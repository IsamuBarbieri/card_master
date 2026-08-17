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

# Measured widest transparent gap between each icon's two halves at the
# vertical midline (source art 428x112, displayed at 274x71, scale 0.6402),
# in on-screen px - narrower than the button's own 274px width, so this is
# the real safe zone for translated text (see UIButtonStyle.fit_menu_button_text).
const MENU_BUTTON_GAP_WIDTHS := {
	"button_battle.png": 163.0,
	"button_shop.png": 177.0,
	"button_collection.png": 158.0,
	"button_option.png": 142.0,
}

var cat_sprite: AnimatedSprite2D
var cat_button: Button
var cat_animating := false
var cat_wait_time := 0.0
var nav: FocusNav

## Survives scene reloads (this file's own class, not an instance field) so
## coming back from Shop/Collection/Options/Help re-focuses whichever button
## sent the player there instead of always resetting to Battle.
static var _last_focus_meta := 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := TextureRect.new()
	bg.texture = load(ASSETS + "common_bkg_dark_clean.png")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	add_child(bg)

	var btn_battle := _make_menu_button(StringTable.get_string(StringTable.ID_BATTLE), "button_battle.png", Vector2(343, 26), Vector2(274, 71), _on_battle_pressed)
	var btn_shop := _make_menu_button(StringTable.get_string(StringTable.ID_SHOP), "button_shop.png", Vector2(131, 236), Vector2(274, 71), _on_shop_pressed)
	var btn_collection := _make_menu_button(StringTable.get_string(StringTable.ID_COLLECTION), "button_collection.png", Vector2(556, 236), Vector2(274, 71), _on_collection_pressed)
	var btn_options := _make_menu_button(StringTable.get_string(StringTable.ID_OPTIONS), "button_option.png", Vector2(343, 442), Vector2(274, 71), _on_options_pressed)
	var btn_online := _make_online_button()

	# No-op if a menu track is already playing (e.g. coming back from
	# Opponents, which never touches the music itself) - keeps whatever's
	# already going instead of restarting/switching it under the player.
	Game.ensure_menu_music()

	_build_cat()
	cat_wait_time = randf() * 3.5

	# Online goes last so the stored focus meta of the four original buttons
	# keeps pointing at the same button it always did.
	_setup_nav([btn_battle, btn_shop, btn_collection, btn_options, btn_online])

## The cat hotspot is registered too so the Help screen is reachable without
## a pointer - it's the only way in.
func _setup_nav(buttons: Array) -> void:
	nav = FocusNav.new()
	add_child(nav)
	for i in buttons.size():
		var btn: Button = buttons[i]
		nav.add_control(btn, i)
		btn.pressed.connect(_remember_focus.bind(i))
	if cat_button != null:
		nav.add_control(cat_button, buttons.size())
		cat_button.pressed.connect(_remember_focus.bind(buttons.size()))
	nav.activated.connect(func(item: FocusNav.NavItem) -> void:
		(item.control as Button).pressed.emit())
	nav.focus_by_meta(_last_focus_meta)
	add_child(ControllerUI.make_prompt_bar([
		[&"A", StringTable.get_string(StringTable.ID_SELECT)],
	]))

func _remember_focus(meta: int) -> void:
	_last_focus_meta = meta

func _build_cat() -> void:
	var sheet: Texture2D = load(ASSETS + "help_cat.png")
	var cols := 6
	var rows := ceili(float(CAT_FRAME_COUNT) / cols)
	var frame_w := sheet.get_width() / cols
	var frame_h := sheet.get_height() / rows

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
	cat_sprite.scale = CAT_FRAME_SIZE / Vector2(frame_w, frame_h)
	cat_sprite.position = CAT_POS
	add_child(cat_sprite)

	cat_button = Button.new()
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

func _make_menu_button(label: String, texture_name: String, pos: Vector2, size: Vector2, on_pressed: Callable) -> Button:
	var font_stylish: Font = Game.font_stylish
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
	UIButtonStyle.fit_menu_button_text(btn, MENU_BUTTON_GAP_WIDTHS[texture_name])

	var icon := TextureRect.new()
	icon.texture = load(ASSETS + texture_name)
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.position = pos
	icon.size = size
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)
	return btn

