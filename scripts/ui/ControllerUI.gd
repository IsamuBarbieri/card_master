extends Node
## Autoload (declared last - reads Game.font_stylish). Owns everything that is
## global to controller support:
##   - which device the player is currently using (pointer vs gamepad),
##   - the "hand" cursor that snaps onto whatever FocusNav has focused,
##   - the button-glyph lookup and the on-screen prompt bar.
##
## Per-screen navigation lives in FocusNav (scripts/ui/FocusNav.gd) instead;
## this class deliberately knows nothing about any individual screen.
##
## The InputMap actions are registered here in code rather than written into
## project.godot's [input] section: that section stores serialized
## InputEvent objects, which is both unreadable and easy to corrupt by hand,
## and this project builds all of its UI in code anyway. The trade-off is
## that the actions don't show up in the editor's Input Map panel.

signal mode_changed(new_mode: int)

enum { MODE_POINTER, MODE_GAMEPAD }

## Below this, a resting-but-drifting stick must not flip the game into
## gamepad mode (or fire navigation).
const STICK_DEADZONE := 0.35
## Shared auto-repeat timing so every screen scrolls at the same speed.
const NAV_REPEAT_DELAY := 0.38
const NAV_REPEAT_RATE := 0.11

const HAND_TEXTURE_PATH := "res://assets/cursor.png"
const HAND_SIZE := Vector2(40, 40)
## The fingertip's landing spot within the target rect, as a fraction of its
## size: bottom-right corner. Center-ish fractions read as "correct" on some
## rect sizes and "off" on others depending on aspect ratio; the corner is
## the one spot that's unambiguous regardless of the target's shape.
const HAND_ANCHOR_FRACTION := Vector2(1.0, 1.0)
const HAND_TWEEN_TIME := 0.07
## Idle bob: a small diagonal nudge toward/away from the anchor point along
## the same up-left/down-right line the hand travels in on arrival, so it
## keeps reading as "still pointing at this" rather than a static decal.
const HAND_BOB := Vector2(4.0, 4.0)
const HAND_BOB_TIME := 0.55

## The single indirection point for button art. Only these paths need to
## change if the glyph set is ever swapped; everything else refers to the
## semantic key. Sourced from Kenney's Input Prompts (CC0) - the pack itself
## is gitignored, these few files are copied into assets/prompts/.
const GLYPH_PATHS := {
	&"A": "res://assets/prompts/xbox_button_color_a.png",
	&"B": "res://assets/prompts/xbox_button_color_b.png",
	&"X": "res://assets/prompts/xbox_button_color_x.png",
	&"Y": "res://assets/prompts/xbox_button_color_y.png",
	&"LB": "res://assets/prompts/xbox_lb.png",
	&"RB": "res://assets/prompts/xbox_rb.png",
	&"START": "res://assets/prompts/xbox_button_menu.png",
	&"DPAD": "res://assets/prompts/xbox_dpad.png",
}

const PROMPT_GLYPH_SIZE := Vector2(34, 34)
## Outline thickness (real screen pixels, not texture texels - see
## _get_outline_shader) drawn around every glyph icon's own opaque pixels.
## Kenney's button art alone washes out against light or busy backgrounds
## (several screens' backgrounds are exactly that); a flat backing box behind
## it read as a giant black blob, so this outlines the glyph's actual shape
## instead.
const GLYPH_OUTLINE_WIDTH := 2.0
const PROMPT_FONT_SIZE := 20
const PROMPT_BAR_Y := 508.0
const PROMPT_BAR_X := 20.0  # default: bottom-left, not centered
const PROMPT_ITEM_GAP := 6.0
const PROMPT_ENTRY_GAP := 22.0

var mode := MODE_POINTER

var _layer: CanvasLayer
var _hand: TextureRect
var _hand_tween: Tween
var _bob_tween: Tween
var _hand_target := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # must keep working over a paused battle
	_register_actions()
	_build_hand()

# ------------------------------------------------------------------ actions

