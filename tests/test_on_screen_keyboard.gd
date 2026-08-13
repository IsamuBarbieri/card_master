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

	kb.queue_free()
	print("OK - on-screen keyboard checks passed")
	get_tree().quit()

func _fake_item(meta: Variant) -> FocusNav.NavItem:
	var item := FocusNav.NavItem.new()
	item.meta = meta
	return item
