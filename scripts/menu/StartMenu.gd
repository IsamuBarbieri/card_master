extends Control
## Port of UIStartMenu.cs / UIStartMenu.composer.cs (960x544 design canvas).
## 3-slot save select: each slot shows "New" (empty) or the saved player's
## name, with a delete (X) button next to occupied slots. Tapping an empty
## slot opens a name-entry dialog; tapping an occupied slot loads it and
## goes straight to MainMenu.
##
## Matched as-is even though it reads a little clunky: per DialogClose() in
## the reference, confirming a new name does NOT itself proceed to
## MainMenu - it only saves the new player and re-labels the slot. Entering
## the game requires tapping the now-named slot a second time.
##
## UINewPlayer/the delete confirmation are native PSM Dialog/MessageDialog
## widgets with no composer layout to copy for their background chrome (no
## CustomImage set - see UIButtonStyle.gd's docstring on that same "no
## CustomImage still means a real skin" pattern for buttons) - styled here
## with the game's existing common_transp_box_a.png panel look instead of
## guessing at the engine's actual default dialog skin.

const SCREEN_W := 960
const SCREEN_H := 544
const ASSETS := "res://assets/"

const SLOT_POSITIONS := [Vector2(344, 115), Vector2(344, 240), Vector2(344, 362)]
const SLOT_SIZE := Vector2(271, 71)
const DELETE_POSITIONS := [Vector2(660, 130), Vector2(660, 251), Vector2(660, 376)]
const DELETE_SIZE := Vector2(42, 42)

var slot_buttons: Array = []    # Button x3
var delete_buttons: Array = []  # Button x3
var slot_names: Array = [null, null, null]

var selected_slot := -1
var confirm_slot := -1

var name_dialog: Control
var name_edit: LineEdit
var confirm_dialog: Control
var confirm_title_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := TextureRect.new()
	bg.texture = load(ASSETS + "common_bkg_dark_clean.png")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	add_child(bg)

	var font_stylish: Font = load(ASSETS + "fonts/font_stylish.ttf")
	for i in 3:
		var slot := Button.new()
		UIButtonStyle.apply(slot)
		slot.position = SLOT_POSITIONS[i]
		slot.size = SLOT_SIZE
		slot.add_theme_font_override("font", font_stylish)
		slot.add_theme_font_size_override("font_size", 36)
		slot.add_theme_color_override("font_color", Color.BLACK)
		slot.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
		slot.add_theme_constant_override("shadow_offset_x", 1)
		slot.add_theme_constant_override("shadow_offset_y", 1)
		slot.pressed.connect(_on_slot_pressed.bind(i))
		add_child(slot)
		slot_buttons.append(slot)

		var del := _make_delete_button(DELETE_POSITIONS[i])
		del.pressed.connect(_on_delete_pressed.bind(i))
		add_child(del)
		delete_buttons.append(del)

	_build_name_dialog()
	_build_confirm_dialog()
	_refresh_slots()

	Game.play_music(ASSETS + "music/menu1.mp3")

func _make_delete_button(pos: Vector2) -> Button:
	var btn := Button.new()
	btn.position = pos
	btn.size = DELETE_SIZE
	btn.icon = load(ASSETS + "button_delete_save.png")
	btn.expand_icon = true
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER

	var normal := StyleBoxTexture.new()
	normal.texture = load(ASSETS + "button_9patch_normal.png")
	normal.texture_margin_left = 21
	normal.texture_margin_right = 21
	normal.texture_margin_top = 21
	normal.texture_margin_bottom = 21
	normal.content_margin_left = 4
	normal.content_margin_right = 4
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", normal)

	var pressed := StyleBoxTexture.new()
	pressed.texture = load(ASSETS + "button_9patch_press.png")
	pressed.texture_margin_left = 21
	pressed.texture_margin_right = 21
	pressed.texture_margin_top = 21
	pressed.texture_margin_bottom = 21
	pressed.content_margin_left = 4
	pressed.content_margin_right = 4
	pressed.content_margin_top = 4
	pressed.content_margin_bottom = 4
	btn.add_theme_stylebox_override("pressed", pressed)

	return btn

func _refresh_slots() -> void:
	var names := SaveSystem.check_existing_players()
	for i in 3:
		slot_names[i] = names[i]
		if names[i] != null:
			slot_buttons[i].text = names[i]
			delete_buttons[i].visible = true
		else:
			slot_buttons[i].text = StringTable.get_string(StringTable.ID_NEW)
			delete_buttons[i].visible = false

# --------------------------------------------------------------- dialogs

