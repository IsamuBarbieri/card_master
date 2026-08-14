extends Control
## Port of DeckSelectScene.cs + gsWaitingInput/gsDeckScroll/gsDragCard.cs +
## UIDeckSelect.cs/.composer.cs (960x544 design canvas).
##
## PSM drives this scene from one central OnInput(event,x,y) callback with a
## hand-rolled hit-test dispatch (checking the lower deck, then Panel_Left,
## then Panel_Right) rather than per-widget input events - the state machine
## itself (WaitingInput/DeckScroll/DragCard) is the real game logic here, so
## it's kept 1:1 rather than reworked into Godot's per-Control input model:
## one full-screen Control (this scene's root) captures all mouse input via
## _gui_input and replicates the same manual hit-testing dispatch.
##
## SlideTransition animations are skipped (plain change_scene_to_file), same
## simplification as every other menu scene ported so far.

const SCREEN_W := 960
const SCREEN_H := 544
const ASSETS := "res://assets/"
const LABEL_FONT_SIZE := 36

const PLACEHOLDER_POS := [
	Vector2(237, 391), Vector2(334, 391), Vector2(431, 391),
	Vector2(528, 391), Vector2(625, 391),
]
const PLACEHOLDER_SIZE := Vector2(96, 128)

const GET_BACK_TIME := 0.1
const DECK_SCROLL_TIME := 0.25
const LAUNCH_BATTLE_DELAY := 1.2

enum GameState { WAITING_INPUT, DECK_SCROLL, DRAG_CARD }

var game_state: GameState = GameState.WAITING_INPUT
var game_state_mode: int = 0
var next_sel: int = 0  # 0 none, 1 left, 2 right, 10+ lower(index)

var deck_selector_left := DeckSelectorWheel.new()
var deck_selector_right := DeckSelectorWheel.new()
var lower_deck := LowerDeck.new()

var panel_left: Control
var panel_right: Control
var placeholders: Array = []  # Array[Control], 5

var label_info_name: Label
var label_value_offense: Label
var label_value_type: Label
var label_value_pdef: Label
var label_value_mdef: Label
var button_play: Button
var busy_indicator: BusySpinner

var drag_ghost: CardView
var selection_outline: SelectionOutline
var nav: FocusNav

# --- WaitingInput state (SWaitingInput) ---
var wi_x: int = 0
var wi_y: int = 0
var wi_panel: Control = null
var wi_selector: DeckSelectorWheel = null

# --- DeckScroll state (SDeckScroll) ---
var ds_selector: DeckSelectorWheel
var ds_moving_vert: bool = false
var ds_cur_card_stats: Card = null
var ds_elapsed: float = 0.0
var ds_start_angle: float = 0.0
var ds_diff: float = 0.0

# --- DragCard state (SDragCard) ---
var dc_selector: DeckSelectorWheel
var dc_from_left: bool = false
var dc_from_right: bool = false
var dc_from_deck: bool = false
var dc_deck_index: int = -1
var dc_start_x: int = 0
var dc_start_y: int = 0
var dc_card_pos: Vector2 = Vector2.ZERO
var dc_lower_deck_hover_index: int = -1
var dc_lower_deck_hover_incs: Array = [0, 0, 0, 0, 0]
var dc_lower_deck_timer: int = 0

var launch_battle_delay: float = 0.0

var _pointer_down := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_build_ui()

	for card in Game.player.cards:
		card.is_on_deck = false

	# Restore the last deck played: cards captured away since then simply
	# aren't in Game.player.cards anymore, so their slot is left empty
	# (marked is_on_deck here, before the wheels init, so they don't also
	# show up there).
	var restored: Array = [null, null, null, null, null]
	for i in 5:
		var uid: int = Game.player.last_deck[i]
		if uid == -1:
			continue
		for card in Game.player.cards:
			if card.unique_id == uid:
				card.is_on_deck = true
				restored[i] = card
				break

	deck_selector_left.init(panel_left, Game.player.cards, false, false, false)
	deck_selector_right.init(panel_right, Game.player.cards, true, false, false)
	lower_deck.init(placeholders)

	for i in 5:
		if restored[i] != null:
			lower_deck.add_card(i, restored[i])

	_enter_waiting_input()
	_setup_nav()

