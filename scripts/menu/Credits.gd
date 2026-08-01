extends Control
## Port of UICredits.cs / UICredits.composer.cs (960x544 design canvas).
## Tap anywhere goes back to Options (Credits_Bkg's TouchEventReceived).

const SCREEN_W := 960
const SCREEN_H := 544
const ASSETS := "res://assets/"
const FONT_SIZE := 36

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var font_stylish: Font = load(ASSETS + "fonts/font_stylish.ttf")

	var bg_black := ColorRect.new()
	bg_black.color = Color.BLACK
	bg_black.size = Vector2(SCREEN_W, SCREEN_H)
	add_child(bg_black)

	var bg := TextureButton.new()
	bg.texture_normal = load(ASSETS + "credits_screen.png")
	bg.stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	bg.pressed.connect(_on_back_pressed)
	add_child(bg)

	_make_label(Vector2(320, 36), Vector2(320, 94), font_stylish, "Marco Castrucci\nProgramming")
	_make_label(Vector2(263, 170), Vector2(432, 94), font_stylish, "Samuele Barbieri\nGame Design, Graphics")
	_make_label(Vector2(320, 305), Vector2(320, 94), font_stylish, "Viviana Massicut\nCards Graphics")
	_make_label(Vector2(0, 448), Vector2(958, 79), font_stylish, "Music: Essa (soundcloud)\nSFX: http://www.freesfx.co.uk")

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
