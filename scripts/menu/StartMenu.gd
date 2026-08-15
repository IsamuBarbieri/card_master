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

## Spyro-remake-style save select: 3 tall vertical slot cards side by side
## (layout/functionality idea only - our own panel art, fonts and colors),
## each numbered and showing name + stats, instead of the reference's thin
## name-only bar. Sized as large as the 960x544 canvas allows (not the
## original StartMenu's small name-only bar) since "canvas_items" stretch
## scales this canvas up to fill the real screen - on a phone, small design-
## canvas text reads as genuinely tiny, so every label below is sized to the
## biggest font that still fits its box rather than an arbitrary pick.
const SLOT_POSITIONS := [Vector2(40, 42), Vector2(340, 42), Vector2(640, 42)]
const SLOT_SIZE := Vector2(280, 460)
const DELETE_SIZE := Vector2(48, 48)
const DELETE_MARGIN := 6.0  # gap from the card's top-right corner, both axes

## Collection icon grid: gen_table.csv has exactly 21 card types, so a 7x3
## grid (21 cells) covers the whole collection with no overflow/"+N" needed
## - icon size/gap are picked to fill COLLECTION_BOX_SIZE exactly at 7x3, so
## a full collection tiles the box precisely with no leftover slack. Sized up
## from the original 33x44/256x140 now that dropping the "Collection:" text
## label (redundant once the row below it is obviously a card grid) freed
## enough vertical room to grow the icons within the same 7-wide layout the
## slot's width was already tuned for.
const COLLECTION_ICON_SIZE := Vector2(35, 47)
const COLLECTION_ICON_GAP := 4.0
const COLLECTION_COLUMNS := 7
const COLLECTION_BOX_SIZE := Vector2(269, 149)

var slot_buttons: Array = []        # Button x3
var slot_number_labels: Array = []  # Label x3 ("1"/"2"/"3"), always visible
var slot_name_labels: Array = []    # Label x3
var slot_stat_labels: Array = []    # Label x3 ("Cards: N\nWins: N")
var slot_collection_boxes: Array = []   # Control x3, holds the icon grid
var slot_coins_labels: Array = []   # RichTextLabel x3, coin icon + amount, bottom of card
var slot_empty_labels: Array = []   # Label x3 ("New", centered - empty slots only)
var delete_buttons: Array = []      # Button x3
var slot_names: Array = [null, null, null]

var selected_slot := -1
var confirm_slot := -1

var name_dialog: Control
var name_edit: LineEdit
var name_ok_btn: Button
var name_cancel_btn: Button
var confirm_dialog: Control
var confirm_title_label: Label
var confirm_ok_btn: Button
var confirm_cancel_btn: Button

