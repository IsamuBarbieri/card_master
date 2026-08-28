extends Control
## Port of UIOptions.cs / UIOptions.composer.cs (960x544 design canvas).
## Sliders drive Game.music_volume/sfx_volume, which live-adjust the
## "Music"/"SFX" audio buses (see Game.gd) - affects the persistent music
## track and every sfx immediately, matching Music.curPlayer.Volume /
## Globals.UpdateSoundVolumes in the original.

const ASSETS := "res://assets/"
# Title reuses button_option.png the same "two icon halves + transparent
# gap" trick as MainMenu's own Options button (see UIButtonStyle.gd), just
# at this screen's own icon size (265x68 vs MainMenu's 274x71): native gap
# 222px * (265/428) scale = ~137.5px on-screen.
const TITLE_ICON_GAP_WIDTH := 137.5

const SLIDER_NUDGE := 5.0

var sfx_cat: AudioStreamPlayer
var _sfx_dragging := false

@onready var title: Label = $Title
@onready var label_music: Label = $LabelMusic
@onready var label_sfx: Label = $LabelSfx
@onready var label_lang: Label = $LabelLang
@onready var back_button: Button = $BackButton
@onready var credits_button: Button = $CreditsButton
@onready var title_screen_button: Button = $TitleScreenButton

@onready var slider_music: HSlider = $SliderMusic
@onready var slider_sfx: HSlider = $SliderSfx
@onready var lang_popup: OptionButton = $LangPopup
var lang_arrow_left: Control
var lang_arrow_right: Control
var nav: FocusNav

func _ready() -> void:
	for btn in [back_button, credits_button, title_screen_button]:
		UIButtonStyle.apply(btn)

	_style_slider(slider_music)
	_style_slider(slider_sfx)
	_style_lang_popup(lang_popup)

	slider_music.value = Game.music_volume * 100.0
	slider_music.value_changed.connect(_on_music_value_changed)

	slider_sfx.value = Game.sfx_volume * 100.0
	slider_sfx.value_changed.connect(_on_sfx_value_changed)
	slider_sfx.drag_started.connect(_on_sfx_drag_started)
	slider_sfx.drag_ended.connect(_on_sfx_drag_ended)

	# Order must match StringTable.TABLE (sorted alphabetically by each
	# language's own native name).
	lang_popup.add_item("Deutsch")
	lang_popup.add_item("English")
	lang_popup.add_item("Español")
	lang_popup.add_item("Français")
	lang_popup.add_item("Italiano")
	lang_popup.add_item("Português (Brasil)")
	lang_popup.add_item("Русский")
	lang_popup.add_item("日本語")
	lang_popup.add_item("简体中文")
	lang_popup.selected = Game.language
	lang_popup.item_selected.connect(_on_language_selected)

	# Pad left/right cycles the language directly (see _setup_nav's axis_fn)
	# instead of opening lang_popup's own native dropdown arrow - that arrow
	# means nothing to a pad, so these two only show up in gamepad mode to
	# spell out what the d-pad actually does here.
	var arrow_left_tex := _load_texture(ASSETS + "icons/arrow_left.png")
	var arrow_right_tex := _load_texture(ASSETS + "icons/arrow_right.png")
	lang_arrow_left = _make_lang_arrow(arrow_left_tex, "<", Vector2(lang_popup.position.x - 30, lang_popup.position.y + 16))
	lang_arrow_right = _make_lang_arrow(arrow_right_tex, ">", Vector2(lang_popup.position.x + lang_popup.size.x + 6, lang_popup.position.y + 16))
	ControllerUI.show_in_gamepad(lang_arrow_left)
	ControllerUI.show_in_gamepad(lang_arrow_right)

	back_button.pressed.connect(_on_back_pressed)
	credits_button.pressed.connect(_on_credits_pressed)
	# Returns to the Title Screen instead of MainMenu.
	title_screen_button.pressed.connect(_on_title_screen_pressed)

	sfx_cat = AudioStreamPlayer.new()
	sfx_cat.stream = load(ASSETS + "sfx/help_cat.wav")
	sfx_cat.bus = "SFX"
	sfx_cat.finished.connect(func():
		if _sfx_dragging:
			sfx_cat.play())
	add_child(sfx_cat)

	_update_language_texts()
	_setup_nav()