## Mirrors next_sel's own 7-state model (1=left wheel, 2=right wheel,
## 10+i=deck slot i) rather than the spatial scorer: a spatial jump from the
## left wheel (y~246) straight to the right wheel (y~246, x~786) scores
## lower than reaching the deck slots below (y~455, penalized by
## CROSS_AXIS_PENALTY) and would skip them entirely. Explicit link()s make
## left/right walk the same 7 states next_sel already models; wrap links are
## added asymmetrically at the two ends so the chain cycles.
func _setup_nav() -> void:
	nav = FocusNav.new()
	add_child(nav)

	var left_item := nav.add_virtual(&"wheel", func() -> Rect2:
		return Rect2(deck_selector_left.central_card_x(), deck_selector_left.central_card_y(), deck_selector_left.card_width, deck_selector_left.card_height), 1)
	left_item.axis_fn_v = func(d: int) -> void: _snap_to_box(deck_selector_left, 1 if d > 0 else 3, false)

	var slot_items: Array = []
	for i in 5:
		slot_items.append(nav.add_virtual(&"slot", (func(idx: int) -> Rect2:
			return Rect2(lower_deck.card_x(idx), lower_deck.card_y(idx), lower_deck.card_width(idx), lower_deck.card_height(idx))).bind(i), 10 + i))

	var right_item := nav.add_virtual(&"wheel", func() -> Rect2:
		return Rect2(deck_selector_right.central_card_x(), deck_selector_right.central_card_y(), deck_selector_right.card_width, deck_selector_right.card_height), 2)
	right_item.axis_fn_v = func(d: int) -> void: _snap_to_box(deck_selector_right, 1 if d > 0 else 3, false)

	nav.link(left_item, slot_items[0], FocusNav.DIR_RIGHT)
	for i in 4:
		nav.link(slot_items[i], slot_items[i + 1], FocusNav.DIR_RIGHT)
	nav.link(slot_items[4], right_item, FocusNav.DIR_RIGHT)
	nav.link(right_item, left_item, FocusNav.DIR_RIGHT, false)
	nav.link(left_item, right_item, FocusNav.DIR_LEFT, false)

	nav.activated.connect(_on_nav_activated)
	nav.alt2_activated.connect(func(_item: FocusNav.NavItem) -> void:
		if not button_play.disabled:
			button_play.pressed.emit())
	nav.cancelled.connect(_on_back_pressed)
	nav.focus_by_meta(next_sel if next_sel != 0 else 1)

	add_child(ControllerUI.make_prompt_bar([
		[&"A", StringTable.get_string(StringTable.ID_SELECT)],
		[&"Y", StringTable.get_string(StringTable.ID_PLAY_BATTLE)],
		[&"B", StringTable.get_string(StringTable.ID_BACK)],
	]))

## A's semantics mirror _handle_double_click, keyed by the focused nav item
## instead of a click point: a wheel sends its centered card to the first
## free deck slot, a slot returns its card to the matching wheel.
func _on_nav_activated(item: FocusNav.NavItem) -> void:
	if game_state != GameState.WAITING_INPUT:
		return
	if item.id == &"wheel":
		var selector: DeckSelectorWheel = deck_selector_left if item.meta == 1 else deck_selector_right
		var free_index := lower_deck.get_unused_index()
		if free_index == -1:
			return
		_cancel_current_interaction()
		var cstats: Card = selector.remove_current_card()
		lower_deck.add_card(free_index, cstats)
		next_sel = 10 + free_index
	elif item.id == &"slot":
		var index: int = item.meta - 10
		var cstats: Card = lower_deck.card_stats(index)
		if cstats == null:
			return
		_cancel_current_interaction()
		lower_deck.remove_card(index)
		if cstats.is_favourite:
			deck_selector_right.add_card(cstats)
			next_sel = 2
		else:
			deck_selector_left.add_card(cstats)
			next_sel = 1
	else:
		return
	_enter_waiting_input()
	nav.focus_by_meta(next_sel)