var nav: FocusNav
var keyboard: OnScreenKeyboard = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := TextureRect.new()
	bg.texture = load(ASSETS + "common_bkg_dark_clean.png")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	add_child(bg)

	var font_stylish: Font = Game.font_stylish
	for i in 3:
		var slot := FixedSizeButton.new()
		UIButtonStyle.apply(slot)
		slot.position = SLOT_POSITIONS[i]
		slot.size = SLOT_SIZE
		slot.pressed.connect(_on_slot_pressed.bind(i))
		add_child(slot)
		slot_buttons.append(slot)

		var number_label := _make_dialog_label(Vector2(0, 6), Vector2(SLOT_SIZE.x, 46), font_stylish)
		number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number_label.add_theme_font_size_override("font_size", 38)
		number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		number_label.text = str(i + 1)
		slot.add_child(number_label)
		slot_number_labels.append(number_label)

		var name_label := _make_dialog_label(Vector2(12, 56), Vector2(SLOT_SIZE.x - 24, 40), font_stylish)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 30)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(name_label)
		slot_name_labels.append(name_label)

		var stat_label := _make_dialog_label(Vector2(12, 100), Vector2(SLOT_SIZE.x - 24, 62), font_stylish)
		stat_label.add_theme_font_size_override("font_size", 24)
		stat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(stat_label)
		slot_stat_labels.append(stat_label)

		# No "Collection:" caption above the grid - a row of card portraits
		# reads as a collection on its own, and dropping the label frees the
		# room COLLECTION_ICON_SIZE above grew into.
		var collection_box := Control.new()
		collection_box.position = Vector2(6, 172)
		collection_box.size = COLLECTION_BOX_SIZE
		collection_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(collection_box)
		slot_collection_boxes.append(collection_box)

		# Coin total, icon + number the same way the battle end screen and
		# the shop show it (CardManager.card_price's "[center]N [img]..."
		# pattern) rather than a text label. Bottom of the card - grown into
		# the strip the last-saved date used to occupy below it.
		var coins_label := RichTextLabel.new()
		coins_label.bbcode_enabled = true
		coins_label.scroll_active = false
		coins_label.position = Vector2(12, SLOT_SIZE.y - 60)
		coins_label.size = Vector2(SLOT_SIZE.x - 24, 48)
		coins_label.add_theme_font_override("normal_font", font_stylish)
		coins_label.add_theme_font_size_override("normal_font_size", 34)
		coins_label.add_theme_color_override("default_color", Color(1, 0.85, 0.1))
		coins_label.add_theme_constant_override("outline_size", 3)
		coins_label.add_theme_color_override("font_outline_color", Color.BLACK)
		coins_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(coins_label)
		slot_coins_labels.append(coins_label)

		var empty_label := _make_dialog_label(Vector2(0, 52), Vector2(SLOT_SIZE.x, SLOT_SIZE.y - 52), font_stylish)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 40)
		empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(empty_label)
		slot_empty_labels.append(empty_label)

		var del := _make_delete_button(SLOT_POSITIONS[i] + Vector2(SLOT_SIZE.x - DELETE_SIZE.x - DELETE_MARGIN, DELETE_MARGIN))
		del.pressed.connect(_on_delete_pressed.bind(i))
		add_child(del)
		delete_buttons.append(del)

	_build_name_dialog()
	_build_confirm_dialog()
	_refresh_slots()
	_setup_nav()

	# X already deletes a focused slot directly (see alt_activated in
	# _setup_nav) - the info panel underneath is enough, this small corner X
	# is just mouse/touch clutter once the prompt bar spells the same action
	# out. _refresh_slots also gates delete_buttons on `occupied`, so mode is
	# folded in there rather than a plain hide_in_gamepad per button.
	ControllerUI.mode_changed.connect(func(_m: int) -> void: _refresh_slots())

	Game.play_music(ASSETS + "music/menu1.mp3")

## Layer 0 = the 3 slots. Layer 1 = whichever dialog is open - both dialogs'
## OK/Cancel share it since only one is ever visible at a time (enabled_fn
## already excludes the hidden one).
func _setup_nav() -> void:
	nav = FocusNav.new()
	add_child(nav)
	for i in 3:
		nav.add_control(slot_buttons[i], i)
	nav.add_control(name_ok_btn, "name_ok", 1)
	nav.add_control(name_cancel_btn, "name_cancel", 1)
	nav.add_control(confirm_ok_btn, "confirm_ok", 1)
	nav.add_control(confirm_cancel_btn, "confirm_cancel", 1)

	nav.activated.connect(func(item: FocusNav.NavItem) -> void:
		(item.control as Button).pressed.emit())
	# X on a focused occupied slot deletes it, instead of making the small
	# corner X button separately focusable.
	nav.alt_activated.connect(func(item: FocusNav.NavItem) -> void:
		# Check occupancy directly instead of delete_buttons[i].visible - that
		# button is hidden in gamepad mode (mouse-only corner X, see
		# _refresh_slots), which used to make X do nothing on a pad entirely.
		if item.control is FixedSizeButton and item.meta is int and not SaveSystem.slot_summary(item.meta).is_empty():
			_on_delete_pressed(item.meta))
	nav.cancelled.connect(func() -> void:
		if nav.get_layer() == 1:
			if name_dialog.visible:
				_on_name_cancel_pressed()
			elif confirm_dialog.visible:
				_on_confirm_delete_cancel())
	nav.focus_first()

	add_child(ControllerUI.make_prompt_bar([
		[&"A", StringTable.get_string(StringTable.ID_SELECT)],
		[&"X", StringTable.get_string(StringTable.ID_DELETE_SLOT_TITLE)],
	]))

