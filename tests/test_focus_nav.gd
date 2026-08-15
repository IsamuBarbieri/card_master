extends Node
## Checks the controller-navigation logic that CAN be asserted without a
## real pad: the spatial neighbour scorer, layer isolation, device-mode
## classification, and the glyph text-fallback that keeps the game running
## when the button art isn't present.
##
## Must be a .tscn test (not `--script`): it touches the ControllerUI
## autoload, and --script mode does not load autoloads.
## Run: godot --headless --quit-after 20 res://tests/test_focus_nav.tscn

const CELL := Vector2(98, 130)
const GAP := Vector2(14, 6)

## Rebuilds Opponents.gd's real 7x3 grid geometry.
func _grid_rects(cols: int, rows: int) -> Array:
	var out: Array = []
	for r in rows:
		for c in cols:
			out.append(Rect2(Vector2(c * (CELL.x + GAP.x), r * (CELL.y + GAP.y)), CELL))
	return out

func _ready() -> void:
	_test_scorer()
	_test_layers()
	_test_axis_fn()
	_test_classify()
	_test_glyph_fallback()
	_test_focus_by_meta_mixed_types()
	print("OK - focus nav checks passed")
	get_tree().quit()

## Regression: BattleScene mixes int metas (hand slots) and Vector2i metas
## (board cells) in the same nav. GDScript's == throws a runtime error for
## some mismatched Variant type pairs (confirmed for int vs Vector2i) rather
## than just returning false, which used to abort focus_by_meta's whole
## search on the first non-matching item of a different type - silently
## leaving focus wherever it already was. Every other screen so far happened
## to use one meta type consistently, which is why this never tripped until
## a screen mixed two.
func _test_focus_by_meta_mixed_types() -> void:
	var nav := FocusNav.new()
	add_child(nav)
	nav.add_virtual(&"hand", func() -> Rect2: return Rect2(0, 0, 10, 10), 0)
	var board_item := nav.add_virtual(&"board", func() -> Rect2: return Rect2(20, 0, 10, 10), Vector2i(1, 2))
	nav.focus_first()
	assert(nav.current != null and nav.current.meta == 0, "sanity: hand item focused first")

	nav.focus_by_meta(Vector2i(1, 2))
	assert(nav.current == board_item, "focus_by_meta must find a Vector2i meta past an int-meta item without erroring")

	nav.queue_free()

## A slider's left/right must nudge its value instead of moving focus away.
func _test_axis_fn() -> void:
	var nav := FocusNav.new()
	add_child(nav)
	# GDScript lambdas capture outer locals by value, not reference - a
	# plain int wouldn't see mutations from inside the closure. An Array's
	# identity IS captured, so indexing into it works.
	var nudges := [0]
	var a := nav.add_virtual(&"slider", func() -> Rect2: return Rect2(0, 0, 10, 10), "a")
	a.axis_fn = func(d: int) -> void: nudges[0] += d
	nav.add_virtual(&"other", func() -> Rect2: return Rect2(50, 0, 10, 10), "b")
	nav.focus_first()
	assert(nav.current == a)

	nav.move(FocusNav.DIR_RIGHT)
	assert(nudges[0] == 1, "right on a slider should nudge, not move focus")
	assert(nav.current == a, "focus must stay on the slider")

	nav.move(FocusNav.DIR_LEFT)
	assert(nudges[0] == 0)
	assert(nav.current == a)

	nav.queue_free()

func _test_scorer() -> void:
	var rects := _grid_rects(7, 3)  # 21 opponents, indices 0..20 row-major

	# Right from index 0 must land on 1, not on the (equally close by raw
	# distance) cell below it - that's what CROSS_AXIS_PENALTY buys.
	var others := rects.duplicate()
	others.remove_at(0)
	var idx := FocusNav.pick_neighbour(rects[0], others, FocusNav.DIR_RIGHT, false)
	assert(others[idx] == rects[1], "right from 0 should reach 1")

	# Down from 0 -> 7 (same column, next row).
	idx = FocusNav.pick_neighbour(rects[0], others, FocusNav.DIR_DOWN, false)
	assert(others[idx] == rects[7], "down from 0 should reach 7")

	# Column is preserved moving down the middle of the grid: 10 -> 17.
	others = rects.duplicate()
	others.remove_at(10)
	idx = FocusNav.pick_neighbour(rects[10], others, FocusNav.DIR_DOWN, false)
	assert(others[idx] == rects[17], "down from 10 should stay in column -> 17")

	# Nothing above the top row.
	others = rects.duplicate()
	others.remove_at(3)
	idx = FocusNav.pick_neighbour(rects[3], others, FocusNav.DIR_UP, false)
	assert(idx == -1, "no wrap requested, nothing above row 0")

	# ...but with wrap it comes back on the bottom row, same column (3 -> 17).
	idx = FocusNav.pick_neighbour(rects[3], others, FocusNav.DIR_UP, true)
	assert(others[idx] == rects[17], "wrapping up from 3 should land on 17, got %s" % others[idx])

	# Wrapping right off the end of a row stays on that row (6 -> 0).
	others = rects.duplicate()
	others.remove_at(6)
	idx = FocusNav.pick_neighbour(rects[6], others, FocusNav.DIR_RIGHT, true)
	assert(others[idx] == rects[0], "wrapping right from 6 should land on 0, got %s" % others[idx])

	# Empty candidate set never crashes.
	assert(FocusNav.pick_neighbour(rects[0], [], FocusNav.DIR_RIGHT, true) == -1)