func _build_ui() -> void:
	var font_stylish: Font = Game.font_stylish

	var bg := TextureRect.new()
	bg.texture = load(ASSETS + "common_bkg_clean.png")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	add_child(bg)

	var deck_bar := TextureRect.new()
	deck_bar.texture = load(ASSETS + "common_transp_box_b.png")
	deck_bar.stretch_mode = TextureRect.STRETCH_SCALE
	deck_bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	deck_bar.position = Vector2(228, 377)
	deck_bar.size = Vector2(503, 157)
	add_child(deck_bar)

	panel_left = _make_selector_panel(Vector2(0, 72), Vector2(348, 348))
	panel_right = _make_selector_panel(Vector2(612, 72), Vector2(348, 348))

	for i in 5:
		var ph := Control.new()
		ph.position = PLACEHOLDER_POS[i]
		ph.size = PLACEHOLDER_SIZE
		ph.clip_contents = true
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg_rect := ColorRect.new()
		bg_rect.color = Color(153.0 / 255.0, 153.0 / 255.0, 153.0 / 255.0, 127.0 / 255.0)
		bg_rect.size = PLACEHOLDER_SIZE
		bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ph.add_child(bg_rect)
		add_child(ph)
		placeholders.append(ph)

	button_play = _make_text_button(StringTable.get_string(StringTable.ID_PLAY_BATTLE), Vector2(798, 463), Vector2(115, 56), font_stylish)
	button_play.pressed.connect(_on_play_pressed)

	var back_button := _make_text_button(StringTable.get_string(StringTable.ID_BACK), Vector2(42, 463), Vector2(115, 56), font_stylish)
	back_button.pressed.connect(_on_back_pressed)
	# B already backs out via nav.cancelled (_setup_nav) - hide the button
	# itself in gamepad mode rather than also making it a redundant focus stop.
	ControllerUI.hide_in_gamepad(back_button)

	var info_bkg := TextureRect.new()
	info_bkg.texture = load(ASSETS + "common_transp_box_a.png")
	info_bkg.stretch_mode = TextureRect.STRETCH_SCALE
	info_bkg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	info_bkg.position = Vector2(352, 106)
	info_bkg.size = Vector2(260, 252)
	add_child(info_bkg)

	var label_select5 := _make_label(Vector2(313, 10), Vector2(333, 43), font_stylish)
	label_select5.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_select5.text = StringTable.get_string(StringTable.ID_DECK_SELECT_CARDS)
	add_child(label_select5)
	UIButtonStyle.fit_button_text(label_select5)

	var label_your_deck := _make_label(Vector2(67, 32), Vector2(214, 36), font_stylish)
	label_your_deck.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_your_deck.text = StringTable.get_string(StringTable.ID_CARDS)
	add_child(label_your_deck)
	UIButtonStyle.fit_button_text(label_your_deck)

	var label_your_prefs := _make_label(Vector2(679, 32), Vector2(214, 36), font_stylish)
	label_your_prefs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_your_prefs.text = StringTable.get_string(StringTable.ID_FAVORITE_CARDS)
	add_child(label_your_prefs)
	UIButtonStyle.fit_button_text(label_your_prefs)

	var label_info_offense := _make_label(Vector2(361, 161), Vector2(174, 41), font_stylish)
	label_info_offense.text = StringTable.get_string(StringTable.ID_CARD_ATTACK)
	add_child(label_info_offense)
	UIButtonStyle.fit_button_text(label_info_offense)

	var label_info_type := _make_label(Vector2(361, 209), Vector2(174, 41), font_stylish)
	label_info_type.text = StringTable.get_string(StringTable.ID_CARD_TYPE)
	add_child(label_info_type)
	UIButtonStyle.fit_button_text(label_info_type)

	var label_info_pdef := _make_label(Vector2(361, 257), Vector2(169, 41), font_stylish)
	label_info_pdef.text = StringTable.get_string(StringTable.ID_CARD_PHYSICAL_DEFENSE)
	add_child(label_info_pdef)
	UIButtonStyle.fit_button_text(label_info_pdef)

	var label_info_mdef := _make_label(Vector2(361, 304), Vector2(169, 41), font_stylish)
	label_info_mdef.text = StringTable.get_string(StringTable.ID_CARD_MAGICAL_DEFENSE)
	add_child(label_info_mdef)
	UIButtonStyle.fit_button_text(label_info_mdef)

	label_info_name = _make_label(Vector2(361, 118), Vector2(242, 41), font_stylish)
	label_info_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_info_name.text = StringTable.get_string(StringTable.ID_CARD_STATS)
	add_child(label_info_name)
	UIButtonStyle.fit_button_text(label_info_name)

	label_value_offense = _make_label(Vector2(493, 161), Vector2(108, 41), font_stylish)
	label_value_offense.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_value_offense.text = "- - -"
	add_child(label_value_offense)

	label_value_type = _make_label(Vector2(493, 209), Vector2(108, 41), font_stylish)
	label_value_type.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_value_type.text = "---"
	add_child(label_value_type)

	label_value_pdef = _make_label(Vector2(493, 257), Vector2(108, 41), font_stylish)
	label_value_pdef.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_value_pdef.text = "- - -"
	add_child(label_value_pdef)

	label_value_mdef = _make_label(Vector2(493, 304), Vector2(108, 41), font_stylish)
	label_value_mdef.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_value_mdef.text = "- - -"
	add_child(label_value_mdef)

	busy_indicator = BusySpinner.new()
	busy_indicator.position = Vector2(912, 496)
	busy_indicator.size = Vector2(48, 48)
	busy_indicator.pivot_offset = Vector2(24, 24)
	busy_indicator.visible = false
	add_child(busy_indicator)

	drag_ghost = CardView.new()
	drag_ghost.visible = false
	drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_ghost.z_index = 100
	add_child(drag_ghost)

	selection_outline = SelectionOutline.new()
	selection_outline.set_anchors_preset(Control.PRESET_FULL_RECT)
	selection_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Wheel cards set z_index up to Z_BASE (10, DeckSelectorWheel.gd) so the
	# centered card draws above its neighbors - without a z_index of its own
	# the outline (default 0) was drawing behind them despite being added
	# last in the tree, since z_index wins over add-order. Kept under
	# drag_ghost (100) so a dragged card still passes over the glow.
	selection_outline.z_index = 50
	add_child(selection_outline)

