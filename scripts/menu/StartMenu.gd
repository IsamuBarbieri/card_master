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
## name-only bar. Positions/sizes now live in StartMenu.tscn - every label is
## sized to the biggest font that still fits its box rather than an
## arbitrary pick.

## Collection icon grid: gen_table.csv has exactly 21 card types, so a 7x3
## grid (21 cells) covers the whole collection with no overflow/"+N" needed.
## Sized to preserve original 3:4 card aspect ratio (34x45.33).
const COLLECTION_ICON_SIZE := Vector2(34, 45.333)
const COLLECTION_ICON_GAP_X := 4.0
const COLLECTION_ICON_GAP_Y := 8.0
const COLLECTION_COLUMNS := 7

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
## Online names are unique and chosen once - there is no rename - so the name
## is checked against the server while it is being typed and the slot cannot
## be created on a name somebody already holds.
var name_check_dot: Panel
var name_error_label: Label
var name_check_timer: Timer
var name_available := false
const NAME_CHECK_DELAY := 0.45
const NAME_DOT_SIZE := 44.0
const NAME_COLOR_FREE := Color(0.15, 0.65, 0.20)
const NAME_COLOR_TAKEN := Color(0.75, 0.12, 0.10)

func _name_dot_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	var radius := int(NAME_DOT_SIZE / 2.0)
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_color = UIConstants.STARTMENU_SLOT_BORDER_COLOR
	return sb
var name_ok_btn: Button
var name_cancel_btn: Button
var confirm_dialog: Control
var confirm_title_label: Label
var confirm_msg_label: Label
var confirm_ok_btn: Button
var confirm_cancel_btn: Button

var nav: FocusNav
var keyboard: OnScreenKeyboard = null

func _ready() -> void:
	var font_stylish: Font = Game.font_stylish
	for i in 3:
		var slot: FixedSizeButton = get_node("Slot%d" % (i + 1))
		_style_slot_button(slot)
		slot.pressed.connect(_on_slot_pressed.bind(i))
		slot_buttons.append(slot)

		var number_label: Label = slot.get_node("NumberLabel")
		number_label.add_theme_font_override("font", font_stylish)
		number_label.text = str(i + 1)
		slot_number_labels.append(number_label)

		var name_label: Label = slot.get_node("NameLabel")
		name_label.add_theme_font_override("font", font_stylish)
		slot_name_labels.append(name_label)

		var stat_label: Label = slot.get_node("StatLabel")
		stat_label.add_theme_font_override("font", font_stylish)
		slot_stat_labels.append(stat_label)

		var empty_label: Label = slot.get_node("EmptyLabel")
		empty_label.add_theme_font_override("font", font_stylish)
		slot_empty_labels.append(empty_label)

		var slot_text_color: Color = UIConstants.COLOR_SLOT_TEXT
		number_label.add_theme_color_override("font_color", slot_text_color)
		name_label.add_theme_color_override("font_color", slot_text_color)
		stat_label.add_theme_color_override("font_color", slot_text_color)
		empty_label.add_theme_color_override("font_color", slot_text_color)

		# A slot's content is these labels, not the button's own text, so the
		# button has nothing of its own to recolour under the pointer - they
		# are registered so they light up with it like any other button's
		# label does. The coin total keeps its gold.
		for label in [number_label, name_label, stat_label]:
			slot.add_state_label(label)

		var collection_box: Control = slot.get_node("CollectionBox")
		slot_collection_boxes.append(collection_box)

		# Coin total, icon + number the same way the battle end screen and
		# the shop show it (CardManager.card_price's "[center]N [img]..."
		# pattern) rather than a text label.
		var coins_label: RichTextLabel = slot.get_node("CoinsLabel")
		coins_label.add_theme_font_override("normal_font", font_stylish)
		slot_coins_labels.append(coins_label)

		# "New" is what an empty slot shows, so it lights up with the pointer
		# like the filled slots' own labels do.
		slot.add_state_label(empty_label)

		var del: Button = get_node("DeleteButton%d" % (i + 1))
		_style_delete_button(del)
		del.pressed.connect(_on_delete_pressed.bind(i))
		delete_buttons.append(del)

	# Back at the slot list, this copy is holding no save - drop the lock so
	# the other copy can pick it up, and so the list below reads honestly.
	Game.player = null

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
	keyboard = OnScreenKeyboard.new("")
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
	# The pad path skips the text field entirely, so the check that runs while
	# typing never happened - do it here before committing, or a name already
	# taken would sail through on a controller.
	await _check_name_availability()
	if not is_inside_tree():
		return
	if name_ok_btn.disabled:
		# Taken: show the dialog with the cross so the player can see why and
		# pick something else.
		name_dialog.visible = true
		return
	_on_name_ok_pressed()