## Our own nav_* actions rather than reusing the built-in ui_* ones: native
## widgets that own their input while open (OptionButton's popup, LineEdit)
## rely on ui_*, so keeping them separate means FocusNav can never fight
## them. Keyboard bindings are kept alongside the pad ones so the whole
## system stays testable on a desktop with no controller plugged in.
func _register_actions() -> void:
	_add_action(&"nav_up", [JOY_BUTTON_DPAD_UP], [KEY_UP, KEY_W], JOY_AXIS_LEFT_Y, -1.0)
	_add_action(&"nav_down", [JOY_BUTTON_DPAD_DOWN], [KEY_DOWN, KEY_S], JOY_AXIS_LEFT_Y, 1.0)
	_add_action(&"nav_left", [JOY_BUTTON_DPAD_LEFT], [KEY_LEFT, KEY_A], JOY_AXIS_LEFT_X, -1.0)
	_add_action(&"nav_right", [JOY_BUTTON_DPAD_RIGHT], [KEY_RIGHT, KEY_D], JOY_AXIS_LEFT_X, 1.0)
	_add_action(&"nav_accept", [JOY_BUTTON_A], [KEY_ENTER, KEY_SPACE])
	_add_action(&"nav_cancel", [JOY_BUTTON_B], [KEY_ESCAPE, KEY_BACKSPACE])
	_add_action(&"nav_alt", [JOY_BUTTON_X], [KEY_X])
	_add_action(&"nav_alt2", [JOY_BUTTON_Y], [KEY_Y])
	_add_action(&"nav_page_prev", [JOY_BUTTON_LEFT_SHOULDER], [KEY_Q])
	_add_action(&"nav_page_next", [JOY_BUTTON_RIGHT_SHOULDER], [KEY_E])
	_add_action(&"nav_menu", [JOY_BUTTON_START], [KEY_P])
	# Right stick only, no button/key equivalent - Shop's card wheel (see
	# Shop.gd), which needs its own axis separate from nav_left/right (those
	# already move focus between the wheel/slot/offer items).
	_add_action(&"nav_wheel_left", [], [], JOY_AXIS_RIGHT_X, -1.0)
	_add_action(&"nav_wheel_right", [], [], JOY_AXIS_RIGHT_X, 1.0)

func _add_action(name: StringName, buttons: Array, keys: Array, axis: int = -1, axis_value: float = 0.0) -> void:
	if InputMap.has_action(name):
		InputMap.erase_action(name)
	InputMap.add_action(name, STICK_DEADZONE)
	for b in buttons:
		var ev := InputEventJoypadButton.new()
		ev.button_index = b
		InputMap.action_add_event(name, ev)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(name, ev)
	if axis >= 0:
		var ev := InputEventJoypadMotion.new()
		ev.axis = axis
		ev.axis_value = axis_value
		InputMap.action_add_event(name, ev)

# --------------------------------------------------------------- device mode

## Static + side-effect free so it can be unit-tested headlessly with
## synthetic events. Returns the mode this event implies, or -1 for events
## that shouldn't change the mode at all (a stick resting below the
## deadzone, key repeats, everything non-input-ish).
static func classify_event(event: InputEvent) -> int:
	if event is InputEventJoypadButton:
		return MODE_GAMEPAD
	if event is InputEventJoypadMotion:
		return MODE_GAMEPAD if absf((event as InputEventJoypadMotion).axis_value) >= STICK_DEADZONE else -1
	if event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventScreenTouch or event is InputEventScreenDrag:
		return MODE_POINTER
	return -1

func _input(event: InputEvent) -> void:
	var implied := classify_event(event)
	if implied == -1 or implied == mode:
		return
	_set_mode(implied)

func _set_mode(new_mode: int) -> void:
	mode = new_mode
	# Android has no OS cursor to hide, and touching MOUSE_MODE there can
	# interfere with touch input.
	if OS.get_name() != "Android":
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if mode == MODE_GAMEPAD else Input.MOUSE_MODE_VISIBLE
	if mode == MODE_POINTER:
		hide_hand()
	mode_changed.emit(mode)

func is_gamepad() -> bool:
	return mode == MODE_GAMEPAD

# ---------------------------------------------------------------- hand cursor

func _build_hand() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 128
	add_child(_layer)

	_hand = TextureRect.new()
	_hand.texture = load(HAND_TEXTURE_PATH)
	_hand.stretch_mode = TextureRect.STRETCH_SCALE
	_hand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hand.size = HAND_SIZE
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand.visible = false
	_layer.add_child(_hand)