func _make_selector_panel(pos: Vector2, panel_size: Vector2) -> Control:
	var panel := Control.new()
	panel.position = pos
	panel.size = panel_size
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var symbol := TextureRect.new()
	symbol.texture = load(ASSETS + "common_symbol_a.png")
	symbol.stretch_mode = TextureRect.STRETCH_SCALE
	symbol.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	symbol.size = panel_size
	symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(symbol)

	add_child(panel)
	return panel

func _make_label(pos: Vector2, label_size: Vector2, font: Font) -> Label:
	var label := FixedSizeLabel.new()
	label.position = pos
	label.size = label_size
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", Color.BLACK)
	label.add_theme_color_override("font_shadow_color", Color(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0, 0.5))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

func _make_text_button(label: String, pos: Vector2, btn_size: Vector2, font: Font) -> Button:
	var btn := FixedSizeButton.new()
	UIButtonStyle.apply(btn)
	btn.text = label
	btn.position = pos
	btn.size = btn_size
	btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	btn.add_theme_color_override("font_color", Color.BLACK)
	btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	btn.add_theme_constant_override("shadow_offset_x", 1)
	btn.add_theme_constant_override("shadow_offset_y", 1)
	add_child(btn)
	UIButtonStyle.fit_button_text(btn)
	return btn

func _hit_test(control: Control, x: int, y: int) -> bool:
	return Rect2(control.global_position, control.size).has_point(Vector2(x, y))

# ---------------------------------------------------------------- input ---

