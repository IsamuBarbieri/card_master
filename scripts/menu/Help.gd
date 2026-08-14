extends Control
## Port of UIHelp.cs / UIHelp.composer.cs + the 6 Panel_Help*.cs pages
## (960x544 design canvas each). PagePanel's swipe-between-pages behavior is
## approximated with a horizontal ScrollContainer + click-drag panning and
## mouse-wheel paging (PagePanel is touch-swipe only; a mouse has neither
## gesture) that both snap to the nearest page, same end result as
## PagePanel's paging. A row of dots at the bottom (not part of the
## original, which relied on the touch swipe itself being discoverable)
## hints that there's more to scroll.
## Font style is approximated: font_stylish only, no bold+italic variant
## available (same approximation used project-wide for text shadows etc).
## Font size is a deliberate deviation from the composer's literal 20: 20
## read as too small with font_stylish (a slender display face, not the
## chunky default "System" font the original used) - bumped up, then eased
## back down slightly so the Cards page (the longest text) still fits its
## box without clipping.

const SCREEN_W := 960
const SCREEN_H := 544
const ASSETS := "res://assets/"
const FONT_SIZE := 24
const PAGE_COUNT := 6
## Gallery-style swipe: a small flick in either direction commits to the
## next/prev page immediately, instead of needing to drag past half the
## page width.
const SWIPE_THRESHOLD := 24

const DOT_SIZE := 6.0
const DOT_GAP := 14.0
const DOT_Y := 534.0

var scroll: ScrollContainer
var _dragging := false
var _drag_start_scroll := 0
var _drag_start_x := 0.0
var _current_page := 0
var _dots: Array = []  # ColorRect per page
var _page_stick_locked := false
var close_button: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.gui_input.connect(_on_scroll_gui_input)
	add_child(scroll)

	var pages := HBoxContainer.new()
	pages.add_theme_constant_override("separation", 0)
	pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(pages)

	# Help_Panel.AddPage order from UIHelp.composer.cs.
	pages.add_child(_build_presentation_page())
	pages.add_child(_build_cards_page())
	pages.add_child(_build_main_page())
	pages.add_child(_build_deckselect_page())
	pages.add_child(_build_battle_page())
	pages.add_child(_build_shop_page())

	close_button = _make_close_button()
	close_button.pressed.connect(_on_close_pressed)
	add_child(close_button)

	_build_page_dots()

	# Pages aren't discrete items to point a hand at - they're a filmstrip -
	# so there's no FocusNav here at all: paging and closing are handled
	# directly below. The X close button is mouse/touch-only in gamepad mode,
	# physically replaced by a B hint at its own spot - B already closes via
	# _unhandled_input below either way.
	ControllerUI.hide_hand()
	ControllerUI.hide_in_gamepad(close_button)
	# Icon-only: the button's own 42x42 corner box has no room for a label
	# too (make_button_hint's centered glyph+text pair would run off the
	# right edge of the whole 960-wide screen) - the bottom bar already
	# spells out "B Indietro" in words.
	add_child(ControllerUI.make_icon_hint(&"B", close_button.position, close_button.size))
	add_child(ControllerUI.make_prompt_bar([
		[&"B", StringTable.get_string(StringTable.ID_BACK)],
	]))

func _process(_delta: float) -> void:
	# Left stick moves at most one page per push, same as the d-pad/keyboard
	# already do naturally (they're discrete button events) - without this
	# gate, holding the stick over at full deflection re-fires nav_left/
	# nav_right's "just pressed" edge on nearly every analog sample, flipping
	# several pages in a single push instead of one.
	if not ControllerUI.is_gamepad():
		_page_stick_locked = false
		return
	var left := Input.get_action_strength(&"nav_left") > 0.0
	var right := Input.get_action_strength(&"nav_right") > 0.0
	if not left and not right:
		_page_stick_locked = false
	elif not _page_stick_locked:
		_page_stick_locked = true
		_go_to_page(_current_page + (1 if right else -1))

