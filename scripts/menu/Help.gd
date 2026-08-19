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
##
## The 6 pages (background, backing plates, label boxes) live in Help.tscn
## now - positions/sizes are real scene data, editable in the Godot editor.
## Only the text (StringTable-sourced) and the per-language font-fit stay
## script-assigned, via _fill_page below. The page dots and gamepad prompt
## bar stay fully script-built (dot count/state and prompt visibility are
## runtime-computed, not fixed content).

const SCREEN_W := 960
const ASSETS := "res://assets/"
const PAGE_COUNT := 6
## Gallery-style swipe: a small flick in either direction commits to the
## next/prev page immediately, instead of needing to drag past half the
## page width.
const SWIPE_THRESHOLD := 24

const DOT_SIZE := 6.0
const DOT_GAP := 14.0
const DOT_Y := 534.0

@onready var scroll: ScrollContainer = $Scroll
@onready var close_button: Button = $CloseButton
var _dragging := false
var _drag_start_scroll := 0
var _drag_start_x := 0.0
var _current_page := 0
var _dots: Array = []  # ColorRect per page
var _page_stick_locked := false

func _ready() -> void:
	scroll.gui_input.connect(_on_scroll_gui_input)

	_fill_page("PresentationPage", {"Label1": StringTable.ID_HELP_PRESENTATION})
	_fill_page("CardsPage", {"Label1": StringTable.ID_HELP_CARDS})
	_fill_page("MainPage", {
		"Label1": StringTable.ID_HELP_MAIN1,
		"Label2": StringTable.ID_HELP_MAIN2,
		"Label3": StringTable.ID_HELP_MAIN3,
		"LabelOnline": StringTable.ID_HELP_MAIN_ONLINE,
		"Label4": StringTable.ID_HELP_MAIN4,
	})
	_fill_page("DeckSelectPage", {
		"Label1": StringTable.ID_HELP_DECKSELECT1,
		"Label2": StringTable.ID_HELP_DECKSELECT2,
		"Label3": StringTable.ID_HELP_DECKSELECT3,
		"Label4": StringTable.ID_HELP_DECKSELECT4,
	})
	_fill_page("BattlePage", {
		"Label1": StringTable.ID_HELP_BATTLE1,
		"Label2": StringTable.ID_HELP_BATTLE2,
		"Label3": StringTable.ID_HELP_BATTLE3,
		"Label4": StringTable.ID_HELP_BATTLE4,
		"Label5": StringTable.ID_HELP_BATTLE5,
	})
	_fill_page("ShopPage", {
		"Label1": StringTable.ID_HELP_SHOP1,
		"Label2": StringTable.ID_HELP_SHOP2,
		"Label3": StringTable.ID_HELP_SHOP3,
	})

	_style_close_button()
	close_button.pressed.connect(_on_close_pressed)

	_build_page_dots()

	# Pages aren't discrete items to point a hand at - they're a filmstrip -
	# so there's no FocusNav here at all: paging and closing are handled
	# directly below. One shared spot on the left, at the row every screen's
	# hints share now (ControllerUI.PROMPT_BAR_Y): mouse/touch keeps the real
	# X button there, gamepad mode swaps in a B+Indietro hint at the exact
	# same rect instead of two separate close controls in two corners.
	ControllerUI.hide_hand()
	ControllerUI.hide_in_gamepad(close_button)
	add_child(ControllerUI.make_button_hint(&"B", StringTable.get_string(StringTable.ID_BACK), close_button.position, Vector2(140, ControllerUI.HINT_ROW_HEIGHT)))

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

## Sets each named label's text (StringTable) and re-fits its font to the
## box the scene already gives it - some translations (e.g. Russian on the
## Cards page) wrap to more lines than the authored box allows, clipping the
## end of the text since pages set clip_contents = true.
func _fill_page(page_name: String, labels: Dictionary) -> void:
	var page: Control = scroll.get_node("Pages/" + page_name)
	for label_name in labels:
		var label: Label = page.get_node(label_name)
		label.text = StringTable.get_string(labels[label_name])
		UIButtonStyle.fit_paragraph_to_box(label, label.size)

func _style_close_button() -> void:
	# A font glyph instead of button_delete_save.png's raster X: same X at any
	# scale reads crisp (the PNG was low-res and blurred/blocked when the
	# canvas stretched to a real screen size), and colors as plain text
	# theme overrides instead of needing a separately-authored asset.
	close_button.text = "X"
	close_button.add_theme_font_override("font", Game.font_stylish)
	close_button.add_theme_font_size_override("font_size", UIConstants.HELP_CLOSE_BUTTON_FONT_SIZE)
	close_button.add_theme_color_override("font_color", UIConstants.COLOR_DANGER)
	close_button.add_theme_color_override("font_hover_color", UIConstants.COLOR_DANGER_HOVER)
	close_button.add_theme_color_override("font_pressed_color", UIConstants.COLOR_DANGER_PRESSED)
	close_button.add_theme_color_override("font_outline_color", Color.BLACK)
	close_button.add_theme_constant_override("outline_size", 2)

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
	close_button.add_theme_stylebox_override("normal", normal)

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
	close_button.add_theme_stylebox_override("pressed", pressed)
	close_button.add_theme_stylebox_override("hover", normal)

func _build_page_dots() -> void:
	var total_w := PAGE_COUNT * DOT_SIZE + (PAGE_COUNT - 1) * DOT_GAP
	var start_x := (SCREEN_W - total_w) / 2.0
	for i in PAGE_COUNT:
		var dot := ColorRect.new()
		dot.size = Vector2(DOT_SIZE, DOT_SIZE)
		dot.position = Vector2(start_x + i * (DOT_SIZE + DOT_GAP), DOT_Y)
		dot.color = UIConstants.HELP_DOT_COLOR if i == 0 else Color(1, 1, 1, UIConstants.HELP_DOT_INACTIVE_ALPHA)
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
