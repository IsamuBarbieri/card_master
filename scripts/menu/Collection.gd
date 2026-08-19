extends Control
## Port of UICollection.cs / UICollection.composer.cs (960x544 design
## canvas). Two vertical browse lists (card types, then individual cards of
## the selected type) driving a big preview + stat panel. Much simpler than
## DeckSelect/Shop despite reusing the same CardMatrix grouping - no drag
## state machine for card placement, just tap-to-select rows (plus drag-to-
## scroll on the lists themselves, a QoL addition not in the reference).
##
## Reuses the normal card art scaled down via CardView's transform instead
## of the reference's separate cards_small/ pre-shrunk asset set (Card.cs's
## "SmallMode"/"BigMode" render flags are just size variants of the same
## composition) - same visual result, no duplicate asset folder needed.
##
## Label text on list rows is left blank: matches the reference's actual
## behavior (Card.cs's `text` field - MyListPanelItem_Card.Text source -
## is never assigned anywhere in the codebase, always blank in a real run).
## The type list's items use the reference's own literal choice of a
## generic card-back icon rather than that type's actual art.

const SCREEN_W := 960
const SCREEN_H := 544
const ASSETS := "res://assets/"
const CARD_W := 96
const CARD_H := 128

const ROW_HEIGHT := 47.0
const ROW_IMAGE_SIZE := Vector2(32, 43)
const COLOR_NORMAL := Color(0.12, 0.12, 0.12, 0.3)
const COLOR_TRANSPARENT := Color(0, 0, 0, 0)
const DRAG_CLICK_THRESHOLD := 6.0

# New QoL addition (not in the reference, which lists individual cards one
# per row like the type list): a grid reads much better once a type has
# more than a couple of copies, and drops the per-row background box since
# the card art alone (no label needed - same type, so same name) is enough.
# 4 columns is the most that fits card_scroll's 230px width without
# crowding info_bkg/big_card_view to its right.
const CARD_GRID_COLUMNS := 4
const CARD_GRID_GAP := 5
const CARD_GRID_CELL := Vector2(50, 67)
const CARD_GRID_ART := Vector2(44, 59)

# Card-stats readout, laid out from the info panel's own box (236,375 299x158)
# rather than per-row hand-tuned positions.
## Rebalanced when the captions went short: the abbreviations need far less
## room than "P. Defense" did, and the value column carries the long strings
## here (the attack type is spelled out in full) - "Физический" needs every
## pixel of it.

var card_matrix := CardMatrix.new()
var sel_type_index := 0
var sel_card_index := 0

var type_rows: Array = []  # Panel x N
var card_rows: Array = []  # Panel x N (rebuilt per type, laid out in a grid)
# Selection is marked with the same blue glow the deck/shop carousels use
# (SelectionOutline), one per item toggled visible, instead of a tinted row
# background - consistent selection language across every browse screen.
var type_outlines: Array = []  # SelectionOutline x N
var card_outlines: Array = []  # SelectionOutline x N

var type_list_box: VBoxContainer
var card_list_box: GridContainer
@onready var type_scroll: ScrollContainer = $TypeScroll
@onready var card_scroll: ScrollContainer = $CardScroll

var big_card_view: CardView
var stat_panel: CardStatPanel

@onready var back_button: Button = $BackButton
@onready var title_label: Label = $TitleLabel
var sfx_back: AudioStreamPlayer
var nav: FocusNav

# New QoL addition (not in the reference, which relies on the thin native
# scrollbar handle): drag anywhere on either list to scroll it, like the
# card wheels elsewhere in the game - rows are non-interactive Panels so
# the ScrollContainer itself gets the input to tell a drag from a tap.
var drag_scroll: ScrollContainer = null
var drag_start_y := 0.0
var drag_start_scroll := 0
var drag_moved := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	for card in Game.player.cards:
		card.is_on_deck = false
	card_matrix.init(Game.player.cards, false, true)
	# New QoL addition (not in the reference, which lists types in whatever
	# order they were first acquired): alphabetical is much easier to browse.
	card_matrix.card_types.sort_custom(func(a: CardMatrix.SameTypeCards, b: CardMatrix.SameTypeCards) -> bool:
		return CardManager.defs[a.original_id].name < CardManager.defs[b.original_id].name)

	_build_ui()
	_setup_nav()  # focus_changed already runs _select_type(0) via focus_by_meta