func _on_keyboard_cancelled() -> void:
	_close_keyboard()
	_on_name_cancel_pressed()

func _style_slot_button(slot: FixedSizeButton) -> void:
	slot.clip_contents = false
	const RADIUS := 14
	const BORDER_W := 4

	# Normal: Dark antique leather panel with bronze frame and soft shadow
	# Normal: Dark antique leather panel with bronze frame
	var normal := StyleBoxFlat.new()
	normal.bg_color = UIConstants.COLOR_SLOT_FILL
	normal.border_width_left = BORDER_W
	normal.border_width_right = BORDER_W
	normal.border_width_top = BORDER_W
	normal.border_width_bottom = BORDER_W
	normal.border_width_left = UIConstants.SLOT_BORDER_WIDTH
	normal.border_width_right = UIConstants.SLOT_BORDER_WIDTH
	normal.border_width_top = UIConstants.SLOT_BORDER_WIDTH
	normal.border_width_bottom = UIConstants.SLOT_BORDER_WIDTH
	normal.border_color = UIConstants.COLOR_SLOT_FRAME
	normal.corner_radius_top_left = RADIUS
	normal.corner_radius_top_right = RADIUS
	normal.corner_radius_bottom_left = RADIUS
	normal.corner_radius_bottom_right = RADIUS
	normal.shadow_color = Color(0, 0, 0, 0.55)
	normal.shadow_size = 8
	normal.shadow_offset = Vector2(0, 4)
	normal.corner_radius_top_left = UIConstants.SLOT_RADIUS
	normal.corner_radius_top_right = UIConstants.SLOT_RADIUS
	normal.corner_radius_bottom_left = UIConstants.SLOT_RADIUS
	normal.corner_radius_bottom_right = UIConstants.SLOT_RADIUS
	normal.shadow_size = 0
	normal.anti_aliasing = true
	normal.anti_aliasing_size = 1.0

	# Hover / Focus: Illuminated dark leather with glowing gold frame and gold glow shadow
	# Hover / Focus: Illuminated dark leather with glowing gold frame
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.26, 0.19, 0.11, 0.98)
	hover.border_width_left = BORDER_W
	hover.border_width_right = BORDER_W
	hover.border_width_top = BORDER_W
	hover.border_width_bottom = BORDER_W
	hover.bg_color = UIConstants.COLOR_BTN_FILL_HOVER
	hover.border_width_left = UIConstants.SLOT_BORDER_WIDTH
	hover.border_width_right = UIConstants.SLOT_BORDER_WIDTH
	hover.border_width_top = UIConstants.SLOT_BORDER_WIDTH
	hover.border_width_bottom = UIConstants.SLOT_BORDER_WIDTH
	hover.border_color = UIConstants.COLOR_SLOT_FRAME_HOVER
	hover.corner_radius_top_left = RADIUS
	hover.corner_radius_top_right = RADIUS
	hover.corner_radius_bottom_left = RADIUS
	hover.corner_radius_bottom_right = RADIUS
	hover.shadow_color = Color(0.95, 0.75, 0.20, 0.55)
	hover.shadow_size = 12
	hover.shadow_offset = Vector2(0, 2)
	hover.corner_radius_top_left = UIConstants.SLOT_RADIUS
	hover.corner_radius_top_right = UIConstants.SLOT_RADIUS
	hover.corner_radius_bottom_left = UIConstants.SLOT_RADIUS
	hover.corner_radius_bottom_right = UIConstants.SLOT_RADIUS
	hover.shadow_size = 0
	hover.anti_aliasing = true
	hover.anti_aliasing_size = 1.0

	# Pressed: Deep sunken dark bronze
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.12, 0.08, 0.05, 0.98)
	pressed.border_width_left = BORDER_W
	pressed.border_width_right = BORDER_W
	pressed.border_width_top = BORDER_W
	pressed.border_width_bottom = BORDER_W
	pressed.border_color = Color(0.38, 0.26, 0.10, 1.0)
	pressed.corner_radius_top_left = RADIUS
	pressed.corner_radius_top_right = RADIUS
	pressed.corner_radius_bottom_left = RADIUS
	pressed.corner_radius_bottom_right = RADIUS
	pressed.shadow_size = 2
	pressed.shadow_offset = Vector2(0, 1)
	pressed.bg_color = UIConstants.COLOR_BTN_FILL_PRESSED
	pressed.border_width_left = UIConstants.SLOT_BORDER_WIDTH
	pressed.border_width_right = UIConstants.SLOT_BORDER_WIDTH
	pressed.border_width_top = UIConstants.SLOT_BORDER_WIDTH
	pressed.border_width_bottom = UIConstants.SLOT_BORDER_WIDTH
	pressed.border_color = UIConstants.COLOR_BTN_BORDER_PRESSED
	pressed.corner_radius_top_left = UIConstants.SLOT_RADIUS
	pressed.corner_radius_top_right = UIConstants.SLOT_RADIUS
	pressed.corner_radius_bottom_left = UIConstants.SLOT_RADIUS
	pressed.corner_radius_bottom_right = UIConstants.SLOT_RADIUS
	pressed.shadow_size = 0
	pressed.anti_aliasing = true
	pressed.anti_aliasing_size = 1.0

	# Disabled: Dimmed charcoal
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.14, 0.12, 0.10, 0.60)
	disabled.border_width_left = BORDER_W
	disabled.border_width_right = BORDER_W
	disabled.border_width_top = BORDER_W
	disabled.border_width_bottom = BORDER_W
	disabled.border_color = Color(0.32, 0.28, 0.24, 0.40)
	disabled.corner_radius_top_left = RADIUS
	disabled.corner_radius_top_right = RADIUS
	disabled.corner_radius_bottom_left = RADIUS
	disabled.corner_radius_bottom_right = RADIUS
	disabled.bg_color = UIConstants.COLOR_BTN_FILL_DISABLED
	disabled.border_width_left = UIConstants.SLOT_BORDER_WIDTH
	disabled.border_width_right = UIConstants.SLOT_BORDER_WIDTH
	disabled.border_width_top = UIConstants.SLOT_BORDER_WIDTH
	disabled.border_width_bottom = UIConstants.SLOT_BORDER_WIDTH
	disabled.border_color = UIConstants.COLOR_BTN_BORDER_DISABLED
	disabled.corner_radius_top_left = UIConstants.SLOT_RADIUS
	disabled.corner_radius_top_right = UIConstants.SLOT_RADIUS
	disabled.corner_radius_bottom_left = UIConstants.SLOT_RADIUS
	disabled.corner_radius_bottom_right = UIConstants.SLOT_RADIUS
	disabled.shadow_size = 0
	disabled.anti_aliasing = true

	slot.add_theme_stylebox_override("normal", normal)
	slot.add_theme_stylebox_override("hover", hover)
	slot.add_theme_stylebox_override("pressed", pressed)
	slot.add_theme_stylebox_override("disabled", disabled)
	slot.add_theme_stylebox_override("focus", hover)
	slot.set_meta(&"style_normal", normal)
	slot.set_meta(&"style_hover", hover)

	slot.add_theme_color_override("font_color", UIConstants.COLOR_SLOT_TEXT)
	slot.add_theme_color_override("font_hover_color", Color.WHITE)
	slot.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	slot.add_theme_color_override("font_pressed_color", UIConstants.COLOR_SLOT_TEXT)

	# Inner gold decorative hairline border
	var inner := Panel.new()
	const INNER_INSET := 6.0
	inner.position = Vector2(INNER_INSET, INNER_INSET)
	inner.size = slot.size - Vector2(INNER_INSET, INNER_INSET) * 2.0
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var inner_style := StyleBoxFlat.new()
	inner_style.bg_color = Color.TRANSPARENT
	inner_style.border_width_left = 1
	inner_style.border_width_right = 1
	inner_style.border_width_top = 1
	inner_style.border_width_bottom = 1
	inner_style.border_color = UIConstants.COLOR_SLOT_INNER_LINE
	inner_style.corner_radius_top_left = 10
	inner_style.corner_radius_top_right = 10
	inner_style.corner_radius_bottom_left = 10
	inner_style.corner_radius_bottom_right = 10
	inner_style.anti_aliasing = true
	inner.add_theme_stylebox_override("panel", inner_style)
	slot.add_child(inner)
	slot.move_child(inner, 0)

