class_name OnScreenKeyboard
extends Control
## Controller-only text entry (player name). Mouse keeps using the real
## LineEdit - see StartMenu.gd's name dialog. ASCII-only, no locale needed:
## the name isn't translated.
##
## A physical keyboard also types directly into this (see _input below)
## instead of forcing the player to grid-navigate every letter with the pad -
## no mode swap involved, since ControllerUI.classify_event() already never
## treats InputEventKey as a pointer-mode signal.
##
## Owns its own FocusNav entirely independent of whatever screen instances
## it - the caller just add_child()s this and listens for confirmed/
## cancelled, same shape as a native dialog.

signal confirmed(text: String)
signal cancelled()

const PANEL_SIZE := Vector2(480, 300)
const KEY_SIZE := Vector2(40, 40)
const KEY_GAP := 4.0
const MAX_LENGTH := 20

const ROWS := ["1234567890", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]

var _text := ""
var _shift := true  # ROWS is authored uppercase, so buttons start matching this
var _caret_label: Label
var _key_buttons := {}  # char -> Button, for relabeling on shift toggle
var nav: FocusNav

func _init(initial_text: String = "") -> void:
	_text = initial_text.left(MAX_LENGTH)
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE

func _ready() -> void:
	var font: Font = Game.font_stylish

	var bg := UIPanel.make(PANEL_SIZE)
	add_child(bg)

	_caret_label = Label.new()
	_caret_label.position = UIConstants.KEYBOARD_CARET_LABEL_POS
	_caret_label.size = Vector2(PANEL_SIZE.x - 40, 36)
	_caret_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caret_label.add_theme_font_override("font", font)
	_caret_label.add_theme_font_size_override("font_size", UIConstants.KEYBOARD_CARET_FONT_SIZE)
	_caret_label.add_theme_color_override("font_color", Color.BLACK)
	add_child(_caret_label)

	nav = FocusNav.new()
	add_child(nav)

	var y := UIConstants.KEYBOARD_ROWS_START_Y
	for row in ROWS:
		_add_key_row(row, y, font)
		y += KEY_SIZE.y + KEY_GAP

	_add_action_row(y, font)

	nav.activated.connect(_on_key_activated)
	nav.alt_activated.connect(func(_i): _backspace())      # X = backspace
	nav.alt2_activated.connect(func(_i): _toggle_shift())  # Y = shift
	nav.cancelled.connect(func(): cancelled.emit())
	nav.focus_first()
	_update_caret()

func _add_key_row(chars: String, y: float, font: Font) -> void:
	var row_width := chars.length() * (KEY_SIZE.x + KEY_GAP) - KEY_GAP
	var x := (PANEL_SIZE.x - row_width) * 0.5
	for c in chars:
		var btn := _make_key(c, Vector2(x, y), KEY_SIZE, font)
		nav.add_control(btn, c)
		btn.pressed.connect(_activate.bind(c))
		_key_buttons[c] = btn
		x += KEY_SIZE.x + KEY_GAP

func _add_action_row(y: float, font: Font) -> void:
	var x := UIConstants.KEYBOARD_ACTION_ROW_START_X
	var shift_btn := _make_key("Shift", Vector2(x, y), Vector2(70, KEY_SIZE.y), font, 16)
	nav.add_control(shift_btn, "SHIFT")
	shift_btn.pressed.connect(_activate.bind("SHIFT"))
	x += 70 + KEY_GAP

	var space_btn := _make_key("Space", Vector2(x, y), Vector2(150, KEY_SIZE.y), font, 16)
	nav.add_control(space_btn, "SPACE")
	space_btn.pressed.connect(_activate.bind("SPACE"))
	x += 150 + KEY_GAP

	var back_btn := _make_key("<-", Vector2(x, y), Vector2(70, KEY_SIZE.y), font, 20)
	nav.add_control(back_btn, "BACK")
	back_btn.pressed.connect(_activate.bind("BACK"))
	x += 70 + KEY_GAP

	var done_btn := _make_key(StringTable.get_string(StringTable.ID_OK), Vector2(x, y), Vector2(90, KEY_SIZE.y), font, 16)
	nav.add_control(done_btn, "DONE")
	done_btn.pressed.connect(_activate.bind("DONE"))

func _make_key(label: String, pos: Vector2, key_size: Vector2, font: Font, font_size: int = UIConstants.KEYBOARD_KEY_FONT_SIZE) -> Button:
	var btn := FixedSizeButton.new()
	UIButtonStyle.apply(btn)
	btn.text = label
	btn.position = pos
	btn.size = key_size
	btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color.BLACK)
	add_child(btn)
	return btn

## Runs in the _input phase, ahead of FocusNav's own _unhandled_input - lets
## a physical keyboard type letters straight into _text instead of only
## grid-navigating the on-screen keys. Backspace and Enter are handled here
## specifically because nav_cancel/nav_accept also bind them (see
## ControllerUI._register_actions): left alone, Backspace would close the
## whole keyboard instead of deleting a character, and Enter would type
## whichever key the pad cursor happens to be sitting on instead of
## submitting - both backwards from what typing on a real keyboard expects.
## Escape is deliberately NOT intercepted, it keeps cancelling via
## nav_cancel exactly as before.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_BACKSPACE:
		_backspace()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
		confirmed.emit(_text)
		get_viewport().set_input_as_handled()
		return
	var code := key_event.unicode
	if code >= 32 and code < 127 and _text.length() < MAX_LENGTH:
		_text += char(code)
		_update_caret()
		get_viewport().set_input_as_handled()

func _on_key_activated(item: FocusNav.NavItem) -> void:
	_activate(item.meta)

## Shared by both the pad/keyboard-grid path (_on_key_activated) and a
## direct mouse click (each key's own `pressed`, see _add_key_row/
## _add_action_row) - mouse used to be entirely inert here since these
## buttons were never wired to anything but FocusNav.
func _activate(meta: Variant) -> void:
	match meta:
		"SHIFT": _toggle_shift()
		"SPACE": _append(" ")
		"BACK": _backspace()
		"DONE": confirmed.emit(_text)
		_: _append(String(meta))

func _append(c: String) -> void:
	if _text.length() >= MAX_LENGTH:
		return
	_text += c if _shift else c.to_lower()
	_update_caret()

func _backspace() -> void:
	if _text.is_empty():
		return
	_text = _text.substr(0, _text.length() - 1)
	_update_caret()

func _toggle_shift() -> void:
	_shift = not _shift
	for c in _key_buttons:
		if not (c as String).is_valid_int():
			(_key_buttons[c] as Button).text = c if _shift else (c as String).to_lower()
	_update_caret()

func _update_caret() -> void:
	# Static, not blinking, and "|" not "_" - matches LineEdit's own default
	# caret in mouse mode (a thin vertical bar, caret_blink off) exactly.
	_caret_label.text = _text + "|"