## The four composer buttons sit around the edges of a diamond (y 26 / 236 /
## 442); Online fills the hole in the middle. It stays round because that is
## the only shape that fits there - the gap between Shop (ends x=405) and
## Collection (starts x=556) is 151px, so a 274-wide button like the other
## four cannot go in the centre at all.
##
## Unlike the other four, the art here is a solid emblem with no transparent
## gap for a label to show through, so the order is reversed: the emblem is
## laid down first and the button (flat, no background of its own) goes on top
## carrying the text.
const ONLINE_BUTTON_SIZE := 146.0
const ONLINE_BUTTON_POS := Vector2(407, 199)
## Black at rest like every other menu label, lighting up to the emblem's own
## gold on hover and focus.
const ONLINE_TEXT_COLOR := Color.BLACK
const ONLINE_TEXT_HOVER := Color(0.93, 0.75, 0.32)
const ONLINE_OUTLINE_SIZE := 2

## outline_size is a single theme constant with no per-state variant, so the
## rim has to be toggled by hand as the pointer or the pad focus arrives.
func _set_online_outline(btn: Button, size: int) -> void:
	btn.add_theme_constant_override("outline_size", size)

func _make_online_button() -> Button:
	var emblem := TextureRect.new()
	emblem.texture = load(ASSETS + "button_online_round.png")
	emblem.stretch_mode = TextureRect.STRETCH_SCALE
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.position = ONLINE_BUTTON_POS
	emblem.size = Vector2(ONLINE_BUTTON_SIZE, ONLINE_BUTTON_SIZE)
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(emblem)

	var btn := Button.new()
	btn.flat = true
	btn.text = StringTable.get_string(StringTable.ID_ONLINE)
	btn.position = ONLINE_BUTTON_POS
	btn.size = Vector2(ONLINE_BUTTON_SIZE, ONLINE_BUTTON_SIZE)
	btn.add_theme_font_override("font", Game.font_stylish)
	btn.add_theme_font_size_override("font_size", 36)
	btn.add_theme_color_override("font_color", ONLINE_TEXT_COLOR)
	# Same touch caveat as every other button - see UIButtonStyle.hover_color.
	btn.add_theme_color_override("font_hover_color", UIButtonStyle.hover_color(ONLINE_TEXT_HOVER))
	btn.add_theme_color_override("font_focus_color", ONLINE_TEXT_HOVER)
	btn.add_theme_color_override("font_pressed_color", ONLINE_TEXT_HOVER)
	# Gold rim rather than the usual black one: black-on-black would vanish
	# against the globe, and this picks up the emblem's own ring. It is dropped
	# while highlighted - the label turns gold there, so keeping a gold rim
	# around gold letters just reads as a heavier, blurrier font.
	btn.add_theme_color_override("font_outline_color", ONLINE_TEXT_HOVER)
	btn.add_theme_constant_override("outline_size", ONLINE_OUTLINE_SIZE)
	btn.mouse_entered.connect(_set_online_outline.bind(btn, 0))
	btn.mouse_exited.connect(_set_online_outline.bind(btn, ONLINE_OUTLINE_SIZE))
	btn.focus_entered.connect(_set_online_outline.bind(btn, 0))
	btn.focus_exited.connect(_set_online_outline.bind(btn, ONLINE_OUTLINE_SIZE))
	btn.pressed.connect(_on_online_pressed)
	add_child(btn)
	# Fitted by hand rather than through fit_menu_button_text: that one is
	# built for the four two-halves icons and CLEARS the outline overrides
	# whenever the label fits between them (see UIButtonStyle), which quietly
	# removed the gold rim set just above. The safe width here is the square
	# inscribed in the circle, not the button's full 146.
	btn.add_theme_font_size_override("font_size", UIButtonStyle.fit_text_to_width(
		btn.text, Game.font_stylish, ONLINE_BUTTON_SIZE * 0.70, 36, UIButtonStyle.MIN_FONT_SIZE))
	return btn

func _on_online_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/Online.tscn")

func _on_battle_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/Opponents.tscn")

func _on_shop_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/Shop.tscn")

func _on_collection_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/Collection.tscn")

func _on_options_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/Options.tscn")

func _on_cat_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/help_cat.wav")
	get_tree().change_scene_to_file("res://scenes/menu/Help.tscn")
