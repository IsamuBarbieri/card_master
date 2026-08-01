extends Control
## Port of UIOptions.cs / UIOptions.composer.cs (960x544 design canvas).
## Sliders drive Game.music_volume/sfx_volume, which live-adjust the
## "Music"/"SFX" audio buses (see Game.gd) - affects the persistent music
## track and every sfx immediately, matching Music.curPlayer.Volume /
## Globals.UpdateSoundVolumes in the original.

const SCREEN_W := 960
const SCREEN_H := 544
const ASSETS := "res://assets/"
const LABEL_FONT_SIZE := 36

var sfx_cat: AudioStreamPlayer
var _sfx_dragging := false

var title: Label
var label_music: Label
var label_sfx: Label
var label_lang: Label
var back_button: Button
var credits_button: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var font_stylish: Font = load(ASSETS + "fonts/font_stylish.ttf")

	var bg := TextureRect.new()
	bg.texture = load(ASSETS + "common_bkg_dark_clean.png")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	add_child(bg)

	var icon := TextureRect.new()
	icon.texture = load(ASSETS + "button_option.png")
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.position = Vector2(347, 9)
	icon.size = Vector2(265, 68)
	add_child(icon)

	title = _make_label(Vector2(348, 20), Vector2(264, 47), font_stylish, 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	label_music = _make_label(Vector2(64, 170), Vector2(205, 58), font_stylish, LABEL_FONT_SIZE)
	label_music.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_music.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label_music)

	label_sfx = _make_label(Vector2(64, 243), Vector2(205, 58), font_stylish, LABEL_FONT_SIZE)
	label_sfx.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_sfx.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label_sfx)

	label_lang = _make_label(Vector2(64, 326), Vector2(205, 58), font_stylish, LABEL_FONT_SIZE)
	label_lang.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_lang.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label_lang)

	var slider_music := _make_slider(Vector2(298, 170), Vector2(362, 58), Game.music_volume * 100.0)
	slider_music.value_changed.connect(_on_music_value_changed)
	add_child(slider_music)

	var slider_sfx := _make_slider(Vector2(298, 243), Vector2(362, 58), Game.sfx_volume * 100.0)
	slider_sfx.value_changed.connect(_on_sfx_value_changed)
	slider_sfx.drag_started.connect(_on_sfx_drag_started)
	slider_sfx.drag_ended.connect(_on_sfx_drag_ended)
	add_child(slider_sfx)

	var lang_popup := OptionButton.new()
	lang_popup.position = Vector2(300, 328)
	lang_popup.size = Vector2(360, 56)
	lang_popup.add_item("English")
	lang_popup.add_item("Italiano")
	lang_popup.add_item("日本語")
	lang_popup.selected = Game.language
	lang_popup.item_selected.connect(_on_language_selected)
	add_child(lang_popup)

	back_button = _make_text_button("", Vector2(42, 463), Vector2(115, 56), font_stylish)
	back_button.pressed.connect(_on_back_pressed)

	credits_button = _make_text_button("", Vector2(412, 463), Vector2(136, 56), font_stylish)
	credits_button.pressed.connect(_on_credits_pressed)

	sfx_cat = AudioStreamPlayer.new()
	sfx_cat.stream = load(ASSETS + "sfx/help_cat.wav")
	sfx_cat.bus = "SFX"
	sfx_cat.finished.connect(func():
		if _sfx_dragging:
			sfx_cat.play())
	add_child(sfx_cat)

	_update_language_texts()

func _make_label(pos: Vector2, size: Vector2, font: Font, font_size: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = size
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.BLACK)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

func _make_text_button(label: String, pos: Vector2, size: Vector2, font: Font) -> Button:
	var btn := Button.new()
	UIButtonStyle.apply(btn)
	btn.text = label
	btn.position = pos
	btn.size = size
	btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	btn.add_theme_color_override("font_color", Color.BLACK)
	btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	btn.add_theme_constant_override("shadow_offset_x", 1)
	btn.add_theme_constant_override("shadow_offset_y", 1)
	add_child(btn)
	return btn

func _make_slider(pos: Vector2, size: Vector2, value: float) -> HSlider:
	var slider := HSlider.new()
	slider.position = pos
	slider.size = size
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = value
	return slider

func _on_music_value_changed(value: float) -> void:
	Game.music_volume = value / 100.0

func _on_sfx_drag_started() -> void:
	_sfx_dragging = true
	sfx_cat.play()

func _on_sfx_value_changed(value: float) -> void:
	Game.sfx_volume = value / 100.0

func _on_sfx_drag_ended(_value_changed: bool) -> void:
	_sfx_dragging = false
	sfx_cat.stop()

func _on_language_selected(index: int) -> void:
	Game.language = index
	_update_language_texts()

func _update_language_texts() -> void:
	title.text = StringTable.get_string(StringTable.ID_OPTIONS)
	label_music.text = StringTable.get_string(StringTable.ID_MUSIC)
	label_sfx.text = StringTable.get_string(StringTable.ID_SFX)
	label_lang.text = StringTable.get_string(StringTable.ID_LANGUAGE)
	back_button.text = StringTable.get_string(StringTable.ID_BACK)
	credits_button.text = StringTable.get_string(StringTable.ID_CREDITS)

func _on_back_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_back_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")

func _on_credits_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/Credits.tscn")