func _unhandled_input(event: InputEvent) -> void:
	if not ControllerUI.is_gamepad():
		return
	if event.is_action_pressed(&"nav_accept") or event.is_action_pressed(&"nav_cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()

func _make_page(bg_path: String) -> Control:
	var page := Control.new()
	page.custom_minimum_size = Vector2(SCREEN_W, SCREEN_H)
	page.clip_contents = true
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg_color := ColorRect.new()
	bg_color.color = Color(153.0 / 255.0, 153.0 / 255.0, 153.0 / 255.0)
	bg_color.size = Vector2(SCREEN_W, SCREEN_H)
	bg_color.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(bg_color)

	var bg := TextureRect.new()
	bg.texture = load(ASSETS + bg_path)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(bg)

	return page

func _add_label(page: Control, pos: Vector2, size: Vector2, string_id: int, center := false) -> void:
	var font_stylish: Font = Game.font_stylish
	var label := FixedSizeLabel.new()
	label.position = pos
	label.size = size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_font_override("font", font_stylish)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = StringTable.get_string(string_id)
	page.add_child(label)
	# New QoL addition (not in the reference, which never localized past its
	# fixed English/Italian text): shrinks the font until the wrapped
	# paragraph fits the box vertically - some translations (e.g. Russian on
	# the Cards page) wrap to more lines than FONT_SIZE's box allows,
	# clipping the end of the text since pages set clip_contents = true.
	UIButtonStyle.fit_paragraph_to_box(label, size)

func _build_presentation_page() -> Control:
	var page := _make_page("help/help_presentation.png")
	_add_label(page, Vector2(47, 63), Vector2(880, 305), StringTable.ID_HELP_PRESENTATION)
	return page

func _build_cards_page() -> Control:
	var page := _make_page("help/help_card.png")
	_add_label(page, Vector2(31, 36), Vector2(600, 386), StringTable.ID_HELP_CARDS)
	return page

func _build_main_page() -> Control:
	var page := _make_page("help/help_main_menu.png")
	_add_label(page, Vector2(338, 79), Vector2(273, 125), StringTable.ID_HELP_MAIN1, true)
	_add_label(page, Vector2(16, 138), Vector2(273, 125), StringTable.ID_HELP_MAIN2, true)
	_add_label(page, Vector2(680, 138), Vector2(273, 125), StringTable.ID_HELP_MAIN3, true)
	_add_label(page, Vector2(304, 337), Vector2(351, 125), StringTable.ID_HELP_MAIN4, true)
	return page

func _build_deckselect_page() -> Control:
	var page := _make_page("help/help_deck_select.png")
	_add_label(page, Vector2(0, 0), Vector2(960, 50), StringTable.ID_HELP_DECKSELECT1, true)
	_add_label(page, Vector2(353, 76), Vector2(253, 125), StringTable.ID_HELP_DECKSELECT2, true)
	_add_label(page, Vector2(46, 141), Vector2(253, 125), StringTable.ID_HELP_DECKSELECT3, true)
	_add_label(page, Vector2(283, 399), Vector2(393, 125), StringTable.ID_HELP_DECKSELECT4, true)
	return page

func _build_battle_page() -> Control:
	var page := _make_page("help/help_battle.png")
	_add_label(page, Vector2(472, 135), Vector2(239, 125), StringTable.ID_HELP_BATTLE1, true)
	_add_label(page, Vector2(320, 10), Vector2(222, 125), StringTable.ID_HELP_BATTLE2, true)
	_add_label(page, Vector2(17, 241), Vector2(252, 125), StringTable.ID_HELP_BATTLE3, true)
	_add_label(page, Vector2(47, 100), Vector2(177, 35), StringTable.ID_HELP_BATTLE4, true)
	_add_label(page, Vector2(66, 340), Vector2(151, 46), StringTable.ID_HELP_BATTLE5, true)
	return page

func _build_shop_page() -> Control:
	var page := _make_page("help/help_shop.png")
	_add_label(page, Vector2(280, 267), Vector2(253, 125), StringTable.ID_HELP_SHOP1, true)
	_add_label(page, Vector2(644, 426), Vector2(253, 125), StringTable.ID_HELP_SHOP2, true)
	_add_label(page, Vector2(651, 110), Vector2(280, 268), StringTable.ID_HELP_SHOP3, true)
	return page

func _make_close_button() -> Button:
	var btn := Button.new()
	btn.position = Vector2(901, 484)
	btn.size = Vector2(42, 42)
	# A font glyph instead of button_delete_save.png's raster X: same X at any
	# scale reads crisp (the PNG was low-res and blurred/blocked when the
	# canvas stretched to a real screen size), and colors as plain text
	# theme overrides instead of needing a separately-authored asset.
	btn.text = "X"
	btn.add_theme_font_override("font", Game.font_stylish)
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_color_override("font_color", Color(0.85, 0.1, 0.1))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.25, 0.25))
	btn.add_theme_color_override("font_pressed_color", Color(0.6, 0.0, 0.0))
	btn.add_theme_color_override("font_outline_color", Color.BLACK)
	btn.add_theme_constant_override("outline_size", 2)

	var normal := StyleBoxTexture.new()
	normal.texture = load(ASSETS + "button_9patch_normal.png")
	normal.texture_margin_left = 21
	normal.texture_margin_right = 21
	normal.texture_margin_top = 21
	normal.texture_margin_bottom = 21
	# content_margin left at -1 (default) falls back to texture_margin, which
	# on a 42x42 button eats the entire width/height (21+21=42) and leaves
	# the glyph zero room to draw in - pin it small instead so the X shows.
	normal.content_margin_left = 4
	normal.content_margin_right = 4
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", normal)

	var pressed := StyleBoxTexture.new()
	pressed.texture = load(ASSETS + "button_9patch_press.png")
	pressed.texture_margin_left = 21
	pressed.texture_margin_right = 21
	pressed.texture_margin_top = 21
	pressed.texture_margin_bottom = 21
	pressed.content_margin_left = 4
	pressed.content_margin_right = 4
	pressed.content_margin_top = 4
	pressed.content_margin_bottom = 4
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("hover", normal)

	return btn