func _gui_input(event: InputEvent) -> void:
	if launch_battle_delay > 0.0:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var x := int(event.position.x)
		var y := int(event.position.y)
		if event.pressed:
			_pointer_down = true
			if event.double_click and _handle_double_click(x, y):
				return
			_route_click(x, y)
		else:
			_pointer_down = false
			_route_unclick(x, y)
	elif event is InputEventMouseMotion and _pointer_down:
		_route_click(int(event.position.x), int(event.position.y))

func _route_click(x: int, y: int) -> void:
	match game_state:
		GameState.WAITING_INPUT:
			_waiting_input_on_click(x, y)
		GameState.DECK_SCROLL:
			if game_state_mode == 0:
				ds_selector.on_input_click(x, y)
				_deck_scroll_update_card_info()
		GameState.DRAG_CARD:
			_drag_card_on_click(x, y)

## New QoL addition (not in the reference): double-click/double-tap a card
## to send it straight to its slot, instead of dragging it there by hand.
## A deck card goes back to its wheel (routed by is_favourite, same as the
## drag-swap-out path).
##
## For a WHEEL card, this only fires on the CENTERED one - hit_test_h_box
## matches any visible box, not just the centered one, and double-clicking
## while quickly browsing through neighboring wheel cards (the normal way to
## move from one card to another) used to teleport whatever card got
## double-clicked into the deck. A double-click on a neighbor card falls
## through to _route_click instead (see the caller) and behaves like an
## ordinary click: it just navigates/centers that card, nothing more.
## Returns true if the double-click was consumed.
func _handle_double_click(x: int, y: int) -> bool:
	var lower_index: int = lower_deck.get_valid_card_index_under_cursor(x, y)
	if lower_index != -1:
		_cancel_current_interaction()
		var cstats: Card = lower_deck.remove_card(lower_index)
		if cstats.is_favourite:
			deck_selector_right.add_card(cstats)
			next_sel = 2
		else:
			deck_selector_left.add_card(cstats)
			next_sel = 1
		_enter_waiting_input()
		return true

	var selectors: Array[DeckSelectorWheel] = [deck_selector_left, deck_selector_right]
	for selector in selectors:
		if not selector.central_card_hit_test(x, y):
			continue
		var free_index := lower_deck.get_unused_index()
		if free_index == -1:
			return true  # deck already full, nothing to do
		_cancel_current_interaction()
		var cstats: Card = selector.remove_current_card()
		lower_deck.add_card(free_index, cstats)
		next_sel = 10 + free_index
		_enter_waiting_input()
		return true

	return false

## Resets whatever WaitingInput/DeckScroll/DragCard was mid-flight so a
## double-click can act immediately regardless of what the first of its two
## clicks happened to start.
func _cancel_current_interaction() -> void:
	drag_ghost.visible = false
	for index in 5:
		if dc_lower_deck_hover_incs[index] != 0:
			placeholders[index].position.y += 2.0 * dc_lower_deck_hover_incs[index]
			dc_lower_deck_hover_incs[index] = 0

func _route_unclick(x: int, y: int) -> void:
	match game_state:
		GameState.WAITING_INPUT:
			_waiting_input_on_unclick(x, y)
		GameState.DECK_SCROLL:
			if game_state_mode == 0:
				game_state_mode = 1
				var res := ds_selector.on_input_unclick()
				ds_start_angle = res.start_angle
				ds_diff = res.angle_diff
				ds_elapsed = 0.0
		GameState.DRAG_CARD:
			_drag_card_on_unclick(x, y)
		_:
			pass

## New QoL addition (not in the reference): a plain click+release with no
## drag on a non-center wheel card auto-scrolls that card to the center,
## instead of requiring a manual drag past the 90-degree snap threshold.
func _waiting_input_on_unclick(x: int, y: int) -> void:
	var selector := wi_selector
	wi_panel = null
	wi_selector = null
	if selector == null:
		return

	var hi := selector.hit_test_h_box(x, y)
	if hi != -1:
		_snap_to_box(selector, hi, true)
		return

	var vi := selector.hit_test_v_box(x, y)
	if vi != -1:
		_snap_to_box(selector, vi, false)