class ScaledTexture extends Texture2D:
	var base_texture: Texture2D
	var display_size: Vector2

	func _init(p_tex: Texture2D = null, p_size: Vector2 = Vector2(36, 36)) -> void:
		base_texture = p_tex
		display_size = p_size

	func _get_width() -> int:
		return int(display_size.x)

	func _get_height() -> int:
		return int(display_size.y)

	func _has_alpha() -> bool:
		return true

	func _draw(to_canvas_item: RID, pos: Vector2, modulate: Color, transpose: bool) -> void:
		if base_texture == null:
			return
		RenderingServer.canvas_item_add_texture_rect(
			to_canvas_item,
			Rect2(pos, display_size),
			base_texture.get_rid(),
			false,
			modulate,
			transpose
		)

	func _draw_rect(to_canvas_item: RID, rect: Rect2, tile: bool, modulate: Color, transpose: bool) -> void:
		if base_texture == null:
			return
		RenderingServer.canvas_item_add_texture_rect(
			to_canvas_item,
			rect,
			base_texture.get_rid(),
			tile,
			modulate,
			transpose
		)

	func _draw_rect_region(to_canvas_item: RID, rect: Rect2, src_rect: Rect2, modulate: Color, transpose: bool, clip_uv: bool) -> void:
		if base_texture == null:
			return
		RenderingServer.canvas_item_add_texture_rect_region(
			to_canvas_item,
			rect,
			base_texture.get_rid(),
			src_rect,
			modulate,
			transpose,
			clip_uv
		)

	func _is_pixel_opaque(_x: int, _y: int) -> bool:
		return true

func _load_texture(path: String) -> Texture2D:
	var global_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(global_path):
		var img := Image.new()
		if img.load(global_path) == OK:
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res
	return null

func _style_slider(slider: HSlider) -> void:
	# Slim carved dark groove track (4px tall)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.18, 0.12, 0.06, 0.95)
	track.border_width_left = 1
	track.border_width_right = 1
	track.border_width_top = 1
	track.border_width_bottom = 1
	track.border_color = Color(0.40, 0.28, 0.12, 0.9)
	track.corner_radius_top_left = 2
	track.corner_radius_top_right = 2
	track.corner_radius_bottom_left = 2
	track.corner_radius_bottom_right = 2
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	track.anti_aliasing = true

	# Filled golden progress bar (4px tall)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.65, 0.20, 1.0)
	fill.border_width_left = 1
	fill.border_width_right = 1
	fill.border_width_top = 1
	fill.border_width_bottom = 1
	fill.border_color = Color(0.98, 0.82, 0.35, 1.0)
	fill.corner_radius_top_left = 2
	fill.corner_radius_top_right = 2
	fill.corner_radius_bottom_left = 2
	fill.corner_radius_bottom_right = 2
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	fill.anti_aliasing = true

	var fill_hl := StyleBoxFlat.new()
	fill_hl.bg_color = Color(1.0, 0.80, 0.28, 1.0)
	fill_hl.border_width_left = 1
	fill_hl.border_width_right = 1
	fill_hl.border_width_top = 1
	fill_hl.border_width_bottom = 1
	fill_hl.border_color = Color(1.0, 0.92, 0.50, 1.0)
	fill_hl.corner_radius_top_left = 2
	fill_hl.corner_radius_top_right = 2
	fill_hl.corner_radius_bottom_left = 2
	fill_hl.corner_radius_bottom_right = 2
	fill_hl.content_margin_top = 2
	fill_hl.content_margin_bottom = 2
	fill_hl.anti_aliasing = true

	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_hl)

	var grabber_tex: Texture2D = _load_texture(ASSETS + "icons/slider_grabber.png")
	var grabber_hl_tex: Texture2D = _load_texture(ASSETS + "icons/slider_grabber_highlight.png")
	if grabber_tex != null:
		var scaled_grabber := ScaledTexture.new(grabber_tex, Vector2(36, 36))
		slider.add_theme_icon_override("grabber", scaled_grabber)
		slider.add_theme_icon_override("grabber_disabled", scaled_grabber)
	if grabber_hl_tex != null:
		var scaled_hl := ScaledTexture.new(grabber_hl_tex, Vector2(36, 36))
		slider.add_theme_icon_override("grabber_highlight", scaled_hl)

