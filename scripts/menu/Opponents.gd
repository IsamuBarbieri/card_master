extends Control
## Port of UIOpponents.cs / UIOpponents.composer.cs (960x544 design canvas).
## Uses the real AIManager roster and Game.player.available_opponents, so
## locked opponents show card_back + "???" and Select is disabled for them,
## same as the original.
## Label_Opp_Desc: the original reads AIManager's ai_table.csv Name column
## (UIOpponents.cs:136), which had dev placeholder text ("Enemy 03".."Enemy
## 16") unrelated to the portrait actually shown (that portrait always
## comes from gen_table.csv via CardManager.GenerateNewCard, keyed by
## ai_table.csv's Image ID column) - fixed at the data level (ai_table.csv's
## Name column now matches gen_table.csv's name for that Image ID), but the
## name shown here is still looked up via gen_table directly rather than
## ai.ai_name, so it stays correct even if ai_table.csv drifts again.
## Selection indicator: the reference marks the selected grid item by filling
## its 2px margin ring white (MyListPanelItem.BackgroundColor), which reads
## as barely-there at this scale. Reused DeckSelect's SelectionOutline (a
## drawn double-rect border) instead, one per item so it scrolls for free as
## a child of that item - same visual language as the deck carousel.

const SCREEN_W := 960
const SCREEN_H := 544
const ASSETS := "res://assets/"
const CARD_W := 96
const CARD_H := 128
const ITEM_MARGIN := 2
const ITEM_SIZE := Vector2(CARD_W + ITEM_MARGIN * 2, CARD_H + ITEM_MARGIN * 2)
const GRID_COLUMNS := 7
const LABEL_FONT_SIZE := 36

var opp_count: int
var selected_index := 0
var item_buttons: Array = []       # Button per opponent
var item_portraits: Array = []     # CardView or null (locked) per opponent
var item_overlays: Array = []      # TextureRect (new/defeated badge) per opponent
var item_outlines: Array = []      # SelectionOutline per opponent

var label_desc: Label
var select_button: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	opp_count = AIManager.rage_quit_index()  # aiCount = AIManager.Count - 1, skips RAGEQUIT
	Game.rage_quit_mode = Game.player.match_started
	_build_ui()

	var start_index := 0
	for i in range(opp_count - 1, -1, -1):
		if Game.player.available_opponents[i]:
			start_index = i
			break
	_select(start_index)

func _build_ui() -> void:
	var font_stylish: Font = Game.font_stylish

	var bg := TextureRect.new()
	bg.texture = load(ASSETS + "common_bkg_clean.png")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	add_child(bg)

	var desc_panel := TextureRect.new()
	desc_panel.texture = load(ASSETS + "common_transp_box_a.png")
	desc_panel.stretch_mode = TextureRect.STRETCH_SCALE
	desc_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	desc_panel.position = Vector2(207, 463)
	desc_panel.size = Vector2(545, 56)
	add_child(desc_panel)

	var title := _make_label(Vector2(300, 9), Vector2(359, 36), font_stylish)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = StringTable.get_string(StringTable.ID_OPPONENT_SELECT)
	add_child(title)
	UIButtonStyle.fit_button_text(title)

	label_desc = _make_label(Vector2(231, 473), Vector2(498, 36), font_stylish)
	add_child(label_desc)

	var back_button := _make_text_button(StringTable.get_string(StringTable.ID_BACK), Vector2(42, 463), Vector2(115, 56), font_stylish)
	back_button.pressed.connect(_on_back_pressed)

	select_button = _make_text_button(StringTable.get_string(StringTable.ID_SELECT), Vector2(805, 463), Vector2(115, 56), font_stylish)
	select_button.pressed.connect(_on_select_pressed)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(73, 63)
	scroll.size = Vector2(814, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # GridListScrollOrientation.Vertical
	add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)

	for i in opp_count:
		var item := Button.new()
		item.custom_minimum_size = ITEM_SIZE
		item.flat = true
		item.pressed.connect(_on_item_pressed.bind(i))
		grid.add_child(item)
		item_buttons.append(item)
		item_portraits.append(null)
		item_overlays.append(null)

		_refresh_item(i)

		# Added last so it draws on top of the portrait/overlay.
		var outline := SelectionOutline.new()
		outline.set_anchors_preset(Control.PRESET_FULL_RECT)
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outline.set_target_rect(Rect2(ITEM_MARGIN, ITEM_MARGIN, CARD_W, CARD_H))
		outline.visible = false
		item.add_child(outline)
		item_outlines.append(outline)