func _build_dialog_shell(panel_size: Vector2) -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Vector2(SCREEN_W, SCREEN_H)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)

	var panel := Control.new()
	panel.position = (Vector2(SCREEN_W, SCREEN_H) - panel_size) / 2.0
	panel.size = panel_size
	overlay.add_child(panel)

	var panel_bg := TextureRect.new()
	panel_bg.texture = load(ASSETS + "common_transp_box_a.png")
	panel_bg.stretch_mode = TextureRect.STRETCH_SCALE
	panel_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel_bg.size = panel_size
	panel.add_child(panel_bg)

	add_child(overlay)
	overlay.set_meta("panel", panel)
	return overlay

func _make_dialog_label(pos: Vector2, label_size: Vector2, font: Font) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = label_size
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 25)
	label.add_theme_color_override("font_color", Color.BLACK)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

func _make_dialog_button(text: String, pos: Vector2, btn_size: Vector2, font: Font) -> Button:
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
	return btn

func _build_name_dialog() -> void:
	var font_stylish: Font = load(ASSETS + "fonts/font_stylish.ttf")
	name_dialog = _build_dialog_shell(Vector2(500, 300))
	var panel: Control = name_dialog.get_meta("panel")

	var label := _make_dialog_label(Vector2(70, 51), Vector2(359, 37), font_stylish)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = StringTable.get_string(StringTable.ID_ENTER_NAME)
	panel.add_child(label)

	name_edit = LineEdit.new()
	name_edit.position = Vector2(70, 134)
	name_edit.size = Vector2(360, 56)
	name_edit.text = "PlayerName"
	name_edit.max_length = 20
	name_edit.add_theme_font_override("font", font_stylish)
	name_edit.add_theme_font_size_override("font_size", 25)
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(name_edit)

	var ok_btn := _make_dialog_button(StringTable.get_string(StringTable.ID_OK), Vector2(19, 225), Vector2(214, 56), font_stylish)
	ok_btn.pressed.connect(_on_name_ok_pressed)
	panel.add_child(ok_btn)

	var cancel_btn := _make_dialog_button(StringTable.get_string(StringTable.ID_CANCEL), Vector2(267, 225), Vector2(214, 56), font_stylish)
	cancel_btn.pressed.connect(_on_name_cancel_pressed)
	panel.add_child(cancel_btn)

func _build_confirm_dialog() -> void:
	var font_stylish: Font = load(ASSETS + "fonts/font_stylish.ttf")
	confirm_dialog = _build_dialog_shell(Vector2(360, 260))
	var panel: Control = confirm_dialog.get_meta("panel")

	confirm_title_label = _make_dialog_label(Vector2(15, 20), Vector2(330, 60), font_stylish)
	confirm_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(confirm_title_label)

	var msg_label := _make_dialog_label(Vector2(15, 95), Vector2(330, 90), font_stylish)
	msg_label.add_theme_font_size_override("font_size", 20)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	msg_label.text = StringTable.get_string(StringTable.ID_DELETE_SLOT_MSG)
	panel.add_child(msg_label)

	var ok_btn := _make_dialog_button(StringTable.get_string(StringTable.ID_OK), Vector2(23, 190), Vector2(150, 56), font_stylish)
	ok_btn.pressed.connect(_on_confirm_delete_ok)
	panel.add_child(ok_btn)

	var cancel_btn := _make_dialog_button(StringTable.get_string(StringTable.ID_CANCEL), Vector2(187, 190), Vector2(150, 56), font_stylish)
	cancel_btn.pressed.connect(_on_confirm_delete_cancel)
	panel.add_child(cancel_btn)

# --------------------------------------------------------------- handlers

func _on_slot_pressed(slot_index: int) -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	selected_slot = slot_index

	if slot_names[slot_index] == null:
		name_edit.text = "PlayerName"
		name_dialog.visible = true
	else:
		Game.player = SaveSystem.load_player(slot_index)
		get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")

func _on_name_ok_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	var new_name := name_edit.text.strip_edges()
	if new_name.is_empty():
		new_name = "PlayerName"
	name_dialog.visible = false
	Game.player = SaveSystem.create_new_player(selected_slot, new_name)
	_refresh_slots()

func _on_name_cancel_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_back_sound.wav")
	name_dialog.visible = false

func _on_delete_pressed(slot_index: int) -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	confirm_slot = slot_index
	confirm_title_label.text = StringTable.get_string(StringTable.ID_DELETE_SLOT_TITLE) + ":\n" + str(slot_names[slot_index])
	confirm_dialog.visible = true

func _on_confirm_delete_ok() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	SaveSystem.delete_player(confirm_slot)
	confirm_dialog.visible = false
	_refresh_slots()

func _on_confirm_delete_cancel() -> void:
	Game.play_sfx(ASSETS + "sfx/button_back_sound.wav")
	confirm_dialog.visible = false