func _style_lang_popup(lang_btn: OptionButton) -> void:
	const RADIUS := 8
	const BORDER_W := 2

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.95, 0.91, 0.82, 0.98)
	normal.border_width_left = BORDER_W
	normal.border_width_right = BORDER_W
	normal.border_width_top = BORDER_W
	normal.border_width_bottom = BORDER_W
	normal.border_color = Color(0.45, 0.32, 0.15, 1.0)
	normal.corner_radius_top_left = RADIUS
	normal.corner_radius_top_right = RADIUS
	normal.corner_radius_bottom_left = RADIUS
	normal.corner_radius_bottom_right = RADIUS
	normal.shadow_color = Color(0, 0, 0, 0.25)
	normal.shadow_size = 4
	normal.shadow_offset = Vector2(0, 2)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.anti_aliasing = true

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.99, 0.97, 0.91, 0.98)
	hover.border_width_left = BORDER_W
	hover.border_width_right = BORDER_W
	hover.border_width_top = BORDER_W
	hover.border_width_bottom = BORDER_W
	hover.border_color = Color(0.85, 0.65, 0.20, 1.0)
	hover.corner_radius_top_left = RADIUS
	hover.corner_radius_top_right = RADIUS
	hover.corner_radius_bottom_left = RADIUS
	hover.corner_radius_bottom_right = RADIUS
	hover.shadow_color = Color(0.85, 0.65, 0.20, 0.35)
	hover.shadow_size = 6
	hover.shadow_offset = Vector2(0, 2)
	hover.content_margin_left = 14
	hover.content_margin_right = 14
	hover.anti_aliasing = true

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.90, 0.86, 0.76, 0.98)
	pressed.border_width_left = BORDER_W
	pressed.border_width_right = BORDER_W
	pressed.border_width_top = BORDER_W
	pressed.border_width_bottom = BORDER_W
	pressed.border_color = Color(0.35, 0.24, 0.10, 1.0)
	pressed.corner_radius_top_left = RADIUS
	pressed.corner_radius_top_right = RADIUS
	pressed.corner_radius_bottom_left = RADIUS
	pressed.corner_radius_bottom_right = RADIUS
	pressed.content_margin_left = 14
	pressed.content_margin_right = 14
	pressed.anti_aliasing = true

	lang_btn.add_theme_stylebox_override("normal", normal)
	lang_btn.add_theme_stylebox_override("hover", hover)
	lang_btn.add_theme_stylebox_override("pressed", pressed)
	lang_btn.add_theme_stylebox_override("focus", hover)

	var text_color := Color(0.12, 0.08, 0.02)
	lang_btn.add_theme_font_override("font", Game.font_stylish)
	lang_btn.add_theme_font_size_override("font_size", 28)
	lang_btn.add_theme_color_override("font_color", text_color)
	lang_btn.add_theme_color_override("font_hover_color", text_color)
	lang_btn.add_theme_color_override("font_pressed_color", text_color)
	lang_btn.add_theme_color_override("font_focus_color", text_color)

	# Style the PopupMenu
	var popup: PopupMenu = lang_btn.get_popup()
	var menu_panel := StyleBoxFlat.new()
	menu_panel.bg_color = Color(0.96, 0.93, 0.85, 0.98)
	menu_panel.border_width_left = 2
	menu_panel.border_width_right = 2
	menu_panel.border_width_top = 2
	menu_panel.border_width_bottom = 2
	menu_panel.border_color = Color(0.45, 0.32, 0.15, 1.0)
	menu_panel.corner_radius_top_left = 8
	menu_panel.corner_radius_top_right = 8
	menu_panel.corner_radius_bottom_left = 8
	menu_panel.corner_radius_bottom_right = 8
	menu_panel.shadow_color = Color(0, 0, 0, 0.35)
	menu_panel.shadow_size = 6
	menu_panel.shadow_offset = Vector2(0, 3)
	menu_panel.content_margin_left = 10
	menu_panel.content_margin_right = 10
	menu_panel.content_margin_top = 8
	menu_panel.content_margin_bottom = 8
	menu_panel.anti_aliasing = true

	var menu_hover := StyleBoxFlat.new()
	menu_hover.bg_color = Color(0.88, 0.70, 0.25, 0.35)
	menu_hover.border_width_left = 1
	menu_hover.border_width_right = 1
	menu_hover.border_width_top = 1
	menu_hover.border_width_bottom = 1
	menu_hover.border_color = Color(0.85, 0.65, 0.20, 0.8)
	menu_hover.corner_radius_top_left = 4
	menu_hover.corner_radius_top_right = 4
	menu_hover.corner_radius_bottom_left = 4
	menu_hover.corner_radius_bottom_right = 4
	menu_hover.anti_aliasing = true

	popup.add_theme_stylebox_override("panel", menu_panel)
	popup.add_theme_stylebox_override("hover", menu_hover)
	popup.add_theme_font_override("font", Game.font_stylish)
	popup.add_theme_font_size_override("font_size", 22)
	popup.add_theme_color_override("font_color", Color(0.12, 0.08, 0.02))
	popup.add_theme_color_override("font_hover_color", Color.BLACK)