func _style_delete_button(btn: Button) -> void:
	# A font glyph instead of button_delete_save.png's raster X: same X at any
	# scale reads crisp (the PNG was low-res and blurred/blocked when the
	# canvas stretched to a real screen size), and colors as plain text
	# theme overrides instead of needing a separately-authored asset.
	btn.text = "X"
	btn.add_theme_font_override("font", Game.font_stylish)
	btn.add_theme_font_size_override("font_size", UIConstants.STARTMENU_DELETE_BUTTON_FONT_SIZE)
	btn.add_theme_color_override("font_color", UIConstants.COLOR_DANGER)
	btn.add_theme_color_override("font_hover_color", UIConstants.COLOR_DANGER_HOVER)
	btn.add_theme_color_override("font_pressed_color", UIConstants.COLOR_DANGER_PRESSED)
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

		# A save another running copy of the game has open can't be loaded here
		# too - both would keep their own copy in memory and each save would
		# wipe out the other's. Greyed out and labelled rather than silently
		# doing nothing when tapped.
		var in_use := occupied and SaveSystem.is_locked(i)
		slot_buttons[i].disabled = in_use
		delete_buttons[i].disabled = in_use

		if occupied:
			slot_name_labels[i].text = summary["name"]
			slot_stat_labels[i].text = "%s: %d\n%s: %d" % [
				StringTable.get_string(StringTable.ID_CARDS), summary["card_count"],
				StringTable.get_string(StringTable.ID_WINS), summary["wins"],
			]
			if in_use:
				slot_stat_labels[i].text = StringTable.get_string(StringTable.ID_SLOT_IN_USE)
			slot_coins_labels[i].text = "[right]%d [img=34x34]%s[/img][/right]" % [summary["coins"], UIConstants.ICON_COIN]
			_rebuild_collection_icons(slot_collection_boxes[i], summary["card_defs"])
		else:
			_rebuild_collection_icons(slot_collection_boxes[i], [])
			slot_empty_labels[i].text = StringTable.get_string(StringTable.ID_NEW)
			UIButtonStyle.fit_button_text(slot_empty_labels[i])