func _build_ui() -> void:
	var font_stylish: Font = Game.font_stylish

	# font_size 36 to match every other screen's Back button (DeckSelect,
	# Opponents, Options) - this helper's other buttons stay at the default
	# 25, tuned for their own tighter boxes.
	UIButtonStyle.apply(back_button)
	back_button.text = StringTable.get_string(StringTable.ID_BACK)
	back_button.add_theme_font_override("font", font_stylish)
	back_button.add_theme_font_size_override("font_size", UIConstants.BACK_BUTTON_FONT_SIZE)
	back_button.add_theme_color_override("font_color", Color.BLACK)
	back_button.add_theme_color_override("font_shadow_color", UIConstants.COLOR_SHADOW_DIM)
	back_button.add_theme_constant_override("shadow_offset_x", 1)
	back_button.add_theme_constant_override("shadow_offset_y", 1)
	back_button.pressed.connect(_on_back_pressed)
	UIButtonStyle.fit_button_text(back_button)

	# Label first, icon on top - same "icon has a transparent gap the label
	# shows through" trick as MainMenu's buttons (button_collection.png is
	# the same asset used there).
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", Game.font_title)
	title_label.add_theme_font_size_override("font_size", UIConstants.COLLECTION_TITLE_FONT_SIZE)
	title_label.add_theme_color_override("font_color", Color.BLACK)
	title_label.add_theme_color_override("font_shadow_color", UIConstants.COLOR_SHADOW_LIGHT)
	title_label.add_theme_constant_override("shadow_offset_x", 1)
	title_label.add_theme_constant_override("shadow_offset_y", 1)
	title_label.text = StringTable.get_string(StringTable.ID_COLLECTION)
	UIButtonStyle.fit_button_text(title_label)

	big_card_view = CardView.new()
	big_card_view.position = UIConstants.COLLECTION_BIG_CARD_POS
	big_card_view.scale = Vector2(384, 512) / Vector2(CARD_W, CARD_H)
	big_card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(big_card_view)

	type_scroll.gui_input.connect(_on_list_gui_input.bind(type_scroll, func() -> int: return type_rows.size(), _select_type, 1, Vector2(204, ROW_HEIGHT)))
	type_list_box = VBoxContainer.new()
	type_list_box.add_theme_constant_override("separation", 0)
	type_list_box.custom_minimum_size = Vector2(204, 0)
	type_scroll.add_child(type_list_box)

	card_scroll.gui_input.connect(_on_list_gui_input.bind(card_scroll, func() -> int: return card_rows.size(), _select_card, CARD_GRID_COLUMNS, CARD_GRID_CELL + Vector2(CARD_GRID_GAP, CARD_GRID_GAP)))
	card_list_box = GridContainer.new()
	card_list_box.columns = CARD_GRID_COLUMNS
	card_list_box.add_theme_constant_override("h_separation", CARD_GRID_GAP)
	card_list_box.add_theme_constant_override("v_separation", CARD_GRID_GAP)
	card_list_box.custom_minimum_size = Vector2(230, 0)
	card_scroll.add_child(card_list_box)

	# 146 tall (6px margin top and bottom inside the 158px background panel) is
	# the shortest this box can be and still clear the 22px readable floor in
	# every language - Russian's captions are the tightest fit.
	stat_panel = CardStatPanel.make(Vector2(279, 146))
	stat_panel.position = UIConstants.COLLECTION_STAT_PANEL_POS
	add_child(stat_panel)

	sfx_back = AudioStreamPlayer.new()
	sfx_back.stream = load(ASSETS + "sfx/button_back_sound.wav")
	add_child(sfx_back)

	_build_type_rows(font_stylish)