func _make_label(pos: Vector2, size: Vector2, font: Font) -> Label:
	var label := FixedSizeLabel.new()
	label.position = pos
	label.size = size
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", Color.BLACK)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

func _make_text_button(label: String, pos: Vector2, size: Vector2, font: Font) -> Button:
	var btn := FixedSizeButton.new()
	UIButtonStyle.apply(btn)
	btn.text = label
	btn.position = pos
	btn.size = size
	btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	btn.add_theme_color_override("font_color", Color.BLACK)
	btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	btn.add_theme_constant_override("shadow_offset_x", 1)
	btn.add_theme_constant_override("shadow_offset_y", 1)
	add_child(btn)
	UIButtonStyle.fit_button_text(btn)
	return btn

# Rebuilds one grid item's portrait/overlay: card_back+"???" if locked,
# else the AI's stat-card portrait plus a new/defeated badge.
func _refresh_item(index: int) -> void:
	var item: Button = item_buttons[index]

	if item_portraits[index] != null:
		item_portraits[index].queue_free()
		item_portraits[index] = null
	if item_overlays[index] != null:
		item_overlays[index].queue_free()
		item_overlays[index] = null

	var portrait: Control
	if Game.player.available_opponents[index]:
		var ai: AIManager.AIData = AIManager.get_ai(index)
		# Matches UIOpponents.cs's listItemUpdator calling AIManager.GetFullAI():
		# just browsing this screen is enough to lazily generate (and persist,
		# once saved) an AI's starting deck, even before ever fighting it.
		AIManager.ensure_dynamic_data(ai)
		var card := CardManager.generate_card(ai.image_id)
		card.owner = 1
		var view := CardView.new()
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.setup(card, false, false)  # renderFlags = 0 in the original: no stats, no arrows
		portrait = view

		var overlay := TextureRect.new()
		overlay.texture = load(ASSETS + ("cards/card_defeated.png" if ai.defeated else "cards/card_new.png"))
		overlay.stretch_mode = TextureRect.STRETCH_SCALE
		overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		overlay.size = Vector2(CARD_W, CARD_H)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(overlay)
		item_overlays[index] = overlay
	else:
		var back := TextureRect.new()
		back.texture = load(ASSETS + "cards/card_back.png")
		back.stretch_mode = TextureRect.STRETCH_SCALE
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.size = Vector2(CARD_W, CARD_H)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait = back

	portrait.position = Vector2(ITEM_MARGIN, ITEM_MARGIN)
	portrait.size = Vector2(CARD_W, CARD_H)
	item.add_child(portrait)
	item_portraits[index] = portrait

func _on_item_pressed(index: int) -> void:
	_select(index)

func _select(index: int) -> void:
	selected_index = index
	Game.opponent_index = index
	for i in item_outlines.size():
		item_outlines[i].visible = (i == index)

	var ai: AIManager.AIData = AIManager.get_ai(index)
	var prefix := StringTable.get_string(StringTable.ID_OPPONENTS_NAME) + " : "
	if Game.player.available_opponents[index]:
		var card_name: String = CardManager.defs[ai.image_id].name
		label_desc.text = prefix + card_name
		select_button.disabled = false
	else:
		label_desc.text = prefix + "???"
		select_button.disabled = true

func _on_back_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_back_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")

func _on_select_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	if Game.rage_quit_mode:
		Game.opponent_index = AIManager.rage_quit_index()
	get_tree().change_scene_to_file("res://scenes/deckselect/DeckSelect.tscn")