func _snap_to_box(selector: DeckSelectorWheel, array_index: int, horz: bool) -> void:
	var delta: float = selector.snap_delta_for_box(array_index, horz)
	if delta == 0.0:
		return

	# on_input_close() (called when the ease-out below finishes) reads the
	# wheel's own moving_vert field, so it has to be kept in sync here too -
	# same field on_input_setup() would normally set for a manual drag.
	selector.on_input_setup(0, 0, horz)

	game_state = GameState.DECK_SCROLL
	game_state_mode = 1
	ds_selector = selector
	ds_moving_vert = not horz
	ds_cur_card_stats = null
	ds_start_angle = selector.cur_angle_v if not horz else selector.cur_angle_h
	ds_diff = delta
	ds_elapsed = 0.0

func _process(delta: float) -> void:
	deck_selector_left.update()
	deck_selector_right.update()
	_update_selection_outline()

	if game_state == GameState.DECK_SCROLL and game_state_mode == 1:
		_deck_scroll_process(delta)
	elif game_state == GameState.DRAG_CARD:
		_drag_card_process(delta)

	if launch_battle_delay > 0.0:
		launch_battle_delay -= delta
		if launch_battle_delay <= 0.0:
			launch_battle_delay = 0.0
			Game.player.match_started = true
			SaveSystem.save_player(Game.player)
			get_tree().change_scene_to_file("res://scenes/battle/BattleScene.tscn")

# --------------------------------------------------------- WaitingInput ---

func _enter_waiting_input() -> void:
	game_state = GameState.WAITING_INPUT
	game_state_mode = 0
	wi_panel = null
	wi_selector = null
	_update_play_button()

func _waiting_input_on_click(x: int, y: int) -> void:
	if wi_panel == null:
		var lower_index: int = lower_deck.get_valid_card_index_under_cursor(x, y)
		if lower_index != -1:
			var cstats: Card = lower_deck.card_stats(lower_index)
			_update_card_info(cstats, lower_index + 10)
			_drag_card_set(x, y, false, false, true, null, lower_index)
			return
		elif _hit_test(panel_left, x, y):
			wi_panel = panel_left
			wi_selector = deck_selector_left
			wi_x = x
			wi_y = y
		elif _hit_test(panel_right, x, y):
			wi_panel = panel_right
			wi_selector = deck_selector_right
			wi_x = x
			wi_y = y

	if wi_panel != null:
		var diff_x: int = absi(wi_x - x)
		var diff_y: int = absi(wi_y - y)

		if wi_selector.central_card_hit_test(x, y):
			var cstats: Card = wi_selector.central_card_stats()
			_update_card_info(cstats, 1 if wi_selector == deck_selector_left else 3)
			_drag_card_set(x, y, wi_selector == deck_selector_left, wi_selector == deck_selector_right, false, wi_selector, -1)
		else:
			if diff_x > diff_y:
				if diff_x >= 2:
					_deck_scroll_set(x, y, true, wi_selector)
			else:
				if diff_y >= 2:
					_deck_scroll_set(x, y, false, wi_selector)

# ----------------------------------------------------------- DeckScroll ---

func _deck_scroll_set(x: int, y: int, horz: bool, selector: DeckSelectorWheel) -> void:
	game_state = GameState.DECK_SCROLL
	game_state_mode = 0

	ds_selector = selector
	ds_moving_vert = not horz
	ds_cur_card_stats = null

	selector.on_input_setup(x, y, horz)

func _deck_scroll_process(delta: float) -> void:
	ds_elapsed += delta
	var t: float = clampf(ds_elapsed / DECK_SCROLL_TIME, 0.0, 1.0)
	var val: float = t * (2.0 - t)  # Ease.EaseOutQuadratic

	if ds_moving_vert:
		ds_selector.cur_angle_v = ds_start_angle + val * ds_diff
	else:
		ds_selector.cur_angle_h = ds_start_angle + val * ds_diff

	if t >= 1.0:
		ds_selector.on_input_close()
		_deck_scroll_update_card_info()
		_enter_waiting_input()

func _deck_scroll_update_card_info() -> void:
	var cstats: Card = ds_selector.central_card_stats()
	if cstats != ds_cur_card_stats:
		ds_cur_card_stats = cstats
		if cstats != null:
			_update_card_info(cstats, 1 if ds_selector == deck_selector_left else 2)