func _build_type_rows(font: Font) -> void:
	var card_back_tex: Texture2D = load(ASSETS + "cards/card_back.png")

	for i in card_matrix.card_types.size():
		var row := _make_row(font)
		type_list_box.add_child(row)
		type_rows.append(row)

		var icon := TextureRect.new()
		icon.texture = card_back_tex
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.position = Vector2(4, (ROW_HEIGHT - ROW_IMAGE_SIZE.y) / 2.0)
		icon.size = ROW_IMAGE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIShadow.behind(row, icon.position, ROW_IMAGE_SIZE, Vector2(1, 2))
		row.add_child(icon)

		var def: CardManager.CardDef = CardManager.defs[card_matrix.card_types[i].original_id]
		var label := _make_row_label(font)
		label.text = def.name
		row.add_child(label)

		# Full row rect (204 = type_list_box's own width, set below), not just
		# the label's - a glow hugging only the text read wrong next to the
		# row's own full-width background tint. Rows sit edge to edge (no
		# separation), so there's no gap for the glow's outward falloff to
		# bleed into without touching the next row - clip it at the row's own
		# bounds instead of the old fix of shrinking the target rect inward
		# (which left the crisp edge looking sized to the text, not the row).
		row.clip_contents = true
		var outline := SelectionOutline.new()
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outline.set_target_rect(Rect2(0, 0, 204, ROW_HEIGHT))
		outline.visible = false
		row.add_child(outline)
		type_outlines.append(outline)

func _setup_nav() -> void:
	nav = FocusNav.new()
	add_child(nav)
	for i in type_rows.size():
		var item := nav.add_control(type_rows[i], i)
		item.id = &"type"
		nav.set_scroll(item, type_scroll)
		# A single-column list: left/right never has a normal meaning here,
		# so it's free to always mean "go to the card grid instead" - the
		# grid rebuilds every time _select_type runs below, so by the time
		# this fires the &"card" items for the CURRENT type already exist.
		nav.link_action(item, FocusNav.DIR_LEFT, func() -> void:
			nav.focus_by_meta(sel_card_index, &"card"))
		nav.link_action(item, FocusNav.DIR_RIGHT, func() -> void:
			nav.focus_by_meta(sel_card_index, &"card"))
	# B already backs out via nav.cancelled below - hide the button itself in
	# gamepad mode rather than also making it a redundant focus stop, and
	# replace it in-place - same row every screen's hints share now
	# (ControllerUI.PROMPT_BAR_Y, matching MainMenu's own A/Select row).
	ControllerUI.hide_in_gamepad(back_button)
	add_child(ControllerUI.make_button_hint(&"B", StringTable.get_string(StringTable.ID_BACK), Vector2(back_button.position.x, ControllerUI.PROMPT_BAR_Y), Vector2(back_button.size.x, ControllerUI.HINT_ROW_HEIGHT)))

	# The cursor moving IS the selection now - no A press needed to preview a
	# type or a card, so there's nothing left for activated to dispatch.
	var on_focus_changed := func(item: FocusNav.NavItem) -> void:
		match item.id:
			&"type": _select_type(item.meta)
			&"card": _select_card(item.meta)
	nav.focus_changed.connect(on_focus_changed)
	nav.cancelled.connect(_on_back_pressed)
	nav.focus_by_meta(sel_type_index, &"type")

func _make_row(font: Font) -> Panel:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Rows are purely visual - mouse events must fall through to the
	# ScrollContainer's own gui_input so it can tell a drag from a tap.
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paint_row(row, COLOR_NORMAL)
	return row

func _make_row_label(font: Font) -> Label:
	var label := Label.new()
	label.position = Vector2(4 + ROW_IMAGE_SIZE.x + 10, 0)
	label.size = Vector2(0, ROW_HEIGHT)
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", UIConstants.COLLECTION_ROW_FONT_SIZE)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _paint_row(row: Panel, color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	row.add_theme_stylebox_override("panel", sb)

