class_name FixedSizeButton
extends Button
## Godot's Control.size setter unconditionally clamps to at least
## get_combined_minimum_size() - confirmed via direct experimentation this
## can't be bypassed from script: overriding _get_minimum_size() isn't
## consulted by Button's own C++ minimum-size calculation at all, and even
## re-asserting .size every frame just gets synchronously re-clamped back up
## by that same setter. For CJK text (font_stylish.ttf/font_info.ttf have no
## CJK glyphs, so it renders through Godot's system-fallback font) that
## content-driven minimum can be taller than the button's authored size, no
## matter how far UIButtonStyle shrinks the font trying to compensate.
##
## The only thing that actually works: never let the native Button.text
## carry real content, since that's the only thing feeding Button's own
## minimum-size calculation. The visible text renders in an internal child
## Label instead, sized to fill the button and clipped to it - a child's
## size has zero effect on its parent's own minimum size (Button isn't a
## layout Container), so this sidesteps the problem instead of fighting it.
##
## Callers don't need to know any of this:
## - _set/_get intercept the native "text" property (confirmed: GDScript's
##   property override hooks fire even for engine-native properties, not
##   just custom ones) and redirect it to the internal label, so plain
##   `btn.text = "..."` keeps working exactly as every call site already does.
## - Theme overrides (add_theme_font_override etc.) can't be intercepted the
##   same way - Godot rejects overriding those method names outright, they
##   aren't script-virtual. And a plain child Control does NOT inherit a
##   parent's per-node theme overrides (only a real Theme resource cascades
##   that way) - confirmed empirically. Instead, NOTIFICATION_THEME_CHANGED
##   (which DOES fire for every add_theme_*_override call) is used to copy
##   whatever's currently set on self onto the child every time it changes.

var _label: Label

const _COLOR_KEYS := ["font_color", "font_shadow_color", "font_outline_color"]
const _CONSTANT_KEYS := ["shadow_offset_x", "shadow_offset_y", "outline_size"]

func _init() -> void:
	clip_contents = true
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	resized.connect(_sync_label_rect)

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_instance_valid(_label):
		if has_theme_font_override("font"):
			_label.add_theme_font_override("font", get_theme_font("font"))
		if has_theme_font_size_override("font_size"):
			_label.add_theme_font_size_override("font_size", get_theme_font_size("font_size"))
		for key in _COLOR_KEYS:
			if has_theme_color_override(key):
				_label.add_theme_color_override(key, get_theme_color(key))
			else:
				_label.remove_theme_color_override(key)
		for key in _CONSTANT_KEYS:
			if has_theme_constant_override(key):
				_label.add_theme_constant_override(key, get_theme_constant(key))
			else:
				_label.remove_theme_constant_override(key)

func _sync_label_rect() -> void:
	_label.position = Vector2.ZERO
	_label.size = size

func _set(property: StringName, value) -> bool:
	if property == "text":
		_label.text = value
		return true
	if property == "size":
		# resized alone isn't reliable for the very first size assignment -
		# every construction site sets .size BEFORE add_child(), and resized
		# doesn't fire for a Control that isn't in the tree yet (confirmed:
		# without this, _label silently stayed at its own tiny content-based
		# size instead of filling the button, misaligning every button's
		# text to the top-left instead of wherever horizontal/vertical
		# alignment says it should be). Sync immediately here too; return
		# false so the real .size assignment still goes through normally.
		_label.position = Vector2.ZERO
		_label.size = value
	return false

func _get(property: StringName):
	if property == "text":
		return _label.text
	return null

## Defensive belt-and-suspenders on top of the child-label fix above: with
## native text always empty, size shouldn't need to grow at all anymore, but
## keep a hard per-frame clamp anyway in case something else (icon, unusual
## theme metrics) ever drives it up again.
var _locked_size: Vector2 = Vector2.ZERO
var _locked := false

func lock_size(target_size: Vector2) -> void:
	_locked_size = target_size
	_locked = true
	size = target_size

func _process(_delta: float) -> void:
	if _locked and not size.is_equal_approx(_locked_size):
		size = _locked_size
