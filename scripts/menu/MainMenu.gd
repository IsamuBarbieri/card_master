extends Control
## Port of UIMainMenu.cs / UIMainMenu.composer.cs (960x544 design canvas).
## Each button has its own text (Button_Battle.Text etc, set in
## UpdateLanguage()) - the Image_* PNGs are a decorative overlay (two icon
## halves with a transparent gap) that sits on top with TouchResponse=false,
## letting the button's own label show through the middle.
## Cat/Help easter egg not ported (its only target, UIHelp, doesn't exist yet).

const SCREEN_W := 960
const SCREEN_H := 544
const ASSETS := "res://assets/"

var sfx_button: AudioStreamPlayer
var music: AudioStreamPlayer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := TextureRect.new()
	bg.texture = load(ASSETS + "common_bkg_dark_clean.png")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	add_child(bg)

	_make_menu_button("Battle", "button_battle.png", Vector2(343, 26), Vector2(274, 71), _on_battle_pressed)
	_make_menu_button("Shop", "button_shop.png", Vector2(131, 236), Vector2(274, 71), _on_shop_pressed)
	_make_menu_button("Collection", "button_collection.png", Vector2(556, 236), Vector2(274, 71), _on_collection_pressed)
	_make_menu_button("Options", "button_option.png", Vector2(343, 442), Vector2(274, 71), _on_options_pressed)

	sfx_button = AudioStreamPlayer.new()
	sfx_button.stream = load(ASSETS + "sfx/button_sound.wav")
	add_child(sfx_button)

	music = AudioStreamPlayer.new()
	music.stream = load(ASSETS + "music/menu1.mp3")
	add_child(music)
	music.play()

func _make_menu_button(label: String, texture_name: String, pos: Vector2, size: Vector2, on_pressed: Callable) -> void:
	var font_stylish: Font = load(ASSETS + "fonts/font_stylish.ttf")
	var btn := Button.new()
	btn.text = label
	btn.position = pos
	btn.size = size
	btn.add_theme_font_override("font", font_stylish)
	btn.add_theme_font_size_override("font_size", 46)
	btn.add_theme_color_override("font_color", Color.BLACK)
	btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	btn.add_theme_constant_override("shadow_offset_x", 1)
	btn.add_theme_constant_override("shadow_offset_y", 1)
	btn.pressed.connect(on_pressed)
	add_child(btn)

	var icon := TextureRect.new()
	icon.texture = load(ASSETS + texture_name)
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.position = pos
	icon.size = size
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)

func _on_battle_pressed() -> void:
	sfx_button.play()
	get_tree().change_scene_to_file("res://scenes/menu/Opponents.tscn")

func _on_shop_pressed() -> void:
	sfx_button.play()
	print("TODO: Shop screen not ported yet")

func _on_collection_pressed() -> void:
	sfx_button.play()
	print("TODO: Collection screen not ported yet")

func _on_options_pressed() -> void:
	sfx_button.play()
	print("TODO: Options screen not ported yet")
