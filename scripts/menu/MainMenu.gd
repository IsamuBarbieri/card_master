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
##
## Static layout (background, the four button/icon pairs' shared rects, the
## online emblem+button rect) lives in MainMenu.tscn now. Each button's icon
## is a separate sibling node at the SAME rect (the transparent-gap overlay
## trick) - move them together if you ever reposition one in the editor.
## Everything else stays script: font_title swaps per language, button skin
## comes from UIButtonStyle.apply(), and menu button font_size is refit
## live per translation (fit_menu_button_text) so it can't be a fixed value.
## The cat button/sprite pair also stays fully script-built and NOT in the
## scene - its position must track UIConstants.MAIN_MENU_CAT_POS exactly
## (the sprite's frames are themselves generated at runtime and can't be
## baked), so keeping both script-driven is what keeps them from drifting
## apart.

const ASSETS := "res://assets/"

const CAT_FRAME_SIZE := Vector2(160, 138)
const CAT_FRAME_COUNT := 28
const CAT_FPS := 10.0

# Measured widest transparent gap between each icon's two halves at the
# vertical midline (source art 428x112, displayed at 274x71, scale 0.6402),
# in on-screen px - narrower than the button's own 274px width, so this is
# the real safe zone for translated text (see UIButtonStyle.fit_menu_button_text).
const MENU_BUTTON_GAP_WIDTHS := {
	"BattleButton": 163.0,
	"ShopButton": 177.0,
	"CollectionButton": 158.0,
	"OptionsButton": 142.0,
}

@onready var battle_button: Button = $BattleButton
@onready var shop_button: Button = $ShopButton
@onready var collection_button: Button = $CollectionButton
@onready var options_button: Button = $OptionsButton
@onready var online_button: Button = $OnlineButton

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
	_setup_menu_button(battle_button, StringTable.get_string(StringTable.ID_BATTLE), _on_battle_pressed)
	_setup_menu_button(shop_button, StringTable.get_string(StringTable.ID_SHOP), _on_shop_pressed)
	_setup_menu_button(collection_button, StringTable.get_string(StringTable.ID_COLLECTION), _on_collection_pressed)
	_setup_menu_button(options_button, StringTable.get_string(StringTable.ID_OPTIONS), _on_options_pressed)
	_setup_online_button()

	# No-op if a menu track is already playing (e.g. coming back from
	# Opponents, which never touches the music itself) - keeps whatever's
	# already going instead of restarting/switching it under the player.
	Game.ensure_menu_music()

	_build_cat()
	cat_wait_time = randf() * 3.5

	# Online goes last so the stored focus meta of the four original buttons
	# keeps pointing at the same button it always did.
	_setup_nav([battle_button, shop_button, collection_button, options_button, online_button])

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
	cat_sprite.position = UIConstants.MAIN_MENU_CAT_POS
	add_child(cat_sprite)

	cat_button = Button.new()
	cat_button.name = "CatButton"
	cat_button.flat = true
	cat_button.position = UIConstants.MAIN_MENU_CAT_POS
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

func _setup_menu_button(btn: Button, label: String, on_pressed: Callable) -> void:
	UIButtonStyle.apply(btn)
	btn.text = label
	btn.add_theme_font_override("font", Game.font_title)
	btn.pressed.connect(on_pressed)
	UIButtonStyle.fit_menu_button_text(btn, MENU_BUTTON_GAP_WIDTHS[btn.name])

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
## Black at rest like every other menu label, lighting up to the emblem's own
## gold on hover and focus.
const ONLINE_TEXT_HOVER := Color(0.93, 0.75, 0.32)
const ONLINE_OUTLINE_SIZE := 2

## outline_size is a single theme constant with no per-state variant, so the
## rim has to be toggled by hand as the pointer or the pad focus arrives.
func _set_online_outline(btn: Button, size: int) -> void:
	btn.add_theme_constant_override("outline_size", size)

func _setup_online_button() -> void:
	var btn := online_button
	btn.flat = true
	btn.text = StringTable.get_string(StringTable.ID_ONLINE)
	btn.add_theme_font_override("font", Game.font_title)
	# Same touch caveat as every other button - see UIButtonStyle.hover_color.
	# The only one of this button's colours that can't be baked into the
	# scene: it depends on OS.has_feature("mobile") at runtime.
	btn.add_theme_color_override("font_hover_color", UIButtonStyle.hover_color(ONLINE_TEXT_HOVER))
	btn.mouse_entered.connect(_set_online_outline.bind(btn, 0))
	btn.mouse_exited.connect(_set_online_outline.bind(btn, ONLINE_OUTLINE_SIZE))
	btn.focus_entered.connect(_set_online_outline.bind(btn, 0))
	btn.focus_exited.connect(_set_online_outline.bind(btn, ONLINE_OUTLINE_SIZE))
	btn.pressed.connect(_on_online_pressed)
	# Fitted by hand rather than through fit_menu_button_text: that one is
	# built for the four two-halves icons and CLEARS the outline overrides
	# whenever the label fits between them (see UIButtonStyle), which quietly
	# removed the gold rim set just above. The safe width here is the square
	# inscribed in the circle, not the button's full 146.
	btn.add_theme_font_size_override("font_size", UIButtonStyle.fit_text_to_width(
		btn.text, Game.font_stylish, ONLINE_BUTTON_SIZE * 0.70, 36, UIButtonStyle.MIN_FONT_SIZE))

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