## Snaps the hand so its fingertip (the texture's bottom-right corner) lands
## exactly on `rect`'s own bottom-right corner, approaching it diagonally
## from up-left. Because the project stretches with canvas_items/keep,
## CanvasLayer coordinates are the same 960x544 design coordinates every
## screen is laid out in - no scaling conversion is needed here. Clamped to
## stay on-canvas for anything sitting right at an edge.
func point_at(rect: Rect2) -> void:
	if mode != MODE_GAMEPAD:
		return
	var anchor := rect.position + rect.size * HAND_ANCHOR_FRACTION
	var target := Vector2(
		clampf(anchor.x - HAND_SIZE.x, 0.0, 960.0 - HAND_SIZE.x),
		clampf(anchor.y - HAND_SIZE.y, 0.0, 544.0 - HAND_SIZE.y))
	var first_show := not _hand.visible
	_hand.visible = true
	if target.is_equal_approx(_hand_target) and not first_show:
		return
	_hand_target = target

	if _hand_tween != null and _hand_tween.is_valid():
		_hand_tween.kill()
	if _bob_tween != null and _bob_tween.is_valid():
		_bob_tween.kill()
	if first_show:
		_hand.position = target
		_start_bob()
	else:
		# Bob only starts once the hand actually arrives - starting it
		# immediately raced position/position:x against this same move tween
		# every time focus changed, each frame fighting over which tween's
		# result won, which is what read as a jarring mechanical stutter.
		_hand_tween = create_tween()
		_hand_tween.tween_property(_hand, "position", target, HAND_TWEEN_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_hand_tween.tween_callback(_start_bob)

## A small looping diagonal nudge back along the up-left approach line -
## without it the hand reads as a static decal once it has settled.
func _start_bob() -> void:
	if _bob_tween != null and _bob_tween.is_valid():
		_bob_tween.kill()
	_bob_tween = create_tween()
	_bob_tween.set_loops()
	_bob_tween.tween_property(_hand, "position", _hand_target + HAND_BOB, HAND_BOB_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob_tween.tween_property(_hand, "position", _hand_target, HAND_BOB_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## For a Control whose whole job is already covered by a fixed prompt-bar
## entry (a Back button always bound to B via FocusNav.cancelled, a save
## slot's small delete X always bound to X via alt_activated): pointless
## clutter once the prompt bar spells the same action out, and a competing
## thing to navigate to that doesn't actually need its own focus stop. Ties
## the control's visibility to the current mode immediately and keeps it
## synced as the mode changes; mouse/touch players still see and click it
## normally.
func hide_in_gamepad(control: Control) -> void:
	control.visible = mode != MODE_GAMEPAD
	mode_changed.connect(func(m: int) -> void:
		if is_instance_valid(control):
			control.visible = m != MODE_GAMEPAD)

## The mirror image: a control that only makes sense with a pad in hand (the
## left/right cycle-hint arrows next to the language OptionButton, which the
## pad drives directly instead of opening its native popup - see Options.gd).
func show_in_gamepad(control: Control) -> void:
	control.visible = mode == MODE_GAMEPAD
	mode_changed.connect(func(m: int) -> void:
		if is_instance_valid(control):
			control.visible = m == MODE_GAMEPAD)

func hide_hand() -> void:
	if _hand == null:
		return
	if _hand_tween != null and _hand_tween.is_valid():
		_hand_tween.kill()
	if _bob_tween != null and _bob_tween.is_valid():
		_bob_tween.kill()
	_hand.visible = false
	# So the next point_at() snaps instead of sliding in from wherever it
	# happened to be left on a previous screen.
	_hand_target = Vector2.ZERO

# -------------------------------------------------------------------- glyphs

## Returns null when the art isn't present, which is what lets the prompt bar
## degrade to a text label instead of erroring - see make_prompt_bar.
static func glyph(name: StringName) -> Texture2D:
	if not GLYPH_PATHS.has(name):
		return null
	var path: String = GLYPH_PATHS[name]
	if not ResourceLoader.exists(path):
		return null
	return load(path)

var _outline_shader: Shader

## A cheap edge-detect outline: for every transparent texel, check its 8
## neighbours (node_size apart, in real rendered pixels rather than texture
## texels - a Kenney source PNG can be a very different resolution from the
## 34x34 box it's stretched into here, so texel-space offsets would draw a
## wildly wrong-looking outline width) and paint it solid if any neighbour
## isn't transparent. Built once and reused via a single ShaderMaterial per
## icon instance (materials aren't shared, the Shader resource is).
func _get_outline_shader() -> Shader:
	if _outline_shader == null:
		_outline_shader = Shader.new()
		_outline_shader.code = """
shader_type canvas_item;

uniform vec2 node_size = vec2(34.0, 34.0);
uniform float outline_width = 2.0;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	if (col.a < 0.5) {
		vec2 texel = outline_width / node_size;
		float hit = 0.0;
		hit += texture(TEXTURE, UV + vec2(-texel.x, 0.0)).a;
		hit += texture(TEXTURE, UV + vec2(texel.x, 0.0)).a;
		hit += texture(TEXTURE, UV + vec2(0.0, -texel.y)).a;
		hit += texture(TEXTURE, UV + vec2(0.0, texel.y)).a;
		hit += texture(TEXTURE, UV + vec2(-texel.x, -texel.y)).a;
		hit += texture(TEXTURE, UV + vec2(texel.x, -texel.y)).a;
		hit += texture(TEXTURE, UV + vec2(-texel.x, texel.y)).a;
		hit += texture(TEXTURE, UV + vec2(texel.x, texel.y)).a;
		if (hit > 0.0) {
			col = outline_color;
		}
	}
	COLOR = col;
}
"""
	return _outline_shader

## One glyph "chip", PROMPT_GLYPH_SIZE regardless of which path it takes: the
## button art with a 2px outline traced around its own shape, or - if the
## art isn't present - the same bracketed text tag make_prompt_bar always
## fell back to. Shared by make_prompt_bar and make_button_hint so both draw
## identically.
func _make_glyph_visual(key: StringName) -> Control:
	var tex := glyph(key)
	if tex == null:
		return _make_prompt_label("[%s]" % key)

	var cell := Control.new()
	cell.size = PROMPT_GLYPH_SIZE
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon := TextureRect.new()
	icon.texture = tex
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.size = PROMPT_GLYPH_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = _get_outline_shader()
	mat.set_shader_parameter("node_size", PROMPT_GLYPH_SIZE)
	mat.set_shader_parameter("outline_width", GLYPH_OUTLINE_WIDTH)
	icon.material = mat
	cell.add_child(icon)
	return cell

## `entries` is an Array of [glyph_name: StringName, label: String] pairs.
## The returned Control positions itself along the bottom-left of the
## 960x544 canvas and shows itself only in gamepad mode; add it as a child of
## the screen and forget about it (Godot drops the mode_changed connection
## automatically when the bar is freed with its screen).
func make_prompt_bar(entries: Array) -> Control:
	var bar := Control.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.position = Vector2(0, PROMPT_BAR_Y)
	bar.size = Vector2(960, 36)
	bar.visible = mode == MODE_GAMEPAD

	var x := PROMPT_BAR_X
	for entry in entries:
		var key: StringName = entry[0]
		var text: String = entry[1]

		var glyph_visual := _make_glyph_visual(key)
		glyph_visual.position = Vector2(x, 0)
		bar.add_child(glyph_visual)
		x += glyph_visual.size.x + PROMPT_ITEM_GAP

		var label := _make_prompt_label(text)
		label.position = Vector2(x, 0)
		bar.add_child(label)
		x += label.size.x + PROMPT_ENTRY_GAP

	mode_changed.connect(func(m: int) -> void:
		if is_instance_valid(bar):
			bar.visible = m == MODE_GAMEPAD)
	return bar

## Physically replaces a real button at its own (pos, size) with a glyph +
## label - for the handful of cases where the pad binding is direct and
## fixed enough that hiding the button and pointing only at the generic
## bottom bar would leave a confusing blank spot where a control used to be.
## Pair with hide_in_gamepad() on the button being stood in for.
func make_button_hint(key: StringName, text: String, pos: Vector2, size: Vector2) -> Control:
	var hint := Control.new()
	hint.position = pos
	hint.size = size
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var glyph_visual := _make_glyph_visual(key)
	var label := _make_prompt_label(text)
	var total_w := glyph_visual.size.x + PROMPT_ITEM_GAP + label.size.x
	var start_x := (size.x - total_w) * 0.5
	var mid_y := (size.y - PROMPT_GLYPH_SIZE.y) * 0.5

	glyph_visual.position = Vector2(start_x, mid_y)
	hint.add_child(glyph_visual)
	label.position = Vector2(start_x + glyph_visual.size.x + PROMPT_ITEM_GAP, mid_y)
	hint.add_child(label)

	show_in_gamepad(hint)
	return hint

## Icon-only variant of make_button_hint, for a spot too small to also fit a
## label (Help's close button is a 42x42 corner box) - the bottom-left prompt
## bar already spells the action out in words, so the glyph alone is enough
## in place of the button it's replacing.
func make_icon_hint(key: StringName, pos: Vector2, size: Vector2) -> Control:
	var hint := Control.new()
	hint.position = pos
	hint.size = size
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var glyph_visual := _make_glyph_visual(key)
	glyph_visual.position = (size - glyph_visual.size) * 0.5
	hint.add_child(glyph_visual)

	show_in_gamepad(hint)
	return hint

func _make_prompt_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	if Game.font_stylish != null:
		label.add_theme_font_override("font", Game.font_stylish)
	label.add_theme_font_size_override("font_size", PROMPT_FONT_SIZE)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size = Vector2(label.get_minimum_size().x, PROMPT_GLYPH_SIZE.y)
	return label
