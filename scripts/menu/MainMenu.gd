extends Control
## Port of UIMainMenu.cs / UIMainMenu.composer.cs (960x544 design canvas).
## Each button has its own text (Button_Battle.Text etc, set in
## UpdateLanguage()) - the Image_* PNGs are a decorative overlay (two icon
## halves with a transparent gap in the middle) that sits on top with
## TouchResponse=false, letting the button's own label show through the
## middle. Buttons use PSM's default 9-patch background (see
## UIButtonStyle.gd) - no CustomImage in the composer doesn't mean no
## background, the engine's own default skin is button_9patch_*.png.
## Cat easter egg (InitCat/OnUpdate in UIMainMenu.cs): idle-loops its 28
## frame animation then pauses for a random 2-6s before looping again; tap
## goes to Help.

const SCREEN_W := 960
const SCREEN_H := 544
const ASSETS := "res://assets/"

const CAT_POS := Vector2(850, 416)
const CAT_FRAME_SIZE := Vector2(160, 138)
const CAT_FRAME_COUNT := 28
const CAT_FPS := 10.0

var cat_sprite: AnimatedSprite2D
var cat_animating := false
var cat_wait_time := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := TextureRect.new()
	bg.texture = load(ASSETS + "common_bkg_dark_clean.png")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	add_child(bg)

	_make_menu_button(StringTable.get_string(StringTable.ID_BATTLE), "button_battle.png", Vector2(343, 26), Vector2(274, 71), _on_battle_pressed)
	_make_menu_button(StringTable.get_string(StringTable.ID_SHOP), "button_shop.png", Vector2(131, 236), Vector2(274, 71), _on_shop_pressed)
	_make_menu_button(StringTable.get_string(StringTable.ID_COLLECTION), "button_collection.png", Vector2(556, 236), Vector2(274, 71), _on_collection_pressed)
	_make_menu_button(StringTable.get_string(StringTable.ID_OPTIONS), "button_option.png", Vector2(343, 442), Vector2(274, 71), _on_options_pressed)

	Game.play_music(ASSETS + "music/menu1.mp3")

	_build_cat()
	cat_wait_time = randf() * 3.5

func _build_cat() -> void:
	var sheet: Texture2D = load(ASSETS + "help_cat.png")
	var cols := 6
	var frame_w := int(CAT_FRAME_SIZE.x)
	var frame_h := int(CAT_FRAME_SIZE.y)

	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("idle")
	frames.set_animation_speed("idle", CAT_FPS)
	frames.set_animation_loop("idle", false)
	for i in CAT_FRAME_COUNT:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2((i % cols) * frame_w, (i / cols) * frame_h, frame_w, frame_h)
		frames.add_frame("idle", atlas)

	cat_sprite = AnimatedSprite2D.new()
	cat_sprite.sprite_frames = frames
	cat_sprite.animation = "idle"
	cat_sprite.centered = false
	cat_sprite.position = CAT_POS
	add_child(cat_sprite)

	var cat_button := Button.new()
	cat_button.flat = true
	cat_button.position = CAT_POS
	cat_button.size = CAT_FRAME_SIZE
	cat_button.pressed.connect(_on_cat_pressed)
	add_child(cat_button)

func _process(delta: float) -> void:
	if cat_animating:
		if cat_sprite.frame >= CAT_FRAME_COUNT - 1 and not cat_sprite.is_playing():
			cat_animating = false
			cat_wait_time = 2.0 + randf() * 4.0
	else:
		cat_wait_time -= delta
		if cat_wait_time < 0.0:
			cat_animating = true
			cat_sprite.frame = 0
			cat_sprite.play("idle")

func _make_menu_button(label: String, texture_name: String, pos: Vector2, size: Vector2, on_pressed: Callable) -> void:
	var font_stylish: Font = load(ASSETS + "fonts/font_stylish.ttf")
	var btn := Button.new()
	UIButtonStyle.apply(btn)
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
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/Opponents.tscn")

func _on_shop_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	print("TODO: Shop screen not ported yet")

func _on_collection_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	print("TODO: Collection screen not ported yet")

func _on_options_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/Options.tscn")

func _on_cat_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/help_cat.wav")
	get_tree().change_scene_to_file("res://scenes/menu/Help.tscn")
