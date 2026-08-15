extends Node
## OnScreenKeyboard logic checks - grid completeness, typing, backspace,
## shift, max_length clamp. Doesn't touch StartMenu/save data at all.
## Run: godot --headless --quit-after 10 res://tests/test_on_screen_keyboard.tscn

func _ready() -> void:
	# No duplicate characters across the character rows.
	var seen := {}
	for row in OnScreenKeyboard.ROWS:
		for c in row:
			assert(not seen.has(c), "duplicate key %s" % c)
			seen[c] = true

	var kb := OnScreenKeyboard.new()
	add_child(kb)
	await get_tree().process_frame  # _ready builds the button grid

	assert(kb._text == "")
	kb._backspace()
	assert(kb._text == "", "backspace on empty text must be a no-op")

	# Key buttons always pass the ROWS char as-authored (uppercase) - _shift
	# decides whether _append keeps or lowers it, same as a real key press.
	kb._append("A")
	kb._append("B")
	assert(kb._text == "AB", "typed chars should use the initial shift=true case, got %s" % kb._text)

	kb._toggle_shift()
	kb._append("C")
	assert(kb._text == "ABc", "after shift off, new chars should be lowercase")

	kb._backspace()
	assert(kb._text == "AB")

	for i in OnScreenKeyboard.MAX_LENGTH:
		kb._append("X")
	assert(kb._text.length() == OnScreenKeyboard.MAX_LENGTH, "text must clamp at MAX_LENGTH, got %d" % kb._text.length())

	# Array wrapper: GDScript lambdas capture outer locals by value, so a
	# plain String/bool local wouldn't observe a mutation from inside them.
	var confirmed_text := [""]
	kb.confirmed.connect(func(t): confirmed_text[0] = t)
	var expected_text := kb._text
	kb._on_key_activated(_fake_item("DONE"))
	assert(confirmed_text[0] == expected_text, "DONE key should emit confirmed with the current text")

	var cancelled := [false]
	kb.cancelled.connect(func(): cancelled[0] = true)
	kb.nav.cancelled.emit()
	assert(cancelled[0], "B should emit cancelled")

	# A physical keyboard types directly into the on-screen keyboard - see
	# OnScreenKeyboard._input(). Backspace in particular must delete a
	# character, not cancel: nav_cancel also binds physical Backspace (see
	# ControllerUI._register_actions), so without _input() intercepting it
	# first, typing a correction would silently close the whole dialog.
	var cancel_count := [0]
	kb.cancelled.connect(func(): cancel_count[0] += 1)
	kb._text = ""
	kb._update_caret()
	kb._input(_fake_key_event(KEY_J, 106, false))
	kb._input(_fake_key_event(KEY_O, 111, false))
	assert(kb._text == "jo", "physical letter keys should type straight into _text, got %s" % kb._text)
	kb._input(_fake_key_event(KEY_BACKSPACE, 0, false))
	assert(kb._text == "j", "physical Backspace should delete a char, not cancel, got %s" % kb._text)
	assert(cancel_count[0] == 0, "Backspace must not also fire cancelled")
	# echo (key-repeat) events must be ignored, same as a real held key would
	# otherwise flood _text with repeats.
	kb._input(_fake_key_event(KEY_O, 111, true))
	assert(kb._text == "j", "echoed key events must be ignored")

	# Physical Enter must submit the whole name, not type whichever on-screen
	# key the pad cursor happens to be sitting on (that's what nav_accept
	# would otherwise route it to, same action Space/gamepad A use).
	confirmed_text[0] = ""
	kb.nav.set_focus(kb.nav.items[0])  # a letter key, not DONE
	kb._input(_fake_key_event(KEY_ENTER, 13, false))
	assert(confirmed_text[0] == "j", "physical Enter should confirm with current text, got %s" % confirmed_text[0])
	assert(kb._text == "j", "physical Enter must not also type the focused key")

	# Mouse clicks (a plain Button.pressed, unrelated to FocusNav) used to be
	# entirely inert here - only pad/keyboard nav ever reached _on_key_activated.
	kb._text = ""
	kb._update_caret()
	(kb._key_buttons["Z"] as Button).pressed.emit()
	assert(kb._text == "z", "clicking a letter key with the mouse should type it (shift is off), got %s" % kb._text)

	kb.queue_free()
	print("OK - on-screen keyboard checks passed")
	get_tree().quit()

func _fake_item(meta: Variant) -> FocusNav.NavItem:
	var item := FocusNav.NavItem.new()
	item.meta = meta
	return item

func _fake_key_event(keycode: Key, unicode: int, echo: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.unicode = unicode
	ev.pressed = true
	ev.echo = echo
	return ev
