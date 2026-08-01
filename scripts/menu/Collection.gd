extends Control
## Port of UICollection.cs / UICollection.composer.cs (960x544 design
## canvas). Two vertical browse lists (card types, then individual cards of
## the selected type) driving a big preview + stat panel. No drag/state
## machine needed here (pure click-to-browse), so this is much simpler than
## DeckSelect/Shop despite reusing the same CardMatrix grouping.
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
const COLOR_SELECTED := Color(0.12, 0.3, 0.3, 0.7)

var card_matrix := CardMatrix.new()
var sel_type_index := 0
var sel_card_index := 0

var type_rows: Array = []  # Button x N
var card_rows: Array = []  # Button x N (rebuilt per type)

var type_list_box: VBoxContainer
var card_list_box: VBoxContainer

var big_card_view: CardView
var label_value_offense: Label
var label_value_type: Label
var label_value_pdef: Label
var label_value_mdef: Label

var sfx_back: AudioStreamPlayer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	for card in Game.player.cards:
		card.is_on_deck = false
	card_matrix.init(Game.player.cards, false, true)

	_build_ui()

	_select_type(0)

func _build_ui() -> void:
	var font_stylish: Font = load(ASSETS + "fonts/font_stylish.ttf")

	var bg := TextureRect.new()
	bg.texture = load(ASSETS + "common_bkg_clean.png")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	add_child(bg)

	var back_button := _make_button(StringTable.get_string(StringTable.ID_BACK), Vector2(42, 463), Vector2(115, 56), font_stylish)
	back_button.pressed.connect(_on_back_pressed)

	# Label first, icon on top - same "icon has a transparent gap the label
	# shows through" trick as MainMenu's buttons (button_collection.png is
	# the same asset used there).
	var label_collection := _make_label(Vector2(119, 16), Vector2(264, 47), font_stylish, 46)
	label_collection.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_collection.text = StringTable.get_string(StringTable.ID_COLLECTION)
	add_child(label_collection)

	var image_collection := TextureRect.new()
	image_collection.texture = load(ASSETS + "button_collection.png")
	image_collection.stretch_mode = TextureRect.STRETCH_SCALE
	image_collection.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image_collection.position = Vector2(119, 0)
	image_collection.size = Vector2(263, 69)
	image_collection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image_collection)

	big_card_view = CardView.new()
	big_card_view.position = Vector2(561, 21)
	big_card_view.scale = Vector2(384, 512) / Vector2(CARD_W, CARD_H)
	big_card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(big_card_view)

	var type_scroll := ScrollContainer.new()
	type_scroll.position = Vector2(23, 86)
	type_scroll.size = Vector2(204, 287)
	type_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(type_scroll)
	type_list_box = VBoxContainer.new()
	type_list_box.add_theme_constant_override("separation", 0)
	type_list_box.custom_minimum_size = Vector2(204, 0)
	type_scroll.add_child(type_list_box)

	var card_scroll := ScrollContainer.new()
	card_scroll.position = Vector2(270, 86)
	card_scroll.size = Vector2(230, 287)
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(card_scroll)
	card_list_box = VBoxContainer.new()
	card_list_box.add_theme_constant_override("separation", 0)
	card_list_box.custom_minimum_size = Vector2(230, 0)
	card_scroll.add_child(card_list_box)

	var info_bkg := TextureRect.new()
	info_bkg.texture = load(ASSETS + "common_transp_box_a.png")
	info_bkg.stretch_mode = TextureRect.STRETCH_SCALE
	info_bkg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	info_bkg.position = Vector2(236, 375)
	info_bkg.size = Vector2(299, 158)
	add_child(info_bkg)

	var info_offense_lbl := _make_label(Vector2(246, 384), Vector2(153, 31), font_stylish, 25)
	info_offense_lbl.text = StringTable.get_string(StringTable.ID_CARD_ATTACK)
	add_child(info_offense_lbl)
	label_value_offense = _make_label(Vector2(399, 384), Vector2(126, 31), font_stylish, 25)
	label_value_offense.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_value_offense.text = "- - -"
	add_child(label_value_offense)

	var info_type_lbl := _make_label(Vector2(246, 416), Vector2(153, 36), font_stylish, 25)
	info_type_lbl.text = StringTable.get_string(StringTable.ID_CARD_TYPE)
	add_child(info_type_lbl)
	label_value_type = _make_label(Vector2(399, 416), Vector2(126, 36), font_stylish, 25)
	label_value_type.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_value_type.text = "- - -"
	add_child(label_value_type)

	var info_pdef_lbl := _make_label(Vector2(246, 452), Vector2(153, 37), font_stylish, 25)
	info_pdef_lbl.text = StringTable.get_string(StringTable.ID_CARD_PHYSICAL_DEFENSE)
	add_child(info_pdef_lbl)
	label_value_pdef = _make_label(Vector2(399, 452), Vector2(126, 37), font_stylish, 25)
	label_value_pdef.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_value_pdef.text = "- - -"
	add_child(label_value_pdef)

	var info_mdef_lbl := _make_label(Vector2(246, 489), Vector2(153, 34), font_stylish, 25)
	info_mdef_lbl.text = StringTable.get_string(StringTable.ID_CARD_MAGICAL_DEFENSE)
	add_child(info_mdef_lbl)
	label_value_mdef = _make_label(Vector2(399, 489), Vector2(126, 34), font_stylish, 25)
	label_value_mdef.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_value_mdef.text = "- - -"
	add_child(label_value_mdef)

	sfx_back = AudioStreamPlayer.new()
	sfx_back.stream = load(ASSETS + "sfx/button_back_sound.wav")
	add_child(sfx_back)

	_build_type_rows(font_stylish)