func _load_texture(path: String) -> Texture2D:
	var global_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(global_path):
		var img := Image.new()
		if img.load(global_path) == OK:
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res
	return null

func _rebuild_collection_icons(box: Control, card_defs: Array) -> void:
	for child in box.get_children():
		child.free()

	for idx in card_defs.size():
		var def: CardManager.CardDef = CardManager.defs[card_defs[idx]]
		var icon := TextureRect.new()
		icon.texture = _load_texture(CardView.ASSETS_DIR + def.image)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.size = COLLECTION_ICON_SIZE
		var col := idx % COLLECTION_COLUMNS
		var row := idx / COLLECTION_COLUMNS
		icon.position = Vector2(
			col * (COLLECTION_ICON_SIZE.x + COLLECTION_ICON_GAP_X),
			row * (COLLECTION_ICON_SIZE.y + COLLECTION_ICON_GAP_Y)
		)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)

# --------------------------------------------------------------- dialogs

## Name entry is the one dialog a phone player has to read and type into, so
## it is the widest and the highest on the screen: Android's keyboard eats the
## bottom half, and everything here has to stay above it.
const NAME_DIALOG_SIZE := Vector2(760, 268)

func _build_name_dialog() -> void:
	var font_stylish: Font = Game.font_stylish
	name_dialog = $NameDialog
	var panel: Control = $NameDialog/Panel

	var label: Label = panel.get_node("PromptLabel")
	label.add_theme_font_override("font", font_stylish)
	label.text = StringTable.get_string(StringTable.ID_ENTER_NAME)
	UIButtonStyle.fit_button_text(label)

	name_edit = panel.get_node("NameEdit")
	name_edit.add_theme_font_override("font", font_stylish)
	name_edit.text_changed.connect(_on_name_typed)

	# A filled dot rather than a tick or a cross: at this size a glyph is a few
	# dark pixels either way and the two read alike at a glance, while colour
	# and a solid shape carry across the room. Drawn as a rounded StyleBox so
	# it doesn't depend on a font having the character at all - font_stylish
	# has neither, which is why this was on the default font before.
	name_check_dot = panel.get_node("NameCheckDot")

	# Why the dot is red, when it isn't "somebody has this name".
	name_error_label = panel.get_node("ErrorLabel")
	name_error_label.add_theme_font_override("font", font_stylish)

	# Typing fires per keystroke; the server is asked once the player pauses.
	name_check_timer = Timer.new()
	name_check_timer.one_shot = true
	name_check_timer.wait_time = NAME_CHECK_DELAY
	name_check_timer.timeout.connect(_check_name_availability)
	add_child(name_check_timer)

	# Both buttons on the dialog's last row, inside its 268px height so the
	# whole thing clears an Android keyboard.
	name_ok_btn = panel.get_node("OkButton")
	UIButtonStyle.apply(name_ok_btn)
	name_ok_btn.text = StringTable.get_string(StringTable.ID_OK)
	name_ok_btn.add_theme_font_override("font", font_stylish)
	name_ok_btn.pressed.connect(_on_name_ok_pressed)
	UIButtonStyle.fit_button_text(name_ok_btn)

	name_cancel_btn = panel.get_node("CancelButton")
	UIButtonStyle.apply(name_cancel_btn)
	name_cancel_btn.text = StringTable.get_string(StringTable.ID_CANCEL)
	name_cancel_btn.add_theme_font_override("font", font_stylish)
	name_cancel_btn.pressed.connect(_on_name_cancel_pressed)
	UIButtonStyle.fit_button_text(name_cancel_btn)