func _setup_nav() -> void:
	nav = FocusNav.new()
	add_child(nav)

	var music_item := nav.add_control(slider_music)
	music_item.axis_fn = func(d: int) -> void:
		slider_music.value = clampf(slider_music.value + d * SLIDER_NUDGE, slider_music.min_value, slider_music.max_value)

	var sfx_item := nav.add_control(slider_sfx)
	sfx_item.axis_fn = func(d: int) -> void:
		slider_sfx.value = clampf(slider_sfx.value + d * SLIDER_NUDGE, slider_sfx.min_value, slider_sfx.max_value)
		sfx_cat.play()  # drag_started/ended never fire for a value set from code

	# Left/right nudges the selection directly instead of opening the native
	# popup, same as the sliders above - the popup is a real Window that's
	# supposed to handle ui_accept/ui_cancel itself once opened, but in
	# practice that left the player stuck inside it with no working A or B on
	# a pad. Cycling in place sidesteps that whole native-widget input path
	# rather than debugging it further; mouse/touch still gets the ordinary
	# popup untouched, since this only wires the pad's axis_fn.
	var lang_item := nav.add_control(lang_popup)
	lang_item.axis_fn = func(d: int) -> void:
		var count := lang_popup.item_count
		lang_popup.selected = wrapi(lang_popup.selected + d, 0, count)
		_on_language_selected(lang_popup.selected)
		var arrow := lang_arrow_left if d < 0 else lang_arrow_right
		if is_instance_valid(arrow):
			var tw := create_tween()
			tw.tween_property(arrow, "scale", Vector2(1.3, 1.3), 0.08)
			tw.tween_property(arrow, "scale", Vector2.ONE, 0.08)

	# B already backs out via nav.cancelled below; X/Y below always mean
	# Title Screen/Credits regardless of focus - neither button is a focus
	# stop anymore, so none of the three are registered as nav items.
	ControllerUI.hide_in_gamepad(back_button)
	ControllerUI.hide_in_gamepad(credits_button)
	ControllerUI.hide_in_gamepad(title_screen_button)

	# Same row every screen's hints share now (ControllerUI.PROMPT_BAR_Y,
	# matching MainMenu's own A/Select row) - x stays each button's own.
	add_child(ControllerUI.make_button_hint(&"X", StringTable.get_string(StringTable.ID_TITLE_SCREEN), Vector2(title_screen_button.position.x, ControllerUI.PROMPT_BAR_Y), Vector2(title_screen_button.size.x, ControllerUI.HINT_ROW_HEIGHT)))
	add_child(ControllerUI.make_button_hint(&"Y", StringTable.get_string(StringTable.ID_CREDITS), Vector2(credits_button.position.x, ControllerUI.PROMPT_BAR_Y), Vector2(credits_button.size.x, ControllerUI.HINT_ROW_HEIGHT)))
	add_child(ControllerUI.make_button_hint(&"B", StringTable.get_string(StringTable.ID_BACK), Vector2(back_button.position.x, ControllerUI.PROMPT_BAR_Y), Vector2(back_button.size.x, ControllerUI.HINT_ROW_HEIGHT)))

	nav.activated.connect(func(item: FocusNav.NavItem) -> void:
		if item.control is Button:
			(item.control as Button).pressed.emit())
	nav.alt_activated.connect(func(_item: FocusNav.NavItem) -> void: _on_title_screen_pressed())
	nav.alt2_activated.connect(func(_item: FocusNav.NavItem) -> void: _on_credits_pressed())
	nav.cancelled.connect(_on_back_pressed)
	nav.focus_first()