func _open_keyboard() -> void:
	keyboard = OnScreenKeyboard.new("PlayerName")
	keyboard.position = (Vector2(SCREEN_W, SCREEN_H) - OnScreenKeyboard.PANEL_SIZE) / 2.0
	add_child(keyboard)
	nav.active = false
	ControllerUI.hide_hand()
	keyboard.confirmed.connect(_on_keyboard_confirmed)
	keyboard.cancelled.connect(_on_keyboard_cancelled)

func _close_keyboard() -> void:
	keyboard.queue_free()
	keyboard = null
	nav.active = true

func _on_keyboard_confirmed(text: String) -> void:
	_close_keyboard()
	name_edit.text = text
	_on_name_ok_pressed()

func _on_keyboard_cancelled() -> void:
	_close_keyboard()
	_on_name_cancel_pressed()

func _make_delete_button(pos: Vector2) -> Button:
	var btn := Button.new()
	btn.position = pos
	btn.size = DELETE_SIZE
	# A font glyph instead of button_delete_save.png's raster X: same X at any
	# scale reads crisp (the PNG was low-res and blurred/blocked when the
	# canvas stretched to a real screen size), and colors as plain text
	# theme overrides instead of needing a separately-authored asset.
	btn.text = "X"
	btn.add_theme_font_override("font", Game.font_stylish)
	btn.add_theme_font_size_override("font_size", 34)
	btn.add_theme_color_override("font_color", Color(0.85, 0.1, 0.1))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.25, 0.25))
	btn.add_theme_color_override("font_pressed_color", Color(0.6, 0.0, 0.0))
	btn.add_theme_color_override("font_outline_color", Color.BLACK)
	btn.add_theme_constant_override("outline_size", 3)

	# No panel chrome here - it sits directly on the big slot card button
	# below it, so the usual 9-patch background read as a button-on-a-button.
	# Just the bare X glyph is the pressable area.
	var empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus", empty)

	return btn

func _refresh_slots() -> void:
	for i in 3:
		var summary := SaveSystem.slot_summary(i)
		var occupied := not summary.is_empty()

		slot_names[i] = summary.get("name")
		slot_name_labels[i].visible = occupied
		slot_stat_labels[i].visible = occupied
		slot_collection_boxes[i].visible = occupied
		slot_coins_labels[i].visible = occupied
		slot_empty_labels[i].visible = not occupied
		delete_buttons[i].visible = occupied and not ControllerUI.is_gamepad()

		if occupied:
			slot_name_labels[i].text = summary["name"]
			slot_stat_labels[i].text = "%s: %d\n%s: %d" % [
				StringTable.get_string(StringTable.ID_CARDS), summary["card_count"],
				StringTable.get_string(StringTable.ID_WINS), summary["wins"],
			]
			slot_coins_labels[i].text = "[right]%d [img=34x34]res://assets/coins_icon.png[/img][/right]" % summary["coins"]
			_rebuild_collection_icons(slot_collection_boxes[i], summary["card_defs"])
		else:
			_rebuild_collection_icons(slot_collection_boxes[i], [])
			slot_empty_labels[i].text = StringTable.get_string(StringTable.ID_NEW)
			UIButtonStyle.fit_button_text(slot_empty_labels[i])

