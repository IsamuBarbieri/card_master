extends Control
## Port of UICredits.cs / UICredits.composer.cs (960x544 design canvas).
## Tap anywhere goes back to Options (Credits_Bkg's TouchEventReceived).

const SCREEN_W := 960
const SCREEN_H := 544
const ASSETS := "res://assets/"
const FONT_SIZE := 36

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var font_stylish: Font = Game.font_stylish

	var bg_black := ColorRect.new()
	bg_black.color = Color.BLACK
	bg_black.size = Vector2(SCREEN_W, SCREEN_H)
	add_child(bg_black)

	var bg := TextureButton.new()
	bg.texture_normal = load(ASSETS + "credits_screen.png")
	bg.stretch_mode = TextureButton.STRETCH_SCALE
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	bg.pressed.connect(_on_back_pressed)
	add_child(bg)

	_make_label(Vector2(320, 36), Vector2(320, 94), font_stylish, "Samuele Barbieri\nGame Design, Graphics")
	_make_label(Vector2(263, 170), Vector2(432, 94), font_stylish, "Viviana Massicut\nCards Graphics")
	_make_label(Vector2(320, 305), Vector2(320, 94), font_stylish, "Marco Castrucci\nSpecial Thanks")

	_make_label(Vector2(0, 448), Vector2(958, 79), font_stylish, "Music: Essa (soundcloud)\nSFX: http://www.freesfx.co.uk")

	# Whole screen is one button, so there's nothing to navigate between and
	# nothing meaningful for the hand to point at - A/B are handled directly
	# in _unhandled_input below rather than through a FocusNav item.
	ControllerUI.hide_hand()
	add_child(ControllerUI.make_prompt_bar([
		[&"B", StringTable.get_string(StringTable.ID_BACK)],
	]))

func _unhandled_input(event: InputEvent) -> void:
	if not ControllerUI.is_gamepad():
		return
	if event.is_action_pressed(&"nav_accept") or event.is_action_pressed(&"nav_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()

func _make_label(pos: Vector2, size: Vector2, font: Font, text: String) -> void:
	var label := Label.new()
	label.position = pos
	label.size = size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.text = text
	add_child(label)

func _on_back_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_back_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/Options.tscn")