func _make_lang_arrow(tex: Texture2D, fallback_char: String, pos: Vector2) -> Control:
	if tex != null:
		var rect := TextureRect.new()
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = Vector2(24, 24)
		rect.size = Vector2(24, 24)
		rect.texture = tex
		rect.position = pos
		rect.pivot_offset = Vector2(12, 12)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
		return rect
	else:
		var label := Label.new()
		label.text = fallback_char
		label.position = pos
		label.size = Vector2(24, 24)
		label.custom_minimum_size = Vector2(24, 24)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.pivot_offset = Vector2(12, 12)
		label.add_theme_font_override("font", Game.font_stylish)
		label.add_theme_font_size_override("font_size", UIConstants.OPTIONS_LANG_ARROW_FONT_SIZE)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 3)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		return label

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
	# The heading is the one control here on the decorative face (the rest
	# are baked into the scene on the static body face) - it swaps to a
	# Cyrillic fallback for Russian (see Game._update_fonts_for_language),
	# so it has to be re-applied on every language switch, not just at
	# construction.
	title.add_theme_font_override("font", Game.font_title)

	title.text = StringTable.get_string(StringTable.ID_OPTIONS)
	UIButtonStyle.fit_menu_button_text(title, TITLE_ICON_GAP_WIDTH)
	label_music.text = StringTable.get_string(StringTable.ID_MUSIC)
	UIButtonStyle.fit_button_text(label_music)
	label_sfx.text = StringTable.get_string(StringTable.ID_SFX)
	UIButtonStyle.fit_button_text(label_sfx)
	label_lang.text = StringTable.get_string(StringTable.ID_LANGUAGE)
	UIButtonStyle.fit_button_text(label_lang)
	back_button.text = StringTable.get_string(StringTable.ID_BACK)
	UIButtonStyle.fit_button_text(back_button)
	credits_button.text = StringTable.get_string(StringTable.ID_CREDITS)
	UIButtonStyle.fit_button_text(credits_button)
	title_screen_button.text = StringTable.get_string(StringTable.ID_TITLE_SCREEN)
	UIButtonStyle.fit_button_text(title_screen_button)

func _on_back_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_back_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")

func _on_credits_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/Credits.tscn")

func _on_title_screen_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_back_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/TitleScreen.tscn")