func _rebuild_collection_icons(box: Control, card_defs: Array) -> void:
	for child in box.get_children():
		child.free()

	var pitch: Vector2 = COLLECTION_ICON_SIZE + Vector2(COLLECTION_ICON_GAP, COLLECTION_ICON_GAP)
	for idx in card_defs.size():
		var def: CardManager.CardDef = CardManager.defs[card_defs[idx]]
		var icon := TextureRect.new()
		icon.texture = load(CardView.ASSETS_DIR + def.image)
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.size = COLLECTION_ICON_SIZE
		icon.position = Vector2(idx % COLLECTION_COLUMNS, idx / COLLECTION_COLUMNS) * pitch
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)

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
	var label := FixedSizeLabel.new()
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
	var btn := FixedSizeButton.new()
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
	UIButtonStyle.fit_button_text(btn)
	return btn

func _build_name_dialog() -> void:
	var font_stylish: Font = Game.font_stylish
	name_dialog = _build_dialog_shell(Vector2(500, 300))
	var panel: Control = name_dialog.get_meta("panel")

	var label := _make_dialog_label(Vector2(70, 51), Vector2(359, 37), font_stylish)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = StringTable.get_string(StringTable.ID_ENTER_NAME)
	panel.add_child(label)
	UIButtonStyle.fit_button_text(label)

	name_edit = LineEdit.new()
	name_edit.position = Vector2(70, 134)
	name_edit.size = Vector2(360, 56)
	name_edit.text = "PlayerName"
	name_edit.max_length = 20
	name_edit.add_theme_font_override("font", font_stylish)
	name_edit.add_theme_font_size_override("font_size", 25)
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(name_edit)

	name_ok_btn = _make_dialog_button(StringTable.get_string(StringTable.ID_OK), Vector2(19, 225), Vector2(214, 56), font_stylish)
	name_ok_btn.pressed.connect(_on_name_ok_pressed)
	panel.add_child(name_ok_btn)

	name_cancel_btn = _make_dialog_button(StringTable.get_string(StringTable.ID_CANCEL), Vector2(267, 225), Vector2(214, 56), font_stylish)
	name_cancel_btn.pressed.connect(_on_name_cancel_pressed)
	panel.add_child(name_cancel_btn)

func _build_confirm_dialog() -> void:
	var font_stylish: Font = Game.font_stylish
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

	confirm_ok_btn = _make_dialog_button(StringTable.get_string(StringTable.ID_OK), Vector2(23, 190), Vector2(150, 56), font_stylish)
	confirm_ok_btn.pressed.connect(_on_confirm_delete_ok)
	panel.add_child(confirm_ok_btn)

	confirm_cancel_btn = _make_dialog_button(StringTable.get_string(StringTable.ID_CANCEL), Vector2(187, 190), Vector2(150, 56), font_stylish)
	confirm_cancel_btn.pressed.connect(_on_confirm_delete_cancel)
	panel.add_child(confirm_cancel_btn)

# --------------------------------------------------------------- handlers

func _on_slot_pressed(slot_index: int) -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	selected_slot = slot_index

	if slot_names[slot_index] == null:
		nav.push_layer(1)
		if ControllerUI.is_gamepad():
			_open_keyboard()
		else:
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
	nav.pop_layer()
	Game.player = SaveSystem.create_new_player(selected_slot, new_name)
	_refresh_slots()

func _on_name_cancel_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_back_sound.wav")
	name_dialog.visible = false
	nav.pop_layer()

func _on_delete_pressed(slot_index: int) -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	confirm_slot = slot_index
	confirm_title_label.text = StringTable.get_string(StringTable.ID_DELETE_SLOT_TITLE) + ":\n" + str(slot_names[slot_index])
	confirm_dialog.visible = true
	nav.push_layer(1)

func _on_confirm_delete_ok() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	SaveSystem.delete_player(confirm_slot)
	confirm_dialog.visible = false
	nav.pop_layer()
	_refresh_slots()

func _on_confirm_delete_cancel() -> void:
	Game.play_sfx(ASSETS + "sfx/button_back_sound.wav")
	nav.pop_layer()
	confirm_dialog.visible = false