func _build_type_rows(font: Font) -> void:
	var card_back_tex: Texture2D = load(ASSETS + "cards/card_back.png")

	for i in card_matrix.card_types.size():
		var row := _make_row(font)
		row.pressed.connect(_select_type.bind(i))
		type_list_box.add_child(row)
		type_rows.append(row)

		var icon := TextureRect.new()
		icon.texture = card_back_tex
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.position = Vector2(4, (ROW_HEIGHT - ROW_IMAGE_SIZE.y) / 2.0)
		icon.size = ROW_IMAGE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)

		var def: CardManager.CardDef = CardManager.defs[card_matrix.card_types[i].original_id]
		var label := _make_row_label(font)
		label.text = def.name
		row.add_child(label)

func _make_row(font: Font) -> Button:
	var row := Button.new()
	row.flat = true
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paint_row(row, COLOR_NORMAL)
	return row

func _make_row_label(font: Font) -> Label:
	var label := Label.new()
	label.position = Vector2(4 + ROW_IMAGE_SIZE.x + 10, 0)
	label.size = Vector2(0, ROW_HEIGHT)
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _paint_row(row: Button, color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	row.add_theme_stylebox_override("normal", sb)
	row.add_theme_stylebox_override("hover", sb)
	row.add_theme_stylebox_override("pressed", sb)

func _make_label(pos: Vector2, label_size: Vector2, font: Font, font_size: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = label_size
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.BLACK)
	label.add_theme_color_override("font_shadow_color", Color(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0, 0.5))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

func _make_button(text: String, pos: Vector2, btn_size: Vector2, font: Font) -> Button:
	var btn := Button.new()
	UIButtonStyle.apply(btn)
	btn.text = text
	btn.position = pos
	btn.size = btn_size
	btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", 25)
	btn.add_theme_color_override("font_color", Color.BLACK)
	btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	btn.add_theme_constant_override("shadow_offset_x", 1)
	btn.add_theme_constant_override("shadow_offset_y", 1)
	add_child(btn)
	return btn

# ------------------------------------------------------------- selection

func _select_type(index: int) -> void:
	sel_type_index = index
	for i in type_rows.size():
		_paint_row(type_rows[i], COLOR_SELECTED if i == index else COLOR_NORMAL)

	for row in card_rows:
		row.queue_free()
	card_rows.clear()

	var font_stylish: Font = load(ASSETS + "fonts/font_stylish.ttf")
	var type_cards: Array = card_matrix.card_types[index].cards
	for i in type_cards.size():
		var row := _make_row(font_stylish)
		row.pressed.connect(_select_card.bind(i))
		card_list_box.add_child(row)
		card_rows.append(row)

		var view := CardView.new()
		view.position = Vector2(4, (ROW_HEIGHT - ROW_IMAGE_SIZE.y) / 2.0)
		view.scale = ROW_IMAGE_SIZE / Vector2(CARD_W, CARD_H)
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.setup(type_cards[i], false, true)
		row.add_child(view)

	sel_card_index = 0
	_select_card(0)

func _select_card(index: int) -> void:
	sel_card_index = index
	for i in card_rows.size():
		_paint_row(card_rows[i], COLOR_SELECTED if i == index else COLOR_NORMAL)

	var card: Card = card_matrix.card_types[sel_type_index].cards[index]

	big_card_view.setup(card, false, true)

	label_value_pdef.text = str(card.physical_defense)
	label_value_mdef.text = str(card.magical_defense)
	label_value_offense.text = str(card.attack_power)
	label_value_type.text = CardManager.attack_type_to_string(card.attack_type)

func _on_back_pressed() -> void:
	sfx_back.play()
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
