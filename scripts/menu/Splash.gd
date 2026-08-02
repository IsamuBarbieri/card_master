extends Control
## Studio splash screen (NyanSoft logo) - the very first thing shown at
## boot, before the Title Screen. Silent (no music yet - that starts on the
## Title Screen per design), standard fade-in/hold/fade-out timing. Any
## input skips ahead immediately, standard courtesy so it doesn't waste a
## returning player/tester's time.

const SCREEN_W := 960
const SCREEN_H := 544
const ASSETS := "res://assets/"

const FADE_IN_TIME := 0.6
const HOLD_TIME := 1.4
const FADE_OUT_TIME := 0.6

var _advanced := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# expand_mode=IGNORE_SIZE is required, not decorative: without it Godot
	# clamps this Control's size up to the texture's own native 1376x768
	# (Control.size can't go below combined_minimum_size, which defaults to
	# the texture's size), rendering it oversized and cropped by the
	# viewport - same class of bug as the earlier Button auto-expand issue.
	var logo := TextureRect.new()
	logo.texture = load(ASSETS + "logo.jpg")
	logo.stretch_mode = TextureRect.STRETCH_SCALE
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.size = Vector2(SCREEN_W, SCREEN_H)
	logo.modulate.a = 0.0
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)

	var tw := create_tween()
	tw.tween_property(logo, "modulate:a", 1.0, FADE_IN_TIME)
	tw.tween_interval(HOLD_TIME)
	tw.tween_property(logo, "modulate:a", 0.0, FADE_OUT_TIME)
	tw.tween_callback(_advance)

func _input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey) and event.pressed:
		_advance()

func _advance() -> void:
	if _advanced:
		return
	_advanced = true
	get_tree().change_scene_to_file("res://scenes/menu/TitleScreen.tscn")
