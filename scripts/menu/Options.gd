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
var lang_arrow_left: Label
var lang_arrow_right: Label
var nav: FocusNav

func _ready() -> void:
	var font_stylish: Font = Game.font_stylish

	title.add_theme_font_size_override("font_size", UIConstants.OPTIONS_TITLE_FONT_SIZE)

	for l in [label_music, label_sfx, label_lang]:
		l.add_theme_font_size_override("font_size", UIConstants.LABEL_FONT_SIZE_36)
		l.add_theme_color_override("font_color", Color.BLACK)
		l.add_theme_color_override("font_shadow_color", UIConstants.COLOR_SHADOW_DIM)
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 1)

	for btn in [back_button, credits_button, title_screen_button]:
		UIButtonStyle.apply(btn)
		btn.add_theme_font_size_override("font_size", UIConstants.LABEL_FONT_SIZE_36)
		btn.add_theme_color_override("font_color", Color.BLACK)
		btn.add_theme_color_override("font_shadow_color", UIConstants.COLOR_SHADOW_DIM)
		btn.add_theme_constant_override("shadow_offset_x", 1)
		btn.add_theme_constant_override("shadow_offset_y", 1)

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
	# The one text control on this screen that isn't a UIButtonStyle button,
	# so it needs the same pointer feedback spelled out.
	lang_popup.add_theme_color_override("font_hover_color", UIButtonStyle.hover_color(Color.WHITE))
	lang_popup.item_selected.connect(_on_language_selected)

	# Pad left/right cycles the language directly (see _setup_nav's axis_fn)
	# instead of opening lang_popup's own native dropdown arrow - that arrow
	# means nothing to a pad, so these two only show up in gamepad mode to
	# spell out what the d-pad actually does here.
	lang_arrow_left = _make_lang_arrow("<", Vector2(lang_popup.position.x - 30, lang_popup.position.y))
	lang_arrow_right = _make_lang_arrow(">", Vector2(lang_popup.position.x + lang_popup.size.x + 6, lang_popup.position.y))
	ControllerUI.show_in_gamepad(lang_arrow_left)
	ControllerUI.show_in_gamepad(lang_arrow_right)

	back_button.pressed.connect(_on_back_pressed)
	credits_button.pressed.connect(_on_credits_pressed)
	# New addition (not in the reference): mirror of back_button on the
	# opposite corner (960 - 42 - 115 = 803, same y/size) - returns to the
	# Title Screen instead of MainMenu.
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

func _make_lang_arrow(text: String, pos: Vector2) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = Vector2(24, 56)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
	# Re-applied every call (not just at construction): Game.font_stylish
	# may now point at a different actual font than when these controls were
	# built, if the language just switched to/from one that needs a
	# different font (see Game._update_fonts_for_language).
	for ctrl in [label_music, label_sfx, label_lang, back_button, credits_button, title_screen_button]:
		ctrl.add_theme_font_override("font", Game.font_stylish)
	# The heading is the one control here on the decorative face. It was in
	# the loop above, which meant it was set to the decorative font at
	# construction and then quietly overwritten with the body font a few lines
	# later - every time, since this runs once at startup too.
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