# ------------------------------------------------------------- DragCard ---

func _drag_card_set(x: int, y: int, from_left: bool, from_right: bool, from_deck: bool, selector: DeckSelectorWheel, deck_index: int) -> void:
	dc_selector = selector
	dc_from_left = from_left
	dc_from_right = from_right
	dc_from_deck = from_deck
	dc_deck_index = deck_index
	dc_start_x = x
	dc_start_y = y
	dc_lower_deck_hover_index = -1
	dc_lower_deck_hover_incs = [0, 0, 0, 0, 0]
	dc_lower_deck_timer = 0

	var cstats: Card
	var ghost_center: Vector2
	if from_left or from_right:
		cstats = selector.central_card_stats()
		ghost_center = Vector2(selector.central_card_x(), selector.central_card_y())
	else:
		cstats = lower_deck.card_stats(deck_index)
		ghost_center = Vector2(lower_deck.card_x(deck_index), lower_deck.card_y(deck_index))

	drag_ghost.setup(cstats, true, true)
	drag_ghost.visible = true
	drag_ghost.global_position = ghost_center
	dc_card_pos = drag_ghost.position

	game_state = GameState.DRAG_CARD
	game_state_mode = 0

func _drag_card_on_click(x: int, y: int) -> void:
	drag_ghost.position = dc_card_pos + Vector2(x - dc_start_x, y - dc_start_y)

	var res := lower_deck.get_card_index_under_cursor(x, y)
	var index: int = res.index
	var empty_slot: bool = res.was_empty

	if index != -1:
		dc_lower_deck_timer += 1

	if index != -1 and not empty_slot and index != dc_deck_index:
		dc_lower_deck_hover_index = index
		if dc_lower_deck_hover_incs[index] < 6:
			dc_lower_deck_hover_incs[index] += 1
			placeholders[index].position.y -= 2.0
	else:
		dc_lower_deck_hover_index = -1

func _drag_card_on_unclick(x: int, y: int) -> void:
	var res := lower_deck.get_card_index_under_cursor(x, y)
	var index: int = res.index
	var empty_slot: bool = res.was_empty

	if index != -1:
		var selector_to_lower := false

		if dc_lower_deck_timer < 8 and lower_deck.get_unused_index() != -1 and not dc_from_deck:
			# quick drag straight to the deck bar: drop in the next free slot
			index = lower_deck.get_unused_index()
			empty_slot = true
			selector_to_lower = true
		elif index == dc_deck_index:
			pass  # same slot, no-op
		elif dc_deck_index != -1:
			lower_deck.swap_cards(index, dc_deck_index)
		else:
			selector_to_lower = true

		if selector_to_lower:
			var selector_card: Card = dc_selector.remove_current_card()

			if empty_slot:
				lower_deck.add_card(index, selector_card)
			else:
				var deck_card: Card = lower_deck.remove_card(index)
				if deck_card.is_favourite:
					deck_selector_right.add_card(deck_card)
				else:
					deck_selector_left.add_card(deck_card)
				lower_deck.add_card(index, selector_card)

		next_sel = 10 + index
		_drag_card_on_quit_restore()
		_enter_waiting_input()

	elif _hit_test(panel_left, x, y):
		if dc_from_right:
			var cstats: Card = deck_selector_right.remove_current_card()
			deck_selector_left.add_card(cstats)
			next_sel = 1
			_drag_card_on_quit_restore()
			_enter_waiting_input()
		elif dc_from_deck:
			var cstats: Card = lower_deck.remove_card(dc_deck_index)
			deck_selector_left.add_card(cstats)
			next_sel = 1
			_drag_card_on_quit_restore()
			_enter_waiting_input()
		else:
			_drag_card_get_back(1)

	elif _hit_test(panel_right, x, y):
		if dc_from_left:
			var cstats: Card = deck_selector_left.remove_current_card()
			deck_selector_right.add_card(cstats)
			next_sel = 2
			_drag_card_on_quit_restore()
			_enter_waiting_input()
		elif dc_from_deck:
			var cstats: Card = lower_deck.remove_card(dc_deck_index)
			deck_selector_right.add_card(cstats)
			next_sel = 2
			_drag_card_on_quit_restore()
			_enter_waiting_input()
		else:
			_drag_card_get_back(2)

	else:
		var sel: int
		if dc_from_left:
			sel = 1
		elif dc_from_right:
			sel = 2
		else:
			sel = 10 + dc_deck_index
		_drag_card_get_back(sel)