func _build_page_dots() -> void:
	var total_w := PAGE_COUNT * DOT_SIZE + (PAGE_COUNT - 1) * DOT_GAP
	var start_x := (SCREEN_W - total_w) / 2.0
	for i in PAGE_COUNT:
		var dot := ColorRect.new()
		dot.size = Vector2(DOT_SIZE, DOT_SIZE)
		dot.position = Vector2(start_x + i * (DOT_SIZE + DOT_GAP), DOT_Y)
		dot.color = Color(1, 1, 1, 1.0 if i == 0 else 0.35)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dot)
		_dots.append(dot)

func _update_page_dots() -> void:
	for i in _dots.size():
		_dots[i].color.a = 1.0 if i == _current_page else 0.35

func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = true
			_drag_start_scroll = scroll.scroll_horizontal
			_drag_start_x = event.position.x
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			_go_to_page(_current_page - 1)
			scroll.accept_event()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			_go_to_page(_current_page + 1)
			scroll.accept_event()
			return
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _dragging:
		_dragging = false
		_snap_to_nearest_page()
	elif event is InputEventMouseMotion and _dragging:
		scroll.scroll_horizontal = _drag_start_scroll - int(event.position.x - _drag_start_x)

func _snap_to_nearest_page() -> void:
	var delta: int = scroll.scroll_horizontal - _drag_start_scroll
	if absi(delta) >= SWIPE_THRESHOLD:
		_go_to_page(_current_page + (1 if delta > 0 else -1))
	else:
		_go_to_page(_current_page)

func _go_to_page(page_index: int) -> void:
	_current_page = clampi(page_index, 0, PAGE_COUNT - 1)
	_update_page_dots()
	var tw := create_tween()
	tw.tween_property(scroll, "scroll_horizontal", _current_page * SCREEN_W, 0.25) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _on_close_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_back_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