func _test_layers() -> void:
	var nav := FocusNav.new()
	add_child(nav)

	var a := nav.add_virtual(&"a", func() -> Rect2: return Rect2(0, 0, 10, 10), "a", 0)
	nav.add_virtual(&"b", func() -> Rect2: return Rect2(20, 0, 10, 10), "b", 0)
	var dlg := nav.add_virtual(&"dlg", func() -> Rect2: return Rect2(0, 100, 10, 10), "dlg", 1)

	nav.focus_first()
	assert(nav.current == a, "layer 0 should focus the first layer-0 item")

	# A dialog opens: only its own item is reachable, and moving can't escape
	# back down to the screen underneath.
	nav.push_layer(1)
	assert(nav.current == dlg, "push_layer(1) should focus the dialog item")
	nav.move(FocusNav.DIR_UP)
	assert(nav.current == dlg, "navigation must not leak out of the active layer")

	nav.pop_layer()
	assert(nav.current == a, "pop_layer should return to the screen")

	# A disabled item is skipped entirely.
	var nav2 := FocusNav.new()
	add_child(nav2)
	nav2.add_virtual(&"off", func() -> Rect2: return Rect2(0, 0, 10, 10), "off", 0,
		func() -> bool: return false)
	var on := nav2.add_virtual(&"on", func() -> Rect2: return Rect2(20, 0, 10, 10), "on", 0)
	nav2.focus_first()
	assert(nav2.current == on, "focus_first must skip a disabled item")

	nav.queue_free()
	nav2.queue_free()

func _test_classify() -> void:
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	assert(ControllerUI.classify_event(pad) == ControllerUI.MODE_GAMEPAD)

	var mouse := InputEventMouseMotion.new()
	assert(ControllerUI.classify_event(mouse) == ControllerUI.MODE_POINTER)

	# A stick resting just off centre must NOT yank the game into gamepad
	# mode - that's the drift case.
	var drift := InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_LEFT_X
	drift.axis_value = ControllerUI.STICK_DEADZONE * 0.5
	assert(ControllerUI.classify_event(drift) == -1, "sub-deadzone drift must not switch mode")

	var pushed := InputEventJoypadMotion.new()
	pushed.axis = JOY_AXIS_LEFT_X
	pushed.axis_value = 1.0
	assert(ControllerUI.classify_event(pushed) == ControllerUI.MODE_GAMEPAD)

	# Something we don't care about leaves the mode alone.
	assert(ControllerUI.classify_event(InputEventAction.new()) == -1)

func _test_glyph_fallback() -> void:
	# Every semantic key the UI can ask for must be mapped.
	for key in [&"A", &"B", &"X", &"Y", &"LB", &"RB", &"START", &"DPAD"]:
		assert(ControllerUI.GLYPH_PATHS.has(key), "missing glyph mapping for %s" % key)

	assert(ControllerUI.glyph(&"NOPE") == null, "unknown key must return null, not crash")

	# The bar must still build (with a text tag instead of an icon) for a key
	# whose art is missing - this is what guarantees the game runs before the
	# glyph pack is installed.
	var bar := ControllerUI.make_prompt_bar([[&"NOPE", "Select"], [&"A", "Confirm"]])
	assert(bar != null and bar.get_child_count() >= 4, "prompt bar should build with a fallback tag")
	var texts: Array[String] = []
	for child in bar.get_children():
		if child is Label:
			texts.append((child as Label).text)
	assert(texts.has("[NOPE]"), "missing glyph should render as a [KEY] text tag, got %s" % [texts])
	bar.queue_free()