func _drag_card_get_back(sel: int) -> void:
	next_sel = sel
	var tw := create_tween()
	tw.tween_property(drag_ghost, "position", dc_card_pos, GET_BACK_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		_drag_card_on_quit_restore()
		_enter_waiting_input())

func _drag_card_process(_delta: float) -> void:
	for index in 5:
		if index != dc_lower_deck_hover_index and dc_lower_deck_hover_incs[index] != 0:
			placeholders[index].position.y += 2.0
			dc_lower_deck_hover_incs[index] -= 1

func _drag_card_on_quit_restore() -> void:
	drag_ghost.visible = false
	for index in 5:
		if dc_lower_deck_hover_incs[index] != 0:
			placeholders[index].position.y += 2.0 * dc_lower_deck_hover_incs[index]
			dc_lower_deck_hover_incs[index] = 0

# ------------------------------------------------------------- UI sync ---

func _update_play_button() -> void:
	var count := 0
	for card in Game.player.cards:
		if card.is_on_deck:
			count += 1
	button_play.disabled = count != 5

func _update_card_info(cstats: Card, sel: int) -> void:
	next_sel = sel
	var def: CardManager.CardDef = CardManager.defs[cstats.def_id]
	label_info_name.text = def.name
	label_value_pdef.text = str(cstats.physical_defense)
	label_value_mdef.text = str(cstats.magical_defense)
	label_value_offense.text = str(cstats.attack_power)
	label_value_type.text = CardManager.attack_type_to_string(cstats.attack_type)

func _update_selection_outline() -> void:
	if game_state != GameState.WAITING_INPUT:
		selection_outline.visible = false
		return

	var x := -1.0
	var y := -1.0
	var w := -1.0
	var h := -1.0

	if next_sel == 1:
		x = deck_selector_left.central_card_x()
		y = deck_selector_left.central_card_y()
		w = deck_selector_left.card_width
		h = deck_selector_left.card_height
	elif next_sel == 2:
		x = deck_selector_right.central_card_x()
		y = deck_selector_right.central_card_y()
		w = deck_selector_right.card_width
		h = deck_selector_right.card_height
	elif next_sel >= 10:
		var idx: int = next_sel - 10
		x = lower_deck.card_x(idx)
		y = lower_deck.card_y(idx)
		w = lower_deck.card_width(idx)
		h = lower_deck.card_height(idx)

	if x > 0.0:
		selection_outline.visible = true
		selection_outline.set_target_rect(Rect2(x, y, w, h))
		# Belt-and-suspenders on top of z_index=100 (set in _ready): keeping
		# it the last sibling too means correct draw order even if some
		# card's z_index math above ever changes and z_index alone stops
		# being enough.
		move_child(selection_outline, get_child_count() - 1)
	else:
		selection_outline.visible = false

# ------------------------------------------------------------- buttons ---

func _on_play_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	_sync_last_deck()
	busy_indicator.visible = true
	launch_battle_delay = LAUNCH_BATTLE_DELAY
	nav.active = false

func _on_back_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_back_sound.wav")
	# Unlike _on_play_pressed (whose save piggybacks on the launch-delay
	# timer in _process), leaving without playing had no save path at all -
	# the in-progress deck selection was silently lost on every "Back".
	_sync_last_deck()
	SaveSystem.save_player(Game.player)
	get_tree().change_scene_to_file("res://scenes/menu/Opponents.tscn")

func _sync_last_deck() -> void:
	for i in 5:
		var card: Card = lower_deck.card_stats(i)
		Game.player.last_deck[i] = card.unique_id if card != null else -1