# ------------------------------------------------------------- selection

func _select_type(index: int) -> void:
	sel_type_index = index
	for i in type_outlines.size():
		type_outlines[i].visible = (i == index)

	if nav != null:
		nav.remove_by_id(&"card")
	for row in card_rows:
		row.queue_free()
	card_rows.clear()
	card_outlines.clear()
	card_scroll.scroll_vertical = 0

	var type_cards: Array = card_matrix.card_types[index].cards
	for i in type_cards.size():
		var cell := _make_card_cell()
		card_list_box.add_child(cell)
		card_rows.append(cell)

		var view_pos := (CARD_GRID_CELL - CARD_GRID_ART) / 2.0
		UIShadow.behind(cell, view_pos, CARD_GRID_ART, Vector2(1, 2))
		var view := CardView.new()
		view.position = view_pos
		view.scale = CARD_GRID_ART / Vector2(CARD_W, CARD_H)
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.setup(type_cards[i], false, true)
		cell.add_child(view)

		# Added after the view so the glow draws over the card art it rings.
		var outline := SelectionOutline.new()
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outline.set_target_rect(Rect2(view_pos, CARD_GRID_ART))
		outline.visible = false
		cell.add_child(outline)
		card_outlines.append(outline)

		if nav != null:
			var card_item := nav.add_virtual(&"card", (func(c: Control) -> Rect2: return c.get_global_rect()).bind(cell), i, 0, Callable(), cell)
			nav.set_scroll(card_item, card_scroll)
			# Left from the grid's own first column returns to the type list
			# instead of wrapping to the row's last column - the type list is
			# a single column, so nothing else on the card side ever needs
			# left/right; that's what frees it up for this list-to-list jump.
			if i % CARD_GRID_COLUMNS == 0:
				nav.link_action(card_item, FocusNav.DIR_LEFT, func() -> void:
					nav.focus_by_meta(sel_type_index, &"type"))

	sel_card_index = 0
	_select_card(0)

func _make_card_cell() -> Panel:
	var cell := Panel.new()
	cell.custom_minimum_size = CARD_GRID_CELL
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paint_row(cell, COLOR_TRANSPARENT)
	return cell

func _select_card(index: int) -> void:
	sel_card_index = index
	for i in card_outlines.size():
		card_outlines[i].visible = (i == index)

	var card: Card = card_matrix.card_types[sel_type_index].cards[index]

	big_card_view.setup(card, false, true)

	stat_panel.show_card(card)

# Shared by both lists (bound with their own ScrollContainer, row-count
# getter, and select callback): press-and-hold-still is a tap (selects the
# row under the cursor), press-and-drag scrolls instead - same disambiguation
# the wheel widgets elsewhere use, just against a plain vertical offset here.
func _on_list_gui_input(event: InputEvent, scroll: ScrollContainer, row_count: Callable, on_select: Callable, columns: int, cell_pitch: Vector2) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			drag_scroll = scroll
			drag_start_y = event.position.y
			drag_start_scroll = scroll.scroll_vertical
			drag_moved = false
		elif drag_scroll == scroll:
			if not drag_moved:
				var col: int = int(event.position.x / cell_pitch.x)
				var grid_row: int = int((float(scroll.scroll_vertical) + event.position.y) / cell_pitch.y)
				var index: int = grid_row * columns + col
				if col >= 0 and col < columns and index >= 0 and index < row_count.call():
					on_select.call(index)
			drag_scroll = null
	elif event is InputEventMouseMotion and drag_scroll == scroll:
		var dy: float = event.position.y - drag_start_y
		if absf(dy) > DRAG_CLICK_THRESHOLD:
			drag_moved = true
		if drag_moved:
			scroll.scroll_vertical = int(drag_start_scroll - dy)

func _on_back_pressed() -> void:
	sfx_back.play()
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
