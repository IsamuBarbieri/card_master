class_name FixedSizeLabel
extends Label
## See FixedSizeButton's docstring for the full story - same fix, same
## reason, Label side: native text stays permanently empty (so this Label's
## own minimum-size computation never sees real content to grow for), an
## internal child Label displays what's actually shown, kept in theme sync
## via NOTIFICATION_THEME_CHANGED. _set/_get intercept "text" so
## `lbl.text = "..."` keeps working exactly as every call site already does.

var _child: Label

const _COLOR_KEYS := ["font_color", "font_shadow_color", "font_outline_color"]
const _CONSTANT_KEYS := ["shadow_offset_x", "shadow_offset_y", "outline_size"]

func _init() -> void:
	clip_contents = true
	_child = Label.new()
	_child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_child)
	resized.connect(_sync_child_rect)

## Belt-and-suspenders for scene-loaded instances (a node baked into a
## .tscn, not built with `FixedSizeLabel.new()` in code): Godot's scene
## deserializer sets Label's native properties (autowrap_mode, alignment,
## the offset_*/size that determine `size`) directly on this object,
## bypassing the _set() interception below entirely - confirmed empirically,
## _child was left at Label's own defaults (size (0,0), autowrap off) for
## every FixedSizeLabel placed in a scene file instead of built in script.
## _ready() is guaranteed to fire only after every property from the scene
## has already been applied, so it's the one point that can safely re-pull
## them from self (whose own native storage still holds the correct
## scene-authored values, even though _get("text") no longer reads it) onto
## _child. A no-op for code-built instances, where _set() already kept
## _child in sync as each property was assigned.
func _ready() -> void:
	_child.horizontal_alignment = horizontal_alignment
	_child.vertical_alignment = vertical_alignment
	_child.autowrap_mode = autowrap_mode
	_sync_child_rect()

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_instance_valid(_child):
		if has_theme_font_override("font"):
			_child.add_theme_font_override("font", get_theme_font("font"))
		if has_theme_font_size_override("font_size"):
			_child.add_theme_font_size_override("font_size", get_theme_font_size("font_size"))
		for key in _COLOR_KEYS:
			if has_theme_color_override(key):
				_child.add_theme_color_override(key, get_theme_color(key))
			else:
				_child.remove_theme_color_override(key)
		for key in _CONSTANT_KEYS:
			if has_theme_constant_override(key):
				_child.add_theme_constant_override(key, get_theme_constant(key))
			else:
				_child.remove_theme_constant_override(key)

func _sync_child_rect() -> void:
	_child.position = Vector2.ZERO
	_child.size = size

func _set(property: StringName, value) -> bool:
	match property:
		"text":
			_child.text = value
			return true
		"horizontal_alignment":
			_child.horizontal_alignment = value
		"vertical_alignment":
			_child.vertical_alignment = value
		"autowrap_mode":
			_child.autowrap_mode = value
		"size":
			# resized alone isn't reliable for the very first size assignment
			# - every construction site sets .size BEFORE add_child(), and
			# resized doesn't fire for a Control not yet in the tree
			# (confirmed: without this, _child silently stayed at its own
			# tiny content-based size instead of filling the label,
			# misaligning every label's text to the top-left instead of
			# wherever horizontal/vertical alignment says it should be).
			_child.position = Vector2.ZERO
			_child.size = value
	return false

func _get(property: StringName):
	if property == "text":
		return _child.text
	return null

## Defensive belt-and-suspenders on top of the child-label fix above - see
## FixedSizeButton's matching comment.
var _locked_size: Vector2 = Vector2.ZERO
var _locked := false

func lock_size(target_size: Vector2) -> void:
	_locked_size = target_size
	_locked = true
	size = target_size

func _process(_delta: float) -> void:
	if _locked and not size.is_equal_approx(_locked_size):
		size = _locked_size