func _build_confirm_dialog() -> void:
	var font_stylish: Font = Game.font_stylish
	confirm_dialog = $ConfirmDialog
	var panel: Control = $ConfirmDialog/Panel

	confirm_title_label = panel.get_node("TitleLabel")
	confirm_title_label.add_theme_font_override("font", font_stylish)

	confirm_msg_label = panel.get_node("MsgLabel")
	confirm_msg_label.add_theme_font_override("font", font_stylish)
	confirm_msg_label.text = StringTable.get_string(StringTable.ID_DELETE_SLOT_MSG)

	confirm_ok_btn = panel.get_node("OkButton")
	UIButtonStyle.apply(confirm_ok_btn)
	confirm_ok_btn.text = StringTable.get_string(StringTable.ID_OK)
	confirm_ok_btn.add_theme_font_override("font", font_stylish)
	confirm_ok_btn.pressed.connect(_on_confirm_delete_ok)
	UIButtonStyle.fit_button_text(confirm_ok_btn)

	confirm_cancel_btn = panel.get_node("CancelButton")
	UIButtonStyle.apply(confirm_cancel_btn)
	confirm_cancel_btn.text = StringTable.get_string(StringTable.ID_CANCEL)
	confirm_cancel_btn.add_theme_font_override("font", font_stylish)
	confirm_cancel_btn.pressed.connect(_on_confirm_delete_cancel)
	UIButtonStyle.fit_button_text(confirm_cancel_btn)

# --------------------------------------------------------------- handlers

func _on_slot_pressed(slot_index: int) -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	selected_slot = slot_index

	if slot_names[slot_index] == null:
		nav.push_layer(1)
		_reset_name_check()
		if ControllerUI.is_gamepad():
			_open_keyboard()
		else:
			name_edit.text = ""
			name_dialog.visible = true
	else:
		# Checked again here, not just when the list was drawn: the other copy
		# may have opened this save in the meantime, and this is the last
		# moment before two of them are editing the same file.
		if not SaveSystem.acquire_lock(slot_index):
			_refresh_slots()
			return
		Game.player = SaveSystem.load_player(slot_index)
		get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")

func _reset_name_check() -> void:
	name_available = false
	name_check_dot.visible = false
	name_error_label.text = ""
	_update_name_ok()

func _on_name_typed(_text: String) -> void:
	# The dot goes away while the answer is stale rather than showing the
	# previous name's verdict next to a different name.
	name_available = false
	name_check_dot.visible = false
	_update_name_ok()
	name_check_timer.start()

## Asks the server whether the typed name is free. The reply is dropped if the
## player has kept typing in the meantime, so a slow answer to an old name can
## never mark the current one.
func _check_name_availability() -> void:
	var candidate := name_edit.text.strip_edges()
	if candidate.is_empty():
		_reset_name_check()
		return

	var res := await Net.is_name_available(candidate)
	if not is_inside_tree() or name_edit.text.strip_edges() != candidate:
		return

	name_available = res["ok"] and res["available"]
	name_check_dot.visible = true
	name_check_dot.add_theme_stylebox_override("panel",
		_name_dot_style(NAME_COLOR_FREE if name_available else NAME_COLOR_TAKEN))
	# The reason for a red dot matters: a taken name is the player's to fix, an
	# unreachable server isn't, and without saying so it would look like
	# the name was rejected.
	name_error_label.text = "" if res["ok"] else StringTable.get_string(StringTable.ID_ONLINE_ERROR)
	_update_name_ok()

## OK needs the server's word that the name is free - no connection, no new
## save. Blunt, and deliberately so: the name is chosen once with no rename,
## so letting a slot be created on an unverified name risks stranding it
## offline forever. Playing an EXISTING save offline is unaffected; this gate
## is only on creating one.
func _update_name_ok() -> void:
	name_ok_btn.disabled = not name_available

func _on_name_ok_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	var new_name := name_edit.text.strip_edges()
	if new_name.is_empty():
		new_name = "PlayerName"
	name_dialog.visible = false
	nav.pop_layer()
	Game.player = SaveSystem.create_new_player(selected_slot, new_name)
	_refresh_slots()
	# Claim the name now, not at first online play: between here and then
	# somebody else could take it, and there is no rename to recover with.
	# Offline this simply fails and the claim happens on the first session
	# that does reach the server.
	Net.sign_out()
	await Net.sign_in(selected_slot, new_name)

func _on_name_cancel_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_back_sound.wav")
	name_dialog.visible = false
	nav.pop_layer()

func _on_delete_pressed(slot_index: int) -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	confirm_slot = slot_index
	confirm_title_label.text = StringTable.get_string(StringTable.ID_DELETE_SLOT_TITLE) + ":\n" + str(slot_names[slot_index])
	# Spelled out because it is the part that can't be undone or rebuilt: the
	# local save is one player's own progress, but the online account takes
	# the leaderboard standing and the name with it.
	confirm_msg_label.text = "%s\n%s" % [
		StringTable.get_string(StringTable.ID_DELETE_SLOT_MSG),
		StringTable.get_string(StringTable.ID_DELETE_SLOT_ONLINE)]
	confirm_dialog.visible = true
	nav.push_layer(1)

func _on_confirm_delete_ok() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	confirm_dialog.visible = false
	nav.pop_layer()
	# Server first: the online account has to be given back before the local
	# save goes, both because deleting the save takes the session file with it
	# and because the whole point is to release the name for somebody else.
	await Net.delete_account(confirm_slot)
	if not is_inside_tree():
		return
	SaveSystem.delete_player(confirm_slot)
	_refresh_slots()

func _on_confirm_delete_cancel() -> void:
	Game.play_sfx(ASSETS + "sfx/button_back_sound.wav")
	nav.pop_layer()
	confirm_dialog.visible = false
