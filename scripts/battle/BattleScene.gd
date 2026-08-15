extends Control
## 1:1-ish port of Scenes/Battle/BattleScene.cs and its gs*.cs state files
## (960x544 design canvas, same coordinates/timings). Method names keep the
## gsXxx_Set/OnInput/Update prefixes from the original files they replace, so
## it's easy to grep prj_psvita/Scenes/Battle/gsXxx.cs and find the matching
## code here. Godot doesn't need PS Vita's manual per-frame state machine or
## its custom Events/Tween system, so the state transitions themselves are
## expressed as a linear chain of `await`s and native Tweens instead.
##
## gsEndLevelUp/EndPlayerPick/EndCPUPick/EndNonePick are ported too (the
## post-battle level-up + card-picking flow), including the AI's own
## persistent card pool (AIManager.prepare_set/top_cards/generic_cards/
## captured_cards) - captures and losses feed back into that pool via
## AIManager.add_captured_card/remove_card, same as the reference.

const SCREEN_W := 960
const SCREEN_H := 544
const CARD_W := 96
const CARD_H := 128
const ASSETS := "res://assets/"
## Pad card-picking: the floating card sits shifted this much off a board
## cell's exact position while still picked up, so it visibly reads as
## "hovering over here" rather than "already placed here".
const PAD_DRAG_OFFSET := Vector2(8, 8)

const COLOR_P0 := Color(0.0, 130.0 / 255.0, 1.0, 0.8)
const COLOR_P1 := Color(225.0 / 255.0, 0.0, 0.0, 0.8)

# Board.cs boardCardsRect: uniform 101x133 pitch for a 96x128 card -> 5px gap.
const BOARD_POS := Vector2(282, 7)
const BOARD_GAP := 5

# Board.cs idleCardsRect - the player's own 5 hand slots (zig-zag stack).
const HAND_POSITIONS := [
	Vector2(826, 68), Vector2(718, 134), Vector2(826, 208),
	Vector2(718, 283), Vector2(826, 348),
]

# BattleScene.cs's small opponent-hand stack (quadPlayer1Cards). Centered
# in the empty gap between the pergamena panel's bottom edge (y=4+282=286)
# and the card-stats panel's top (info_name.position.y=340) -> y=313.
const OPPONENT_STACK_POS := Vector2(70, 305)
const OPPONENT_STACK_STEP := 35.0
const OPPONENT_CARD_SCALE := 0.45

# gsBattle.cs timings.
const BATTLE_RUMBLE_TIME := 0.6
const BATTLE_COUNTDOWN_TIME := 1.5
const BATTLE_RUMBLE_DISTANCE := 16.0
const BATTLE_RUMBLE_RETURN_TIME := 0.2

# New QoL addition (not in the reference, which covers the whole card with
# an opaque card_sel_target.png plaque - hiding its stats entirely): just
# the "Target?" text, pulsing between white and a warm red/orange (reads as
# "about to fight" rather than a neutral UI highlight color).
const TARGET_FLASH_COLOR := Color(1.0, 0.3, 0.1)
const TARGET_FLASH_TIME := 0.6

# Port of gsCardPicking.cs's DrawableAlphaPingPong on quadCardGlow (there
# ping-pongs 0.1-0.7 alpha over a 1.6s cycle) - was rendering fully opaque
# here, hiding the board underneath; alpha range bumped to 0.5-0.8 per
# design direction (still readable as a highlight, never fully solid).
const HOVER_GLOW_MIN_ALPHA := 0.5
const HOVER_GLOW_MAX_ALPHA := 0.8
const HOVER_GLOW_FLASH_TIME := 0.8

# New QoL layout (not in the reference, which sits the message right
# against the button's left edge on the same row - reads as disconnected
# from the button rather than "belonging" to it). The "won all cards"
# message is long, so centering it ON the button's own x while staying on
# one row would either run off the 960-wide screen or force the button
# behind the text; stacking the message above a re-centered button avoids
# both while leaving room for a bigger font. Scoped to just this branch of
# gsEndPlayerPick_Set - every other label_central_msg/button_takeall use
# keeps the reference's original position/alignment.
const END_TAKEALL_MSG_POS := Vector2(40, 175)
const END_TAKEALL_MSG_SIZE := Vector2(880, 65)
const END_TAKEALL_MSG_FONT_SIZE := 30
const END_TAKEALL_BUTTON_POS := Vector2(401, 255)

# Battle countdown number: centered in the vertical space between
# card_border.png's top inner edge (y=9) and the top of the stat text
# (CardView.STAT_AREA_BOTTOM - STAT_FONT_SIZE_HEIGHT = 94). Sized with margin
# to avoid collision with approaching opponent card during rumble.
const BATTLE_VALUE_FONT_SIZE := 46
const BATTLE_VALUE_AREA_TOP := 9.0
const BATTLE_VALUE_AREA_BOTTOM := 94.0

# captureCardProcedure's flip time.
const CAPTURE_FLIP_TIME := 0.4

# gsCoinToss.cs timings.
const COIN_TOSS_SPIN_LIFE := 1.38
const COIN_TOSS_MOVE_LIFE := 0.6

# gsEndStart.cs layout/timings.
const END_PL0_START := Vector2(80, 40)
const END_PL0_WIDTH := 700.0
const END_PL1_START := Vector2(260, 544 - 40 - 128)
const END_PL1_WIDTH := (960.0 - 300.0 - 20.0) - 100.0
const END_PL_OFFSET_X := 4.0
const END_PL_OFFSET_Y := 22.0

const MAX_BLOCKS := 4 * 4 - 10  # 16 cells - 10 cards that must fit

signal target_chosen(card: Card)

var board: Board
var player_hand: Array = []  # size 5, null where the card has been played
var cpu_hand: Array = []     # size 5, null where the card has been played
var active_player: int = 0
var busy := false
var target_mode := false
var target_candidates: Array = []

var dragging := false
var drag_index := -1
var drag_card: Card = null
var drag_ghost: CardView = null

var board_slots: Array = []       # [row][col] -> Button
var board_card_views: Array = []  # [row][col] -> CardView or null
var board_blocks: Array = []      # [row][col] -> TextureRect or null
var board_targets: Array = []     # [row][col] -> Label ("Target?" prompt)
var board_target_tweens: Array = []  # [row][col] -> Tween or null (flash loop)
var board_hover_glow: TextureRect
var board_hover_glow_tween: Tween

var hand_slots: Array = []        # size 5 -> Button

var opponent_stack: Control
var turn_cursor: TextureRect
var name_labels: Array = []
var score_value_labels: Array = []

var info_name: Label
var info_attack_val: Label
var info_type_val: Label
var info_pdef_val: Label
var info_mdef_val: Label

var chain_label: Label
var battle_value_labels: Array = []  # 2 Labels
var vfx_sprites := {}                # Card.AttackType -> AnimatedSprite2D
var coin_sprite: TextureRect
var coin_blue_tex: Texture2D
var coin_red_tex: Texture2D
var rage_quit_banner: TextureRect  # (RAGEQUIT)

var end_panel: Control
var end_bkg: TextureRect
var end_banner: TextureRect

# UIBattleEnd-equivalent widgets (built in _build_battle_end_ui()).
var panel_owned: Control
var owned_label: Label
var panel_info: Control
var end_info_name: Label
var end_info_offense_val: Label
var end_info_type_val: Label
var end_info_pdef_val: Label
var end_info_mdef_val: Label
var label_central_msg: Label
var button_done: Button
var label_coin_reward: RichTextLabel
var button_takeall: Button
var image_arrow: TextureRect
var help_arrow: TextureRect
var busy_spinner: BusySpinner

# End-of-match flow state (gsEndLevelUp/EndPlayerPick/EndCPUPick/EndNonePick).
enum EndFlow { NONE, PLAYER_PICK, CPU_PICK, DRAW }
var end_flow := EndFlow.NONE
var end_result: BattleResult
var end_up_cards: Array = []    # Array[CardView], player's original row (top)
var end_down_cards: Array = []  # Array[CardView], CPU's original row (bottom)
var end_movable: Dictionary = {}  # CardView -> bool: capturable this round

var end_remaining := 1  # capturable cards still up for grabs (5 for a perfect win)
var end_pick_interactive := false
var end_pick_dragging := false
var end_sel_view: CardView = null
var end_pick_from_up := false
var end_drag_start := Vector2.ZERO
var end_card_start_pos := Vector2.ZERO
var end_sel_original_pos := Vector2.ZERO
var end_owned_view: CardView = null  # card the Owned panel is currently pinned to

var end_cpu_pickable: Array = []  # Array[CardView]
var end_cpu_pick_mode := false
var end_cpu_total_picks := 0.0
var end_cpu_cur_pick := 0.0
var end_cpu_sel_view: CardView = null

var sfx_button: AudioStreamPlayer
var sfx_place: AudioStreamPlayer
var sfx_attack_p: AudioStreamPlayer
var sfx_attack_m: AudioStreamPlayer
var sfx_ragequit: AudioStreamPlayer  # (RAGEQUIT)

# --------------------------------------------------------------- controller
var nav: FocusNav
var pad_picking := false  # A on a hand card, waiting for a board cell (or B)
var y_continue_hint: Control
var _current_pick_view: CardView = null  # non-perfect win: the single card currently staged to take

# ai_table.csv's Level for the current opponent, 0-7. Drives how sloppily
# GsCPUTurn plays; 7 (= flawless) is the default so a skirmish with no
# opponent set doesn't accidentally play badly.
var cpu_level: int = 7
var font_stylish: Font = Game.font_stylish
var font_info: Font = Game.font_info

func _ready() -> void:
	board = Board.new()
	_build_ui()
	_setup_nav()
	start_new_game()

## Registers every controller target once and leaves them registered for the
## whole match: each item's enabled_fn reads the live game state (busy,
## target_mode, pad_picking, ...) instead of being added/removed as the
## scene moves between placement/target/end-pick sub-modes, mirroring the
## same items real mouse input already hit-tests dynamically. Only the
## end-of-match "pick a card" items are rebuilt on the fly (_refresh_end_pick_
## nav), since they're keyed to CardView instances that don't exist yet here.
func _setup_nav() -> void:
	nav = FocusNav.new()
	nav.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(nav)

	for i in hand_slots.size():
		nav.add_virtual(&"hand", (func(idx: int) -> Rect2: return hand_slots[idx].get_global_rect()).bind(i), i,
			0, (func(idx: int) -> bool:
				return active_player == 0 and not busy and not target_mode and not pad_picking \
						and player_hand[idx] != null).bind(i))

	for row in Board.NUM_ROWS:
		for col in Board.NUM_COLS:
			var rc := Vector2i(row, col)
			nav.add_virtual(&"board", (func(p: Vector2i) -> Rect2: return board_slots[p.x][p.y].get_global_rect()).bind(rc), rc,
				0, (func(p: Vector2i) -> bool:
					if target_mode:
						var c: Card = board.slots[p.x][p.y]
						return c != null and target_candidates.has(c)
					return pad_picking and board.is_playable(p.x, p.y)).bind(rc))

	nav.add_control(button_done)
	nav.add_control(button_takeall)
	# The single already-chosen card (non-perfect win only - _current_pick_
	# view stays null for a perfect one, where there's no single "the" pick
	# to send back), navigable right alongside the down-row candidates via
	# the ordinary spatial scorer - it sits above them, so up/down already
	# reaches it with no explicit link needed. Registered once here rather
	# than rebuilt in _refresh_end_pick_nav: its rect/enabled are read fresh
	# off _current_pick_view every time already, so there's nothing to redo
	# when that changes.
	nav.add_virtual(&"chosen", func() -> Rect2:
		return _current_pick_view.get_global_rect() if _current_pick_view != null else Rect2(), null,
		0, func() -> bool: return _current_pick_view != null)

	# The cursor moving previews a hand card's stats on its own now; while a
	# card is picked up (pad_picking), it also drags the same card_sel_glow
	# highlight the mouse drag path already uses, following focus onto
	# whichever board cell is currently pointed at instead of the mouse.
	var on_focus_changed := func(item: FocusNav.NavItem) -> void:
		if item.id == &"hand":
			var card: Card = player_hand[item.meta]
			if card != null:
				_show_card_info(card)
		elif item.id == &"board" and pad_picking:
			var rc: Vector2i = item.meta
			_show_hover_glow_at(rc.x, rc.y)
			# Offset, not flush with the cell: sitting exactly on the grid
			# read as already placed rather than still picked up. Placing it
			# for real (gsCardPicking_Release, on the next A) always lands a
			# fresh CardView at the slot's own exact position regardless of
			# this offset, so the actual placement stays pixel-precise.
			drag_ghost.position = _board_cell_pos(rc.x, rc.y) + PAD_DRAG_OFFSET
		elif item.id == &"pick":
			var view: CardView = item.meta
			_show_end_card_info(view.card)
			_update_owned_panel_pos(view)
		elif item.id == &"chosen" and _current_pick_view != null:
			_show_end_card_info(_current_pick_view.card)
			_update_owned_panel_pos(_current_pick_view)
	nav.focus_changed.connect(on_focus_changed)
	nav.activated.connect(_on_nav_activated)
	nav.cancelled.connect(_on_nav_cancelled)

	# button_done ("Continue") only shows for the last stretch of the match
	# (end-of-match flow), toggled by the existing fade_in/fade_out game
	# logic rather than a fixed screen state - hide_in_gamepad's own
	# mode_changed listener would fight fade_in/_fade_out for the same
	# .visible property (fade_in always sets it true, regardless of mode).
	# Wrapping it lets the wrapper's OWN visibility hide it in gamepad mode
	# without ever touching button_done's real .visible, which existing game
	# logic still fully owns.
	var button_done_wrap := Control.new()
	var button_done_parent := button_done.get_parent()
	button_done_parent.add_child(button_done_wrap)
	button_done.reparent(button_done_wrap, true)
	ControllerUI.hide_in_gamepad(button_done_wrap)

	nav.alt2_activated.connect(func(_item: FocusNav.NavItem) -> void:
		if button_done.visible and not button_done.disabled:
			button_done.pressed.emit())
	# _process (below) mirrors button_done's own visibility onto the hint
	# every frame - it should only show during the actual end-of-match window,
	# not for the whole match the way Menu below does. x=803 matches Options'
	# X (Title Screen) - the general right-alignment reference every screen's
	# right-side hint now shares.
	const CONTINUE_X := 803.0
	y_continue_hint = ControllerUI.make_button_hint(&"Y", StringTable.get_string(StringTable.ID_DONE), Vector2(CONTINUE_X, ControllerUI.PROMPT_BAR_Y), Vector2(button_done.size.x, ControllerUI.HINT_ROW_HEIGHT))
	add_child(y_continue_hint)
	# No A entry - the cursor moving already previews, and pressing A on a
	# hand/board item (including the end-of-match pick) is self-explanatory
	# once you're pointing at it. No Start/Pause entry either - there's no
	# mouse-mode equivalent, so a pad-only pause was a dead end with nothing
	# consistent to pause into.

func _on_nav_activated(item: FocusNav.NavItem) -> void:
	match item.id:
		&"hand":
			if pad_picking:
				return
			var idx: int = item.meta
			var card: Card = player_hand[idx]
			if card == null:
				return
			gsCardPicking_Set(idx, card)
			pad_picking = true
			# Jump straight to a free cell instead of waiting for the next
			# d-pad move - the point is to immediately show "this card is
			# picked up, here's a valid spot" rather than leave the ghost
			# sitting on the hand slot with nothing on the board changed yet.
			# Rightmost playable column first (the hand sits on the right
			# side of the board), then whichever row in that column lands
			# closest to the hand slot's own height.
			var hand_y: float = hand_slots[idx].position.y
			for col in range(Board.NUM_COLS - 1, -1, -1):
				var best_row := -1
				var best_dist := INF
				for row in Board.NUM_ROWS:
					if board.is_playable(row, col):
						var dist := absf(_board_cell_pos(row, col).y - hand_y)
						if dist < best_dist:
							best_dist = dist
							best_row = row
				if best_row != -1:
					nav.focus_by_meta(Vector2i(best_row, col))
					return
		&"board":
			var rc: Vector2i = item.meta
			if target_mode:
				_on_slot_pressed(rc.x, rc.y)
			elif pad_picking:
				pad_picking = false
				gsCardPicking_Release(_board_cell_pos(rc.x, rc.y) + Vector2(CARD_W, CARD_H) / 2.0)
		&"pick":
			var view: CardView = item.meta
			if end_result == BattleResult.PLAYER_PERFECT:
				_show_end_card_info(view.card)
				_update_owned_panel_pos(view)
			else:
				# Only one card is ever "the" pick for a non-perfect win -
				# choosing a different one swaps it out instead of adding a
				# second (which used to leave more than one card taken and
				# end_remaining wrong, so Y/Done never agreed with what was
				# actually about to be collected).
				if _current_pick_view != null and _current_pick_view != view:
					await _end_uncommit_pick(_current_pick_view)
				await _end_commit_pick(view)
				_current_pick_view = view
				# _end_uncommit_pick's _fade_out and _end_commit_pick's
				# _fade_in each start their own independent tween rather
				# than awaiting one another, so back-to-back (a swap) can
				# race: fade_out's tween_callback setting .visible = false
				# can still be pending when fade_in already set it true, and
				# land after, silently leaving Done/Y invisible - and so
				# non-functional - despite a card genuinely being picked.
				# Stated explicitly here beats trusting either tween's timing.
				button_done.visible = true
				_refresh_end_pick_nav()
				# The cursor follows the card up to &"chosen" instead of
				# staying on the down row - simpler to reason about than
				# jumping to "whatever's next down there": to pick something
				# else, move down (the ordinary spatial scorer already
				# reaches a &"pick" item from &"chosen" with no explicit
				# link needed) and the swap logic above takes it from there.
				_focus_chosen()
		&"chosen":
			# A on the already-chosen card sends it back down - the reverse
			# of &"pick" above, reachable directly instead of only as a side
			# effect of picking something else.
			if _current_pick_view != null:
				var old_view := _current_pick_view
				_current_pick_view = null
				await _end_uncommit_pick(old_view)
				_refresh_end_pick_nav()
				_focus_next_pick_or_done()
		_:
			(item.control as Button).pressed.emit()

func _on_nav_cancelled() -> void:
	if pad_picking:
		# gsCardPicking_Release already restores the card and stops the hover
		# glow (both shared with the mouse drop-outside-board path) - only
		# the refocus back onto the hand slot it came from is pad-specific.
		var idx := drag_index
		pad_picking = false
		gsCardPicking_Release(Vector2(-9999, -9999))
		nav.focus_by_meta(idx)

## Rebuilds the "pick a captured card" targets: called once when the pick
## phase opens and again after every pad-driven pick, since end_down_cards
## shrinks by one CardView each time (mirrors Collection.gd's remove_by_id +
## re-add pattern for its own dynamically-rebuilt card grid).
func _refresh_end_pick_nav() -> void:
	nav.remove_by_id(&"pick")
	for view in end_down_cards:
		if end_movable.get(view, false):
			nav.add_virtual(&"pick", (func(v: CardView) -> Rect2: return v.get_global_rect()).bind(view), view)

## nav.focus_first() picks the first ENABLED item in registration order -
## button_done/button_takeall were both registered before any &"pick" item
## ever existed, so once button_done fades in after the first successful
## pick, focus_first() would land there instead of the next pickable card,
## reading as "A stopped doing anything" (it's still landing on a pick item,
## just not the one the player is now looking at - Y/Continue is what
## actually presses from there, easy to trigger by mistake or just look
## broken). Prefer a &"pick" item explicitly; only fall back once none are
## left, which is exactly when landing on Done/Take All is the right call.
func _focus_next_pick_or_done() -> void:
	for item in nav.items:
		if item.id == &"pick" and item.enabled():
			nav.set_focus(item)
			return
	nav.focus_first()

## The single &"chosen" item is always registered (see _setup_nav) - this
## just finds it, for the one caller that wants the cursor to follow a card
## up onto it right after picking.
func _focus_chosen() -> void:
	for item in nav.items:
		if item.id == &"chosen":
			nav.set_focus(item)
			return

## Port of BattleScene.cs's generateCards(): the 5 Game.player.cards flagged
## isOnDeck by DeckSelect, cloned (clone_stats()) same as the reference's
## cards[i].Setup(cstat, 0) copying stats into a separate battle Card -
## Board.capture() mutates card.owner in place on capture, and that must
## not corrupt the persistent Game.player.cards entry.
## Falls back to a random deck if Game.player has no on-deck cards (e.g.
## BattleScene opened standalone for testing, bypassing the StartMenu ->
## Opponents -> DeckSelect flow that normally populates it - not reference
## behavior, just keeps this scene testable in isolation).
func _get_player_deck() -> Array:
	if Game.player != null:
		var deck := []
		for card in Game.player.cards:
			if card.is_on_deck:
				deck.append(card.clone_stats())
		if deck.size() == 5:
			return deck
	return CardManager.generate_playable_deck(5)

## Port of AIManager.cs's AIPrepareSet(): the selected opponent's 5-card
## battle hand, drawn from its persistent captured/top/generic pools
## (AIManager.ensure_dynamic_data lazily generates the starting set the
## first time this AI is used in the current save slot).
func _get_cpu_deck() -> Array:
	if Game.opponent_index >= 0:
		var ai: AIManager.AIData = AIManager.get_ai(Game.opponent_index)
		# Cached here rather than re-read every turn - this is the one place
		# the AIData is already in hand. The free-skirmish fallback below has
		# no opponent, so it keeps cpu_level's max default and plays sharp.
		cpu_level = ai.level
		AIManager.ensure_dynamic_data(ai)
		return AIManager.prepare_set(ai)
	return CardManager.generate_playable_deck(5)

func start_new_game() -> void:
	end_panel.visible = false
	end_bkg.position.y = -SCREEN_H
	board.reset()
	board.place_random_blocks(MAX_BLOCKS)
	_refresh_board_blocks()
	for row in board_card_views:
		for i in row.size():
			row[i] = null
	_refresh_board_visuals()

	player_hand = _get_player_deck()
	cpu_hand = _get_cpu_deck()
	for c in cpu_hand:
		c.owner = 1
		c.original_owner = 1

	busy = false
	_show_card_info(null)
	_refresh_hands()
	_refresh_scores()

	# Port of BattleScene.cs's MusicPlayWithFade call at the same spot -
	# crossfades from whatever was playing (menu music) into battle1.mp3,
	# instead of leaving the menu track running underneath it.
	Game.crossfade_music(ASSETS + "music/battle1.mp3", 0.85, -8.0)
	gsCoinToss_Set()

# ---------------------------------------------------------------- UI build

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := TextureRect.new()
	bg.texture = load(ASSETS + "battle/battle_screen.png")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.position = Vector2.ZERO
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	add_child(bg)

	var pergamena := TextureRect.new()
	pergamena.texture = load(ASSETS + "battle/battle_pergamena.png")
	pergamena.stretch_mode = TextureRect.STRETCH_SCALE
	pergamena.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pergamena.position = Vector2(0, 4)
	pergamena.size = Vector2(280, 282)
	add_child(pergamena)

	var marmo := TextureRect.new()
	marmo.texture = load(ASSETS + "battle/battle_marmo.png")
	marmo.stretch_mode = TextureRect.STRETCH_SCALE
	marmo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	marmo.position = Vector2(14, 282)
	marmo.size = Vector2(248, 256)
	add_child(marmo)

	turn_cursor = TextureRect.new()
	turn_cursor.texture = load(ASSETS + "battle/battle_cursor.png")
	turn_cursor.stretch_mode = TextureRect.STRETCH_SCALE
	turn_cursor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	turn_cursor.position = Vector2(12, 23)
	turn_cursor.size = Vector2(48, 48)
	turn_cursor.visible = false
	add_child(turn_cursor)

	_build_player_panel(0, 23, COLOR_P0)
	_build_player_panel(1, 125, COLOR_P1)
	_build_card_info_panel()
	_build_board()
	_build_hand()
	_build_opponent_stack()
	_build_battle_overlay()
	_build_end_panel()
	_build_audio()

func _build_player_panel(idx: int, y: int, color: Color) -> void:
	var name_label := Label.new()
	name_label.position = Vector2(60, y)
	name_label.add_theme_font_override("font", font_stylish)
	name_label.add_theme_font_size_override("font_size", 36)
	name_label.add_theme_color_override("font_color", color)
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_label.text = "You" if idx == 0 else "CPU"
	add_child(name_label)
	name_labels.append(name_label)

	var score_caption := Label.new()
	score_caption.position = Vector2(82, y + 51)
	score_caption.add_theme_font_override("font", font_stylish)
	score_caption.add_theme_font_size_override("font_size", 36)
	score_caption.add_theme_color_override("font_color", color)
	score_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	score_caption.add_theme_constant_override("outline_size", 3)
	score_caption.text = "Score"
	add_child(score_caption)

	var score_value := Label.new()
	score_value.position = Vector2(184, y + 51)
	score_value.add_theme_font_override("font", font_stylish)
	score_value.add_theme_font_size_override("font_size", 36)
	score_value.add_theme_color_override("font_color", color)
	score_value.add_theme_color_override("font_outline_color", Color.BLACK)
	score_value.add_theme_constant_override("outline_size", 3)
	score_value.text = "0"
	add_child(score_value)
	score_value_labels.append(score_value)

func _build_card_info_panel() -> void:
	var black := Color(0, 0, 0)

	info_name = Label.new()
	info_name.position = Vector2(14, 340)
	info_name.size = Vector2(248, 24)
	info_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_name.add_theme_font_override("font", font_stylish)
	info_name.add_theme_font_size_override("font_size", 24)
	info_name.add_theme_color_override("font_color", black)
	add_child(info_name)

	var rows := [
		["Attack", 376], ["Type", 410], ["P.Def", 444], ["M.Def", 478],
	]
	var value_labels := []
	for row in rows:
		var caption := Label.new()
		caption.position = Vector2(32, row[1])
		caption.add_theme_font_override("font", font_stylish)
		caption.add_theme_font_size_override("font_size", 24)
		caption.add_theme_color_override("font_color", black)
		caption.text = row[0]
		add_child(caption)

		var value := Label.new()
		value.position = Vector2(200, row[1])
		value.add_theme_font_override("font", font_stylish)
		value.add_theme_font_size_override("font_size", 24)
		value.add_theme_color_override("font_color", black)
		add_child(value)
		value_labels.append(value)

	info_attack_val = value_labels[0]
	info_type_val = value_labels[1]
	info_pdef_val = value_labels[2]
	info_mdef_val = value_labels[3]

func _board_cell_pos(row: int, col: int) -> Vector2:
	return BOARD_POS + Vector2(col * (CARD_W + BOARD_GAP), row * (CARD_H + BOARD_GAP))

func _build_board() -> void:
	for row in Board.NUM_ROWS:
		var slot_row := []
		var view_row := []
		var block_row := []
		var target_row := []
		var target_tween_row := []
		for col in Board.NUM_COLS:
			var pos := _board_cell_pos(row, col)

			var slot := Button.new()
			slot.position = pos
			slot.size = Vector2(CARD_W, CARD_H)
			slot.flat = true
			slot.clip_contents = false
			slot.pressed.connect(_on_slot_pressed.bind(row, col))
			add_child(slot)
			slot_row.append(slot)
			view_row.append(null)

			var block := TextureRect.new()
			block.texture = load(ASSETS + "battle/battle_block.png")
			block.stretch_mode = TextureRect.STRETCH_SCALE
			block.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			block.position = pos
			block.size = Vector2(CARD_W, CARD_H)
			block.visible = false
			block.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(block)
			block_row.append(block)

			var target := Label.new()
			target.text = "Target?"
			target.add_theme_font_override("font", font_stylish)
			target.add_theme_font_size_override("font_size", 22)
			target.add_theme_color_override("font_color", Color.WHITE)
			target.add_theme_color_override("font_outline_color", Color.BLACK)
			target.add_theme_constant_override("outline_size", 4)
			target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			target.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			target.position = pos
			target.size = Vector2(CARD_W, CARD_H)
			target.visible = false
			target.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(target)
			target_row.append(target)
			target_tween_row.append(null)

		board_slots.append(slot_row)
		board_card_views.append(view_row)
		board_blocks.append(block_row)
		board_targets.append(target_row)
		board_target_tweens.append(target_tween_row)

	board_hover_glow = TextureRect.new()
	board_hover_glow.texture = load(ASSETS + "cards/card_sel_glow.png")
	board_hover_glow.stretch_mode = TextureRect.STRETCH_SCALE
	board_hover_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	board_hover_glow.size = Vector2(CARD_W, CARD_H)
	board_hover_glow.visible = false
	board_hover_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board_hover_glow)

func _build_hand() -> void:
	for i in HAND_POSITIONS.size():
		var slot := Button.new()
		slot.position = HAND_POSITIONS[i]
		slot.size = Vector2(CARD_W, CARD_H)
		slot.flat = true
		slot.button_down.connect(_on_hand_button_down.bind(i))
		add_child(slot)
		hand_slots.append(slot)

func _build_opponent_stack() -> void:
	opponent_stack = Control.new()
	add_child(opponent_stack)

func _build_battle_overlay() -> void:
	# combo text (textCombo) - sized and outlined to read instantly against
	# the card-flip animations it now plays alongside, not just be legible:
	# a real outline (not a 1px shadow) holds contrast against any
	# background, and font size roughly doubles the level-up text's.
	chain_label = Label.new()
	chain_label.add_theme_font_override("font", font_stylish)
	chain_label.add_theme_font_size_override("font_size", 48)
	chain_label.add_theme_color_override("font_color", Color(1, 0.85, 0.1))
	chain_label.add_theme_color_override("font_outline_color", Color.BLACK)
	chain_label.add_theme_constant_override("outline_size", 5)
	chain_label.visible = false
	chain_label.z_index = 70  # stays above the cards mid-capture-flip
	add_child(chain_label)

	# battle numbers (textCardBattleValues), styled like CardView's stat
	# text (ochre yellow + black outline) so they're readable over the cards.
	for i in 2:
		var value_label := Label.new()
		value_label.add_theme_font_override("font", font_stylish)
		value_label.add_theme_font_size_override("font_size", BATTLE_VALUE_FONT_SIZE)
		value_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.1))
		value_label.add_theme_color_override("font_outline_color", Color.BLACK)
		value_label.add_theme_constant_override("outline_size", 3)
		value_label.visible = false
		add_child(value_label)
		battle_value_labels.append(value_label)

	# battle VFX (animAssault/animPhysical/animMagical/animFlexible)
	vfx_sprites[Card.AttackType.ASSAULT] = _make_vfx(ASSETS + "battle/effect_assault.png")
	vfx_sprites[Card.AttackType.PHYSICAL] = _make_vfx(ASSETS + "battle/effect_physical.png")
	vfx_sprites[Card.AttackType.MAGICAL] = _make_vfx(ASSETS + "battle/effect_magical.png")
	vfx_sprites[Card.AttackType.FLEXIBLE] = _make_vfx(ASSETS + "battle/effect_flexible.png")

	# coin toss
	coin_blue_tex = load(ASSETS + "battle/battle_coin_blue.png")
	coin_red_tex = load(ASSETS + "battle/battle_coin_red.png")
	coin_sprite = TextureRect.new()
	coin_sprite.texture = coin_blue_tex
	coin_sprite.size = Vector2(96, 96)
	coin_sprite.pivot_offset = Vector2(48, 48)
	coin_sprite.position = Vector2((SCREEN_W - 96) / 2.0, (SCREEN_H - 96) / 2.0)
	coin_sprite.visible = false
	add_child(coin_sprite)

	# (RAGEQUIT)
	rage_quit_banner = TextureRect.new()
	rage_quit_banner.texture = load(ASSETS + "battle/battle_ragequit.png")
	rage_quit_banner.stretch_mode = TextureRect.STRETCH_SCALE
	rage_quit_banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rage_quit_banner.size = Vector2(rage_quit_banner.texture.get_width(), rage_quit_banner.texture.get_height())
	rage_quit_banner.visible = false
	rage_quit_banner.z_index = 50
	add_child(rage_quit_banner)

func _make_vfx(path: String) -> AnimatedSprite2D:
	var tex: Texture2D = load(path)
	var cols := 5
	var rows := 6
	var frame_w := tex.get_width() / cols
	var frame_h := tex.get_height() / rows

	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("play")
	frames.set_animation_speed("play", float(cols * rows) / BATTLE_RUMBLE_TIME)
	frames.set_animation_loop("play", false)
	for row in rows:
		for col in cols:
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h)
			frames.add_frame("play", atlas)

	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.animation = "play"
	sprite.centered = true
	sprite.scale = Vector2(2, 2)
	sprite.visible = false

	# flagSetSrcColorBlend() in the original: these sprite sheets have no
	# alpha channel (Rgb565), black areas are meant to add nothing rather
	# than paint opaque black squares over the cards.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sprite.material = mat

	add_child(sprite)
	return sprite

func _build_end_panel() -> void:
	end_panel = Control.new()
	end_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_panel.visible = false
	add_child(end_panel)

	end_bkg = TextureRect.new()
	end_bkg.texture = load(ASSETS + "common_bkg_clean.png")
	end_bkg.stretch_mode = TextureRect.STRETCH_SCALE
	end_bkg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	end_bkg.size = Vector2(SCREEN_W, SCREEN_H)
	end_bkg.position = Vector2(0, -SCREEN_H)
	end_panel.add_child(end_bkg)

	end_banner = TextureRect.new()
	end_banner.visible = false
	end_panel.add_child(end_banner)

	_build_battle_end_ui()

## Port of UIBattleEnd.composer.cs (default/horizontal orientation). All of
## this sits on top of end_panel (which already has end_bkg behind it), and
## is driven by gsEndLevelUp/EndPlayerPick/EndCPUPick/EndNonePick below.
func _build_battle_end_ui() -> void:
	# As wide as the card it's pinned under (CARD_W) - _update_owned_panel_pos
	# centers it exactly on the card using this same width - and tall enough
	# for a readable font on a phone screen instead of the original's tiny
	# single-purpose tooltip size.
	panel_owned = Control.new()
	panel_owned.size = Vector2(CARD_W, 64)
	panel_owned.clip_contents = true
	panel_owned.visible = false
	# z_index 60 matches the "always above a card" tier used elsewhere in this
	# file (e.g. the floating chain-count label) - a selected/dragged card
	# gets z_index 50 (_end_player_pick_click) to float above other cards,
	# which was also outranking this panel and panel_info whenever the drag
	# passed over them, hiding the stats entirely.
	panel_owned.z_index = 60
	end_panel.add_child(panel_owned)

	var owned_bkg := TextureRect.new()
	owned_bkg.texture = load(ASSETS + "common_transp_box_a.png")
	owned_bkg.stretch_mode = TextureRect.STRETCH_SCALE
	owned_bkg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	owned_bkg.size = panel_owned.size
	panel_owned.add_child(owned_bkg)

	owned_label = _make_end_label(Vector2(0, 0), panel_owned.size, 22)
	owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	owned_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel_owned.add_child(owned_label)

	panel_info = Control.new()
	panel_info.position = Vector2(8, 311)
	panel_info.size = Vector2(228, 224)
	panel_info.clip_contents = true
	panel_info.visible = false
	panel_info.z_index = 60  # see panel_owned's comment above
	end_panel.add_child(panel_info)

	var info_bkg := TextureRect.new()
	info_bkg.texture = load(ASSETS + "common_transp_box_a.png")
	info_bkg.stretch_mode = TextureRect.STRETCH_SCALE
	info_bkg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	info_bkg.size = Vector2(228, 224)
	panel_info.add_child(info_bkg)

	end_info_name = _make_end_label(Vector2(9, 8), Vector2(210, 41), 25)
	end_info_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel_info.add_child(end_info_name)

	var info_offense_lbl := _make_end_label(Vector2(9, 48), Vector2(174, 41), 25)
	info_offense_lbl.text = StringTable.get_string(StringTable.ID_CARD_ATTACK)
	panel_info.add_child(info_offense_lbl)
	UIButtonStyle.fit_button_text(info_offense_lbl)
	end_info_offense_val = _make_end_label(Vector2(111, 48), Vector2(108, 41), 25)
	end_info_offense_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel_info.add_child(end_info_offense_val)

	var info_type_lbl := _make_end_label(Vector2(9, 89), Vector2(174, 41), 25)
	info_type_lbl.text = StringTable.get_string(StringTable.ID_CARD_TYPE)
	panel_info.add_child(info_type_lbl)
	UIButtonStyle.fit_button_text(info_type_lbl)
	end_info_type_val = _make_end_label(Vector2(111, 89), Vector2(108, 41), 25)
	end_info_type_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel_info.add_child(end_info_type_val)

	var info_pdef_lbl := _make_end_label(Vector2(9, 130), Vector2(169, 41), 25)
	info_pdef_lbl.text = StringTable.get_string(StringTable.ID_CARD_PHYSICAL_DEFENSE)
	panel_info.add_child(info_pdef_lbl)
	UIButtonStyle.fit_button_text(info_pdef_lbl)
	end_info_pdef_val = _make_end_label(Vector2(111, 130), Vector2(108, 41), 25)
	end_info_pdef_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel_info.add_child(end_info_pdef_val)

	var info_mdef_lbl := _make_end_label(Vector2(9, 171), Vector2(169, 41), 25)
	info_mdef_lbl.text = StringTable.get_string(StringTable.ID_CARD_MAGICAL_DEFENSE)
	panel_info.add_child(info_mdef_lbl)
	UIButtonStyle.fit_button_text(info_mdef_lbl)
	end_info_mdef_val = _make_end_label(Vector2(111, 171), Vector2(108, 41), 25)
	end_info_mdef_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel_info.add_child(end_info_mdef_val)

	label_central_msg = _make_end_label(Vector2(46, 233), Vector2(742, 74), 25)
	label_central_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_central_msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	label_central_msg.visible = false
	end_panel.add_child(label_central_msg)

	# Coin payout readout, filled in by gsEndPlayerPick_Set on a win. A
	# RichTextLabel with an inline [img] rather than a Label + TextureRect
	# pair - same trick CardView uses for the shop price tags, and it needs
	# no StringTable entry since the whole thing is a number and an icon.
	# Left column, in the gap between panel_owned (y174-238 when pinned to a
	# top-row card) and panel_info (y311-535) - x=8 matches panel_info's own
	# left edge, text itself centered within that box.
	label_coin_reward = RichTextLabel.new()
	label_coin_reward.bbcode_enabled = true
	label_coin_reward.scroll_active = false
	# y centers this box on label_central_msg's own vertical center (233 +
	# 74/2 = 270), so the two read as sitting on the same row.
	label_coin_reward.position = Vector2(8, 247)
	label_coin_reward.size = Vector2(228, 46)
	label_coin_reward.add_theme_font_override("normal_font", font_stylish)
	label_coin_reward.add_theme_font_size_override("normal_font_size", 36)
	label_coin_reward.add_theme_color_override("default_color", Color(1, 0.85, 0.1))
	label_coin_reward.add_theme_constant_override("outline_size", 4)
	label_coin_reward.add_theme_color_override("font_outline_color", Color.BLACK)
	label_coin_reward.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label_coin_reward.visible = false
	end_panel.add_child(label_coin_reward)

	button_done = _make_end_button(StringTable.get_string(StringTable.ID_DONE), Vector2(790, 463), Vector2(122, 56))
	button_done.visible = false
	button_done.pressed.connect(_on_end_done_pressed)
	end_panel.add_child(button_done)

	button_takeall = _make_end_button(StringTable.get_string(StringTable.ID_TAKE_ALL), Vector2(795, 242), Vector2(158, 56))
	button_takeall.visible = false
	button_takeall.pressed.connect(_on_end_takeall_pressed)
	end_panel.add_child(button_takeall)

	image_arrow = TextureRect.new()
	image_arrow.texture = load(ASSETS + "cursor.png")
	image_arrow.stretch_mode = TextureRect.STRETCH_SCALE
	image_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image_arrow.size = Vector2(64, 64)
	image_arrow.visible = false
	image_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.add_child(image_arrow)

	help_arrow = TextureRect.new()
	help_arrow.texture = load(ASSETS + "help_arrow.png")
	help_arrow.stretch_mode = TextureRect.STRETCH_SCALE
	help_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	help_arrow.position = Vector2(574, 98)
	help_arrow.size = Vector2(159, 317)
	help_arrow.visible = false
	help_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.add_child(help_arrow)

	busy_spinner = BusySpinner.new()
	busy_spinner.position = Vector2(912, 496)
	busy_spinner.size = Vector2(48, 48)
	busy_spinner.pivot_offset = Vector2(24, 24)
	busy_spinner.visible = false
	end_panel.add_child(busy_spinner)

func _make_end_label(pos: Vector2, label_size: Vector2, font_size: int) -> Label:
	var label := FixedSizeLabel.new()
	label.position = pos
	label.size = label_size
	label.add_theme_font_override("font", font_stylish)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.BLACK)
	label.add_theme_color_override("font_shadow_color", Color(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0, 0.5))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

func _make_end_button(text: String, pos: Vector2, btn_size: Vector2) -> Button:
	var btn := FixedSizeButton.new()
	UIButtonStyle.apply(btn)
	btn.text = text
	btn.position = pos
	btn.size = btn_size
	btn.add_theme_font_override("font", font_stylish)
	btn.add_theme_font_size_override("font_size", 36)
	btn.add_theme_color_override("font_color", Color.BLACK)
	btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	btn.add_theme_constant_override("shadow_offset_x", 2)
	btn.add_theme_constant_override("shadow_offset_y", 1)
	UIButtonStyle.fit_button_text(btn)
	return btn

func _build_audio() -> void:
	sfx_button = _make_sfx("sfx/button_sound.wav")
	sfx_place = _make_sfx("sfx/place_card.wav")
	sfx_attack_p = _make_sfx("sfx/attack_p.wav")
	sfx_attack_m = _make_sfx("sfx/attack_m.wav")
	sfx_ragequit = _make_sfx("sfx/ragequit_sfx.wav")

func _make_sfx(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = load(ASSETS + path)
	add_child(p)
	return p

# --------------------------------------------------------------- rendering

func _refresh_hands() -> void:
	for i in hand_slots.size():
		var slot: Button = hand_slots[i]
		for c in slot.get_children():
			c.queue_free()

		var card: Card = player_hand[i]
		slot.disabled = card == null
		slot.visible = card != null
		if card == null:
			continue

		var view := CardView.new()
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.setup(card)
		slot.add_child(view)

	for c in opponent_stack.get_children():
		c.queue_free()
	var idle_count := 0
	for c in cpu_hand:
		if c != null:
			idle_count += 1
	var back_tex: Texture2D = load(ASSETS + "cards/card_back.png")
	var back_size := Vector2(CARD_W, CARD_H) * OPPONENT_CARD_SCALE
	for i in idle_count:
		var back := TextureRect.new()
		back.texture = back_tex
		back.stretch_mode = TextureRect.STRETCH_SCALE
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# quadPlayer1Cards uses flagSetTransformPivotAtCenter() in the
		# original, i.e. X/Y is the card's CENTER, not its top-left corner.
		back.position = OPPONENT_STACK_POS + Vector2(i * OPPONENT_STACK_STEP, 0) - back_size / 2.0
		back.size = back_size
		opponent_stack.add_child(back)

func _refresh_board_blocks() -> void:
	for row in Board.NUM_ROWS:
		for col in Board.NUM_COLS:
			board_blocks[row][col].visible = board.is_blocked(row, col)

func _refresh_board_visuals() -> void:
	for row in Board.NUM_ROWS:
		for col in Board.NUM_COLS:
			_update_slot_visual(row, col)

func _update_slot_visual(row: int, col: int) -> void:
	var existing: CardView = board_card_views[row][col]
	if existing != null:
		existing.queue_free()
		board_card_views[row][col] = null

	var card: Card = board.slots[row][col]
	if card == null:
		return

	var view := CardView.new()
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.setup(card)
	board_slots[row][col].add_child(view)
	board_card_views[row][col] = view

func _refresh_scores() -> void:
	score_value_labels[0].text = str(board.count_cards(0))
	score_value_labels[1].text = str(board.count_cards(1))

func _highlight_targets(cards: Array, on: bool) -> void:
	for c in cards:
		var label: Label = board_targets[c.row][c.col]
		var old_tween: Tween = board_target_tweens[c.row][c.col]
		if is_instance_valid(old_tween):
			old_tween.kill()
			board_target_tweens[c.row][c.col] = null

		label.visible = on
		if on:
			label.modulate = Color.WHITE
			var tw := create_tween()
			tw.set_loops()
			tw.tween_property(label, "modulate", TARGET_FLASH_COLOR, TARGET_FLASH_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(label, "modulate", Color.WHITE, TARGET_FLASH_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			board_target_tweens[c.row][c.col] = tw

func _show_card_info(card: Card) -> void:
	if card == null:
		info_name.text = "Card stats"
		info_attack_val.text = ""
		info_type_val.text = ""
		info_pdef_val.text = ""
		info_mdef_val.text = ""
		return
	var def: CardManager.CardDef = CardManager.defs[card.def_id]
	info_name.text = def.name
	info_attack_val.text = str(card.attack_power)
	info_type_val.text = CardManager.attack_type_to_letter(card.attack_type)
	info_pdef_val.text = str(card.physical_defense)
	info_mdef_val.text = str(card.magical_defense)

# --------------------------------------------------------------- coin toss

func gsCoinToss_Set() -> void:
	var player0_wins := randi() % 2 == 0

	coin_sprite.visible = true
	coin_sprite.modulate.a = 1.0
	coin_sprite.scale = Vector2(1, 1)
	coin_sprite.position = Vector2((SCREEN_W - 96) / 2.0, (SCREEN_H - 96) / 2.0)
	coin_sprite.texture = coin_blue_tex

	var elapsed := 0.0
	var flip_index := 0
	while elapsed < COIN_TOSS_SPIN_LIFE:
		var dur: float = lerp(0.09, 0.32, elapsed / COIN_TOSS_SPIN_LIFE)
		var tw := create_tween()
		tw.tween_property(coin_sprite, "scale:x", 0.0, dur * 0.5)
		tw.tween_callback(func():
			coin_sprite.texture = coin_red_tex if coin_sprite.texture == coin_blue_tex else coin_blue_tex)
		tw.tween_property(coin_sprite, "scale:x", 1.0, dur * 0.5)
		await tw.finished
		elapsed += dur
		flip_index += 1

	coin_sprite.texture = coin_blue_tex if player0_wins else coin_red_tex
	coin_sprite.scale = Vector2(1, 1)

	var target: Vector2 = HAND_POSITIONS[1] if player0_wins else OPPONENT_STACK_POS
	var tw2 := create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(coin_sprite, "position", target, COIN_TOSS_MOVE_LIFE) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw2.tween_property(coin_sprite, "modulate:a", 0.0, COIN_TOSS_MOVE_LIFE * 0.2) \
		.set_delay(COIN_TOSS_MOVE_LIFE * 0.8)
	await tw2.finished
	coin_sprite.visible = false

	if Game.rage_quit_mode:
		await _play_rage_quit_intro()

	active_player = 0 if player0_wins else 1
	if active_player == 0:
		gsPlayerTurn_Set()
	else:
		gsCPUTurn_Set()

# (RAGEQUIT) Banner slides in from the left, holds, slides out to the
# right, while a sting plays and the music crossfades to the special
# ragequit_battle.mp3 track - same beats as gsCoinToss.cs's Update, just
# awaited sequentially instead of scheduled via delayed events.
func _play_rage_quit_intro() -> void:
	const MOV_TIME := 0.7
	const STAY_TIME := 2.1

	rage_quit_banner.position = Vector2(-rage_quit_banner.size.x, (SCREEN_H - rage_quit_banner.size.y) / 2.0)
	rage_quit_banner.visible = true

	sfx_ragequit.play()
	Game.crossfade_music(ASSETS + "music/ragequit_battle.mp3", 0.85, -8.0)

	var tw := create_tween()
	tw.tween_property(rage_quit_banner, "position:x", (SCREEN_W - rage_quit_banner.size.x) / 2.0, MOV_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished

	await get_tree().create_timer(STAY_TIME).timeout

	var tw2 := create_tween()
	tw2.tween_property(rage_quit_banner, "position:x", float(SCREEN_W), MOV_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw2.finished

	rage_quit_banner.visible = false

# --------------------------------------------------------------- player turn

func gsPlayerTurn_Set() -> void:
	active_player = 0
	busy = false
	turn_cursor.visible = true
	var tw := create_tween()
	tw.tween_property(turn_cursor, "position:y", 23.0, 0.35) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_focus_first_hand_card()

## Called at the start of every player turn so the pad cursor is always
## sitting on something real the moment control hands back - without this,
## nav.current stays null until the player's first stick nudge (FocusNav
## only calls focus_first() lazily, on the first move()), so the hand was
## invisible for however long it took the player to notice nothing was
## highlighted yet.
func _focus_first_hand_card() -> void:
	if nav == null:
		return
	for i in player_hand.size():
		if player_hand[i] != null:
			nav.focus_by_meta(i)
			return

func _on_hand_button_down(index: int) -> void:
	if busy or active_player != 0 or target_mode or dragging:
		return
	var card: Card = player_hand[index]
	if card == null:
		return
	gsCardPicking_Set(index, card)

# --------------------------------------------------------------- card picking (drag)

func gsCardPicking_Set(index: int, card: Card) -> void:
	dragging = true
	drag_index = index
	drag_card = card
	sfx_button.play()
	_show_card_info(card)

	hand_slots[index].modulate.a = 0.0

	drag_ghost = CardView.new()
	drag_ghost.setup(card)
	drag_ghost.z_index = 10
	add_child(drag_ghost)
	# Gamepad has no mouse position to speak of - get_global_mouse_position()
	# would leave the ghost wherever the OS cursor happens to be (hidden, off
	# in a corner), reading as "the card just vanished". Start it at the hand
	# slot instead; on_focus_changed (_setup_nav) then drags it along to
	# whichever board cell the pad points at next, same as the mouse path's
	# own continuous _update_drag_ghost_pos does for a real mouse.
	if ControllerUI.is_gamepad():
		drag_ghost.position = hand_slots[index].position
	else:
		_update_drag_ghost_pos(get_global_mouse_position())

func _input(event: InputEvent) -> void:
	if end_flow == EndFlow.PLAYER_PICK:
		_end_player_pick_input(event)
		return

	if not dragging:
		return
	if event is InputEventMouseMotion:
		_update_drag_ghost_pos(event.position)
		_update_drag_hover(event.position)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		gsCardPicking_Release(event.position)

func _update_drag_ghost_pos(mouse_pos: Vector2) -> void:
	drag_ghost.position = mouse_pos - Vector2(CARD_W, CARD_H) / 2.0

func _slot_under_point(pos: Vector2) -> Vector2i:
	var rel := pos - BOARD_POS
	var col := int(rel.x / (CARD_W + BOARD_GAP))
	var row := int(rel.y / (CARD_H + BOARD_GAP))
	if row < 0 or row >= Board.NUM_ROWS or col < 0 or col >= Board.NUM_COLS:
		return Vector2i(-1, -1)
	var cell_pos := _board_cell_pos(row, col)
	if pos.x > cell_pos.x + CARD_W or pos.y > cell_pos.y + CARD_H:
		return Vector2i(-1, -1)  # inside the gap between cells
	return Vector2i(row, col)

func _update_drag_hover(mouse_pos: Vector2) -> void:
	var cell := _slot_under_point(mouse_pos)
	_show_hover_glow_at(cell.x, cell.y)

## Shared by the mouse drag path (_update_drag_hover, after its own point-to-
## cell lookup) and the pad path (focus_changed, already holding a row/col
## directly) - same card_sel_glow.png highlight either way.
func _show_hover_glow_at(row: int, col: int) -> void:
	if row >= 0 and board.is_playable(row, col):
		var cell_pos := _board_cell_pos(row, col)
		if not board_hover_glow.visible or board_hover_glow.position != cell_pos:
			board_hover_glow.position = cell_pos
			_start_hover_glow_flash()
		board_hover_glow.visible = true
	else:
		_stop_hover_glow_flash()

func _start_hover_glow_flash() -> void:
	if is_instance_valid(board_hover_glow_tween):
		board_hover_glow_tween.kill()
	board_hover_glow.modulate.a = HOVER_GLOW_MIN_ALPHA
	board_hover_glow_tween = create_tween()
	board_hover_glow_tween.set_loops()
	board_hover_glow_tween.tween_property(board_hover_glow, "modulate:a", HOVER_GLOW_MAX_ALPHA, HOVER_GLOW_FLASH_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	board_hover_glow_tween.tween_property(board_hover_glow, "modulate:a", HOVER_GLOW_MIN_ALPHA, HOVER_GLOW_FLASH_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _stop_hover_glow_flash() -> void:
	if is_instance_valid(board_hover_glow_tween):
		board_hover_glow_tween.kill()
		board_hover_glow_tween = null
	board_hover_glow.visible = false

func gsCardPicking_Release(mouse_pos: Vector2) -> void:
	var cell := _slot_under_point(mouse_pos)
	drag_ghost.queue_free()
	drag_ghost = null
	_stop_hover_glow_flash()
	dragging = false

	if cell.x >= 0 and board.is_playable(cell.x, cell.y):
		busy = true
		var card := drag_card
		player_hand[drag_index] = null
		board.place_card(card, cell.x, cell.y)
		sfx_place.play()
		_refresh_hands()
		_update_slot_visual(cell.x, cell.y)
		_refresh_scores()
		_show_card_info(null)

		await gsPreBattle_Set(card)
		gsNextTurn_Set()
	else:
		hand_slots[drag_index].modulate.a = 1.0
		_show_card_info(null)

# ------------------------------------------------------------------- cpu turn

func gsCPUTurn_Set() -> void:
	active_player = 1
	busy = true
	var tw := create_tween()
	tw.tween_property(turn_cursor, "position:y", 125.0, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(0.5).timeout

	var live_cpu_hand: Array = cpu_hand.filter(func(c): return c != null)
	var move := GsCPUTurn.choose_move(board, live_cpu_hand, cpu_level)
	var card: Card = move["card"]
	var row: int = move["row"]
	var col: int = move["col"]

	# fly a face-down mini card from the opponent stack to the board slot,
	# then flip it to reveal the real card (gsCPUTurn.cs's quadPlayer1Cards
	# move+rotate, simplified to one ghost instead of a paired UI+real card).
	var idle_count := live_cpu_hand.size()
	var ghost := TextureRect.new()
	ghost.texture = load(ASSETS + "cards/card_back.png")
	ghost.stretch_mode = TextureRect.STRETCH_SCALE
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var ghost_size := Vector2(CARD_W, CARD_H) * OPPONENT_CARD_SCALE
	ghost.position = OPPONENT_STACK_POS + Vector2((idle_count - 1) * OPPONENT_STACK_STEP, 0) - ghost_size / 2.0
	ghost.size = ghost_size
	ghost.pivot_offset = ghost.size / 2.0
	add_child(ghost)

	var target_pos := _board_cell_pos(row, col)
	var tw2 := create_tween()
	tw2.tween_property(ghost, "position", target_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw2.parallel().tween_property(ghost, "size", Vector2(CARD_W, CARD_H), 0.4)
	await tw2.finished

	sfx_place.play()
	var tw3 := create_tween()
	tw3.tween_property(ghost, "scale:x", 0.0, 0.15)
	await tw3.finished
	ghost.queue_free()

	cpu_hand[cpu_hand.find(card)] = null
	board.place_card(card, row, col)
	_refresh_hands()
	_update_slot_visual(row, col)
	_refresh_scores()

	await gsPreBattle_Set(card)
	gsNextTurn_Set()

# ---------------------------------------------------- PreBattle / BattleCheck

# Ports gsPreBattle.cs -> gsBattleCheck.cs -> gsBattle.cs -> (chain) ->
# gsBattleCheck.cs, collapsed into one recursive coroutine.
func gsPreBattle_Set(last_placed: Card) -> void:
	await get_tree().create_timer(0.15).timeout
	await gsResolveCardTurn_Set(last_placed, 0)

## Design doc: "Flusso Logico del Turno e Priorità". Every capture - the
## just-placed card, or any card captured deeper in the chain - resolves
## the SAME two sub-phases on itself, in order:
##   1. Combo: free instant captures through arrows with no return arrow.
##   2. Chain: real battles against arrows WITH a return arrow. Winning one
##      makes the just-captured card the new epicenter and repeats this
##      whole function on it (one level deeper) - a chain link can now lose
##      or tie instead of being a guaranteed geometric capture, which is
##      what gives the chain real risk instead of being deterministic
##      once arrows happen to line up.
## `depth` counts consecutive battle wins in this lineage (0 = the initial
## placement, not yet a chain - a Chain popup only starts once it reaches 2).
func gsResolveCardTurn_Set(card: Card, depth: int) -> void:
	var simple := board.get_capturable_cards(card)
	if not simple.is_empty():
		# Counts toward this card's level-up credit even at depth 0 (no
		# popup shown there) - the popup is cosmetic, the capture itself
		# still happened.
		card.battle_captures += simple.size()
		# Combo is specifically the bonus a WON battle cascades into, not
		# just placing a card next to undefended neighbors - depth 0 (the
		# initial placement) still captures them, just silently, same as
		# any other ordinary capture.
		if card.owner == 0 and depth >= 1:
			await _show_chain_text(card, "Combo", simple.size())
		await _capture_batch(card, simple)

	await gsBattleChainBattle_Set(card, depth, [])

## `tied` accumulates opponents `card` has already drawn against this turn:
## get_adjacent_battle_cards is pure board state (position/owner/arrows), so
## a tied card - still on the board, still adjacent, still an enemy - would
## otherwise be offered right back as a "fightable" target forever instead
## of moving on to the next one in the player's chosen order.
func gsBattleChainBattle_Set(card: Card, depth: int, tied: Array) -> void:
	var fightable := board.get_adjacent_battle_cards(card)
	for t in tied:
		fightable.erase(t)
	if fightable.is_empty():
		return
	elif fightable.size() == 1:
		await gsBattle_Set(card, fightable[0], depth, tied)
	elif card.owner != 0:
		# New QoL addition (not in the reference, which shows the same
		# "pick a target" highlight/delay for the CPU too): the AI's choice
		# isn't a real decision the player watches unfold, so skip the
		# target-selection UI entirely and fight immediately.
		var target := GsCPUTurn.choose_battle_target(card, fightable, cpu_level)
		await gsBattle_Set(card, target, depth, tied)
	else:
		# The player picking which candidate to fight next - and getting a
		# fresh choice again after a tie - IS "scegliere l'ordine con cui
		# farle attaccare" from the design doc: no separate up-front queue
		# needed, this already resolves the order one decision at a time.
		var target := await gsBattleSelTarget_Set(card, fightable)
		await gsBattle_Set(card, target, depth, tied)

func gsBattleSelTarget_Set(last_placed: Card, candidates: Array) -> Card:
	_highlight_targets(candidates, true)

	target_mode = true
	target_candidates = candidates
	var chosen: Card = await target_chosen
	target_mode = false
	target_candidates = []

	_highlight_targets(candidates, false)
	return chosen

func _on_slot_pressed(row: int, col: int) -> void:
	if target_mode:
		var card: Card = board.slots[row][col]
		if card != null and target_candidates.has(card):
			# Cleared before emitting, not after gsBattleSelTarget_Set's own
			# await resumes: a second press landing in the gap between this
			# emit and that resume (every candidate cell is still nominally
			# enabled until target_mode actually flips) re-entered this same
			# branch and fired a second target_chosen, one card selected to
			# capture but the coroutine already halfway into resolving a
			# different one - only the first press should ever be able to.
			target_mode = false
			target_chosen.emit(card)

# ------------------------------------------------------------------- battle

func gsBattle_Set(card0: Card, card1: Card, depth: int, tied: Array) -> void:
	var result := GsBattle.resolve_battle(card0, card1)

	await gsBattle_StartRumble(card0, card1, result)
	await gsBattle_Countdown(card0, card1, result)
	await gsBattle_End(card0, card1, result, depth, tied)

func gsBattle_StartRumble(card0: Card, card1: Card, result: Dictionary) -> void:
	var view0: CardView = board_card_views[card0.row][card0.col]
	var view1: CardView = board_card_views[card1.row][card1.col]
	var pos0 := _board_cell_pos(card0.row, card0.col)
	var pos1 := _board_cell_pos(card1.row, card1.col)
	var vec := (pos1 - pos0).normalized()

	# battle values - parented to their card so they ride along with the
	# rumble tween below instead of staying fixed on the board. Seed the
	# text with the stat the countdown tween will start from, otherwise
	# whatever text was left over from the previous battle flashes here.
	battle_value_labels[0].text = str(result["attack_stat"])
	battle_value_labels[1].text = str(result["defense_stat"])
	for i in 2:
		battle_value_labels[i].visible = true
	_position_battle_labels(view0, view1)

	# vfx effect at the midpoint
	var vfx: AnimatedSprite2D = vfx_sprites[card0.attack_type]
	vfx.position = pos0 + (pos1 - pos0) / 2.0 + Vector2(CARD_W, CARD_H) / 2.0
	vfx.visible = true
	vfx.frame = 0
	vfx.play("play")

	if card0.attack_type == Card.AttackType.MAGICAL:
		sfx_attack_m.play()
	else:
		sfx_attack_p.play()

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(view0, "position", vec * BATTLE_RUMBLE_DISTANCE, BATTLE_RUMBLE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(view1, "position", -vec * BATTLE_RUMBLE_DISTANCE, BATTLE_RUMBLE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished

	vfx.visible = false

func _position_battle_labels(view0: CardView, view1: CardView) -> void:
	# Big and centered in the card's upper area, above the stat text and
	# below the frame's top edge. Reparented onto the card itself (in local
	# coordinates) so it rides along when the card rumbles toward its
	# opponent instead of staying fixed on the board underneath it.
	var views := [view0, view1]
	for i in 2:
		var label: Label = battle_value_labels[i]
		if label.get_parent() != views[i]:
			label.reparent(views[i], false)
		label.position = Vector2(0, BATTLE_VALUE_AREA_TOP)
		label.size = Vector2(CARD_W, BATTLE_VALUE_AREA_BOTTOM - BATTLE_VALUE_AREA_TOP)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func gsBattle_Countdown(card0: Card, card1: Card, result: Dictionary) -> void:
	await get_tree().create_timer(0.15).timeout

	var tw := create_tween()
	tw.tween_method(func(v): battle_value_labels[0].text = str(int(v)),
		float(result["attack_stat"]), float(result["attack_value"]), BATTLE_COUNTDOWN_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v): battle_value_labels[1].text = str(int(v)),
		float(result["defense_stat"]), float(result["defense_value"]), BATTLE_COUNTDOWN_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished

func gsBattle_End(card0: Card, card1: Card, result: Dictionary, depth: int, tied: Array) -> void:
	for i in 2:
		battle_value_labels[i].visible = false
		# unparent before the capture flip below can free the CardView
		# they were riding on.
		if battle_value_labels[i].get_parent() != self:
			battle_value_labels[i].reparent(self, false)

	# New QoL addition (not in the reference, which never resets card0/card1's
	# rumble offset at all - they stay permanently shifted 16px toward each
	# other after every battle, a real bug there). Ported as a smooth ease
	# back to the grid slot instead of a hard position snap.
	var view0: CardView = board_card_views[card0.row][card0.col]
	var view1: CardView = board_card_views[card1.row][card1.col]
	var tw_back := create_tween()
	tw_back.set_parallel(true)
	if is_instance_valid(view0):
		tw_back.tween_property(view0, "position", Vector2.ZERO, BATTLE_RUMBLE_RETURN_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if is_instance_valid(view1):
		tw_back.tween_property(view1, "position", Vector2.ZERO, BATTLE_RUMBLE_RETURN_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw_back.finished

	var winner: Card = result["winner"]
	if winner == null or (winner != card0 and depth >= 1):
		# A tie never captures either side. A LOSS is treated the same way,
		# but only for a chain battle (depth >= 1, card0 is itself a card
		# captured earlier this cascade): fighting onward wasn't the
		# player's deliberate choice the way placing the original card was,
		# so a losing chain link shouldn't cost them the card either - it
		# just stays put and this line stops, exactly like a tie. Only the
		# very first battle (depth 0, the one the player actually chose by
		# placing there) keeps real capture-on-loss risk, handled below.
		await get_tree().create_timer(0.3).timeout
		# card0 is still standing and may still have other neighbors left
		# to challenge, in the player's next chosen order (see
		# gsBattleChainBattle_Set's `tied` doc comment on why card1 must be
		# excluded, not just dropped).
		await gsBattleChainBattle_Set(card0, depth, tied + [card1])
		return

	var loser: Card = result["loser"]
	await captureCardProcedure(winner, loser)
	# Counts for the winner regardless of which side it is - a defender that
	# beats an attacker still captured a card and earns level-up credit for
	# it, even though (unlike an attacker's win) it doesn't cascade further.
	winner.battle_captures += 1

	if winner != card0:
		# Only reachable at depth 0 now (see the tie/chain-loss branch
		# above): the initial battle the player chose by placing card0
		# there, lost outright. Normal capture rules apply - card0 is
		# recaptured and this lineage ends here, same as any other loss.
		return

	# card0 won: `loser` becomes the new epicenter, one link deeper in the
	# chain. Design doc: "la Fase 2 si ripete da capo prendendo come
	# riferimento quest'ultima carta" - card0 does NOT go on to try any
	# other candidates it might have had; the moment it wins, focus shifts
	# entirely to what it just captured.
	var new_depth := depth + 1
	if new_depth >= 2 and winner.owner == 0:
		# Always awaited so Chain fully finishes before anything else -
		# the new epicenter's own Combo/Chain popups on the same label
		# node, or the next battle in this lineage - can start.
		await _show_chain_text(winner, "Chain", new_depth)

	await gsResolveCardTurn_Set(loser, new_depth)

# --------------------------------------------------------------- captures

# Ports captureCardProcedure(): the original flips the captured card+a
# temporary card-back overlay by 180 degrees and swaps ownership at the
# midpoint. Godot's 2D canvas has no real Y-rotation, so this fakes the
# same flip with a scale_x 1 -> 0 -> 1 tween and rebuilds the CardView with
# the new owner's colors at the midpoint.
func captureCardProcedure(attacker: Card, captured: Card) -> void:
	var row := captured.row
	var col := captured.col
	var view: CardView = board_card_views[row][col]
	if not is_instance_valid(view):
		board.capture(captured, attacker.owner)
		_update_slot_visual(row, col)
		_refresh_scores()
		return

	view.pivot_offset = Vector2(CARD_W, CARD_H) / 2.0

	var tw := create_tween()
	tw.tween_property(view, "scale:x", 0.0, CAPTURE_FLIP_TIME / 2.0)
	await tw.finished

	board.capture(captured, attacker.owner)
	_update_slot_visual(row, col)
	_refresh_scores()
	var new_view: CardView = board_card_views[row][col]
	new_view.pivot_offset = Vector2(CARD_W, CARD_H) / 2.0
	new_view.scale.x = 0.0

	var tw2 := create_tween()
	tw2.tween_property(new_view, "scale:x", 1.0, CAPTURE_FLIP_TIME / 2.0)
	await tw2.finished

# Same flip as captureCardProcedure but for a whole batch of cards at once,
# all shrinking/growing in parallel instead of one after another - used for
# both an instant multi-arrow capture and a chain burst.
func _capture_batch(attacker: Card, cards: Array) -> void:
	var animated: Array = []
	for c in cards:
		var view: CardView = board_card_views[c.row][c.col]
		if is_instance_valid(view):
			view.pivot_offset = Vector2(CARD_W, CARD_H) / 2.0
			animated.append(c)
		else:
			board.capture(c, attacker.owner)
			_update_slot_visual(c.row, c.col)

	if not animated.is_empty():
		var tw := create_tween()
		tw.set_parallel(true)
		for c in animated:
			tw.tween_property(board_card_views[c.row][c.col], "scale:x", 0.0, CAPTURE_FLIP_TIME / 2.0)
		await tw.finished

	var growing: Array = []
	for c in animated:
		board.capture(c, attacker.owner)
		_update_slot_visual(c.row, c.col)
		var new_view: CardView = board_card_views[c.row][c.col]
		new_view.pivot_offset = Vector2(CARD_W, CARD_H) / 2.0
		new_view.scale.x = 0.0
		growing.append(new_view)
	_refresh_scores()

	if not growing.is_empty():
		var tw2 := create_tween()
		tw2.set_parallel(true)
		for view in growing:
			tw2.tween_property(view, "scale:x", 1.0, CAPTURE_FLIP_TIME / 2.0)
		await tw2.finished

const COMBO_COLOR := Color(1, 0.85, 0.1)  # gold - single-level, the smaller event
const CHAIN_COLOR := Color(1, 0.35, 0.05)  # hot orange-red - reaches a 2nd level, the bigger event

func _show_chain_text(winner: Card, label_word: String, count: int) -> void:
	var pos := _board_cell_pos(winner.row, winner.col) + Vector2(CARD_W, CARD_H) / 2.0
	chain_label.text = label_word if count == 1 else "%s x%d" % [label_word, count]
	chain_label.add_theme_color_override("font_color", CHAIN_COLOR if label_word == "Chain" else COMBO_COLOR)
	chain_label.position = pos - Vector2(70, 55)
	chain_label.pivot_offset = chain_label.get_minimum_size() / 2.0
	chain_label.modulate.a = 0.0
	# Overshoot scale-in ("juice"): starts big and settles to 1x instead of
	# just fading, reads as impact instead of a passive notice.
	chain_label.scale = Vector2(1.4, 1.4)
	chain_label.visible = true

	var tw := create_tween()
	tw.tween_property(chain_label, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(chain_label, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(chain_label, "position:x", pos.x, 0.3)
	tw.tween_interval(0.6)
	tw.tween_property(chain_label, "modulate:a", 0.0, 0.3)
	await tw.finished
	chain_label.visible = false

# ------------------------------------------------------------------- turns

func gsNextTurn_Set() -> void:
	var player_has_cards := player_hand.any(func(c): return c != null)
	var cpu_has_cards := cpu_hand.any(func(c): return c != null)
	if not player_has_cards and not cpu_has_cards:
		await gsEndStart_Set()
		return

	active_player = 1 - active_player
	if active_player == 1:
		gsCPUTurn_Set()
	else:
		gsPlayerTurn_Set()

# --------------------------------------------------------------- end of match

enum BattleResult { PLAYER_WINS, PLAYER_PERFECT, CPU_WINS, CPU_PERFECT, DRAW }

func gsEndStart_Set() -> void:
	busy = true
	turn_cursor.visible = false

	var p0 := board.count_cards(0)
	var p1 := board.count_cards(1)
	var result: BattleResult
	var banner_path: String

	if p0 > p1 and p0 == 10:
		result = BattleResult.PLAYER_PERFECT
		banner_path = "battle/battle_perfect.png"
	elif p0 > p1:
		result = BattleResult.PLAYER_WINS
		banner_path = "battle/battle_win.png"
	elif p1 > p0 and p1 == 10:
		result = BattleResult.CPU_PERFECT
		banner_path = "battle/battle_lose.png"
	elif p1 > p0:
		result = BattleResult.CPU_WINS
		banner_path = "battle/battle_lose.png"
	else:
		result = BattleResult.DRAW
		banner_path = "battle/battle_draw.png"

	end_panel.visible = true

	# banner slides in, holds, slides out
	var banner_tex: Texture2D = load(ASSETS + banner_path)
	end_banner.texture = banner_tex
	end_banner.size = Vector2(banner_tex.get_width(), banner_tex.get_height())
	var banner_y := (SCREEN_H - end_banner.size.y) / 2.0
	end_banner.position = Vector2(-end_banner.size.x, banner_y)
	end_banner.visible = true

	var tw := create_tween()
	tw.tween_property(end_banner, "position:x", (SCREEN_W - end_banner.size.x) / 2.0, 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.6)
	tw.tween_property(end_banner, "position:x", float(SCREEN_W), 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw.finished

	# background drops
	var tw2 := create_tween()
	tw2.tween_property(end_bkg, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw2.finished

	await _move_cards_to_end_rows()
	await gsEndLevelUp_Set(result)

func _move_cards_to_end_rows() -> void:
	end_up_cards.clear()
	end_down_cards.clear()

	for row in Board.NUM_ROWS:
		for col in Board.NUM_COLS:
			var card: Card = board.slots[row][col]
			if card == null:
				continue
			var view: CardView = board_card_views[row][col]
			if not is_instance_valid(view):
				continue
			view.reparent(end_panel, true)
			if card.original_owner == 0:
				end_up_cards.append(view)
			else:
				end_down_cards.append(view)

	var tw := create_tween()
	tw.set_parallel(true)
	for i in end_up_cards.size():
		var x := END_PL0_START.x + i * (CARD_W + END_PL_OFFSET_X)
		tw.tween_property(end_up_cards[i], "position", Vector2(x, END_PL0_START.y), 1.0) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in end_down_cards.size():
		var x := END_PL1_START.x + i * (CARD_W + END_PL_OFFSET_X)
		tw.tween_property(end_down_cards[i], "position", Vector2(x, END_PL1_START.y), 1.0) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished

# --------------------------------------------------------- end: level up

func gsEndLevelUp_Set(result: BattleResult) -> void:
	# Hybrid: a small flat bonus only on an actual match win (LEVEL_UP_POINTS
	# has no Draw/loss entry - a draw used to grant 1 point per card just for
	# surviving, which made repeatedly drawing a farmable source of free
	# growth), plus battle_captures - points for cards that personally won a
	# battle, chain link, or combo this match, regardless of the match's
	# overall result. A card that fought well in an otherwise-drawn or lost
	# match still grows for what IT did; one that never fought gets nothing
	# unless the match was an outright win.
	var base_points := LEVEL_UP_POINTS.get(result, 0) as int
	for view in end_up_cards:
		var card: Card = view.card
		var points := base_points + card.battle_captures
		if points > 0:
			await _level_up_card(view, card, points)
			_sync_card_stats_to_collection(card)

	# A win or draw is already a safe outcome - clear match_started (and
	# persist it) right away instead of waiting for the player to press
	# Done, so quitting the app on this screen doesn't wrongly trigger the
	# rage-quit punishment on next launch. A loss deliberately keeps
	# match_started true until gsEndCPUPick's own close/save, since that's
	# exactly the "quit to dodge losing cards" case rage-quit exists for.
	match result:
		BattleResult.PLAYER_PERFECT, BattleResult.PLAYER_WINS:
			Game.player.match_started = false
			SaveSystem.save_player(Game.player)
			gsEndPlayerPick_Set(result)
		BattleResult.CPU_PERFECT, BattleResult.CPU_WINS:
			gsEndCPUPick_Set(result)
		BattleResult.DRAW:
			Game.player.match_started = false
			SaveSystem.save_player(Game.player)
			gsEndNonePick_Set()

# Spends `points` growth points on this card (see gsEndLevelUp_Set for how
# many a result is worth), one stat at a time.
#
# Two deliberate departures from the reference's rules:
#
# - A point is never wasted. The reference rolled 1-of-5 fixed slots and, if
#   that slot already sat at the card's ceiling, dropped the point outright
#   (Tetra Master's "blind spot"). Here the draw happens only among stats
#   that can still grow, so a nearly-maxed card keeps improving instead of
#   stalling. Attack power still gets two entries to the defenses' one each,
#   preserving the original 2:1:1 weighting.
#
# - The attack type advances deterministically at growth thresholds instead
#   of on a 5%/1% roll per attempt (which worked out to ~1% and ~0.2% per
#   match - hundreds of matches for one step). Crossing at 45%/75% of the
#   card's own headroom means the jump lands mid-curve, while the card still
#   has room to grow, so its power ramps continuously rather than suddenly
#   doubling on an already-maxed card.
#
# Floating text reports the net change once, after all the points are spent,
# rather than one popup per point.
const LEVEL_UP_POINTS := {
	BattleResult.PLAYER_PERFECT: 2,  # was 5 - most of the growth is now the battle_captures bonus
	BattleResult.PLAYER_WINS: 1,     # was 3
	# No Draw entry - see gsEndLevelUp_Set.
}
const TYPE_UP_GROWTH_X := 0.45
const TYPE_UP_GROWTH_A := 0.75

func _level_up_card(view: CardView, card: Card, points: int) -> void:
	var def: CardManager.CardDef = CardManager.defs[card.def_id]

	var old_attack_power := card.attack_power
	var old_attack_type := card.attack_type
	var old_pdef := card.physical_defense
	var old_mdef := card.magical_defense

	var spent := 0
	for i in points:
		var pool := []
		if card.can_level_up_a_pow():
			pool.append(0)
			pool.append(0)
		if card.can_level_up_p_def():
			pool.append(2)
		if card.can_level_up_m_def():
			pool.append(3)
		if pool.is_empty():
			break
		match pool[randi() % pool.size()]:
			0: card.attack_power = mini(card.attack_power + 1, def.max_attack_power)
			2: card.physical_defense = mini(card.physical_defense + 1, def.max_physical_defense)
			3: card.magical_defense = mini(card.magical_defense + 1, def.max_magical_defense)
		spent += 1

	if card.attack_type < Card.AttackType.FLEXIBLE \
			and def.max_attack_type >= Card.AttackType.FLEXIBLE \
			and CardManager.growth(card) >= TYPE_UP_GROWTH_X:
		card.attack_type = Card.AttackType.FLEXIBLE
	elif card.attack_type == Card.AttackType.FLEXIBLE \
			and def.max_attack_type >= Card.AttackType.ASSAULT \
			and CardManager.growth(card) >= TYPE_UP_GROWTH_A:
		card.attack_type = Card.AttackType.ASSAULT

	if spent == 0 and card.attack_type == old_attack_type:
		await _show_level_up_text(view, StringTable.get_string(StringTable.ID_CARD_LVLUP_MAX), " ")
		return

	if card.attack_type != old_attack_type:
		var s0 := StringTable.get_string(StringTable.ID_CARD_LVLUP_ATTACK_TYPE)
		var s1 := CardManager.attack_type_to_string(old_attack_type)
		# "MAX" now means "this stat just hit its ceiling". The reference
		# tested the OLD value instead, which only ever fired because a
		# wasted point could leave a maxed stat "changing" by 0 - impossible
		# now that the draw only picks stats with room left.
		if card.attack_type == def.max_attack_type:
			s1 += " " + StringTable.get_string(StringTable.ID_CARD_LVLUP_MAX)
		await _show_level_up_text(view, s0, s1)

	if card.attack_power != old_attack_power:
		var inc := card.attack_power - old_attack_power
		var s0 := StringTable.get_string(StringTable.ID_CARD_ATTACK) + " " + StringTable.get_string(StringTable.ID_CARD_LVLUP)
		var s1 := "%d+%d" % [old_attack_power, inc]
		if card.attack_power == def.max_attack_power:
			s1 += " " + StringTable.get_string(StringTable.ID_CARD_LVLUP_MAX)
		await _show_level_up_text(view, s0, s1)

	if card.physical_defense != old_pdef:
		var inc := card.physical_defense - old_pdef
		var s0 := StringTable.get_string(StringTable.ID_CARD_PHYSICAL_DEFENSE) + " " + StringTable.get_string(StringTable.ID_CARD_LVLUP)
		var s1 := "%d+%d" % [old_pdef, inc]
		if card.physical_defense == def.max_physical_defense:
			s1 += " " + StringTable.get_string(StringTable.ID_CARD_LVLUP_MAX)
		await _show_level_up_text(view, s0, s1)

	if card.magical_defense != old_mdef:
		var inc := card.magical_defense - old_mdef
		var s0 := StringTable.get_string(StringTable.ID_CARD_MAGICAL_DEFENSE) + " " + StringTable.get_string(StringTable.ID_CARD_LVLUP)
		var s1 := "%d+%d" % [old_mdef, inc]
		if card.magical_defense == def.max_magical_defense:
			s1 += " " + StringTable.get_string(StringTable.ID_CARD_LVLUP_MAX)
		await _show_level_up_text(view, s0, s1)

	view.setup(card)

# BattleScene's player_hand cards are clone_stats() copies of the entries
# in Game.player.cards (so mid-battle owner mutations don't corrupt the
# persistent collection - see clone_stats()'s docstring). The reference
# doesn't need this: Card.Stats is a shared reference there, so a level-up
# on the battle card IS the same object as the one in Player.cards. Here
# that has to be an explicit sync instead, matched by unique_id.
func _sync_card_stats_to_collection(card: Card) -> void:
	for entry in Game.player.cards:
		if entry.unique_id == card.unique_id:
			entry.attack_power = card.attack_power
			entry.physical_defense = card.physical_defense
			entry.magical_defense = card.magical_defense
			entry.attack_type = card.attack_type
			return

# Simplified from gsEndLevelUp.cs's parallel-delay choreography (multiple
# floating texts scheduled with staggered start times) to one small tween
# per message, awaited in sequence - same "stat pops up and floats away"
# read, far less bookkeeping.
func _show_level_up_text(view: CardView, line0: String, line1: String) -> void:
	var label := Label.new()
	# Globals.UIFontLevelUp: font_info.ttf at 24 - bumped a bit further since
	# a 96px-wide card leaves little room and the text needs to read at a
	# glance. Color/shadow match the reference exactly (light grey, black
	# drop shadow).
	label.add_theme_font_override("font", font_info)
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(213.0 / 255.0, 213.0 / 255.0, 213.0 / 255.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.text = line0 + "\n" + line1
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(CARD_W * 2.5, 64)
	# Reference starts the text at the card's bottom edge and floats it a
	# full card-height upward (ending well above the card) - on a small
	# 96x128 card that reads as "appears above the card, easy to miss".
	# Center it on the card instead and only drift up a little.
	var card_center: Vector2 = view.position + Vector2(CARD_W, CARD_H) / 2.0
	label.position = card_center - label.size / 2.0
	label.modulate.a = 0.0
	label.z_index = 60
	end_panel.add_child(label)

	# 3x speedup (was 0.2/1.5/1.0/0.5s) - with up to 4 stats x 5 cards to show
	# in sequence, the original pacing made the end-of-match screen crawl.
	var start_y := label.position.y
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 0.2 / 3.0)
	var tw2 := create_tween()
	tw2.tween_property(label, "position:y", start_y - 30.0, 1.5 / 3.0)
	await get_tree().create_timer(1.0 / 3.0).timeout
	var tw3 := create_tween()
	tw3.tween_property(label, "modulate:a", 0.0, 0.5 / 3.0)
	await tw3.finished
	label.queue_free()

# --------------------------------------------------------- end: shared helpers

# Compresses `views` into `total_width` starting at `start` (same fit-to-
# width logic as gsEndPlayer_MoveCardUp, shared by both EndPlayerPick's and
# EndCPUPick's row layout in the reference too). Cards flagged in
# end_movable sit slightly higher (they're the ones actually changing hands).
func _relayout_row(views: Array, start: Vector2, total_width: float, mov_time: float) -> void:
	if views.is_empty():
		return
	var count: int = views.size()
	var natural_len: float = count * CARD_W + (count - 1) * END_PL_OFFSET_X
	var offs := END_PL_OFFSET_X
	if natural_len > total_width and count > 1:
		offs = ceilf((total_width - count * CARD_W) / float(count - 1))

	var tw := create_tween()
	tw.set_parallel(true)
	for i in count:
		var x: float = start.x + i * (CARD_W + offs)
		var y: float = start.y
		if end_movable.get(views[i], false):
			y -= END_PL_OFFSET_Y / 2.0
		tw.tween_property(views[i], "position", Vector2(x, y), mov_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _card_view_contains(view: CardView, pos: Vector2) -> bool:
	return Rect2(view.position, Vector2(CARD_W, CARD_H)).has_point(pos)

func _show_end_card_info(card: Card) -> void:
	if card == null:
		panel_owned.visible = false
		panel_info.visible = false
		end_owned_view = null
		return

	panel_info.visible = true
	panel_owned.visible = true
	var owned_word := StringTable.get_string(StringTable.ID_OWNED)
	owned_label.text = "%s\n%d" % [owned_word, Game.player.get_num_cards_of_this_type(card)]
	# fit_button_text doesn't handle a 2-line label correctly (get_string_size
	# doesn't measure "\n" as a line break) - the count line is always short,
	# so only the translated word needs a width-based shrink to stay inside
	# the now-card-width box for longer translations (e.g. "Possédées").
	var fitted := UIButtonStyle.fit_text_to_width(owned_word, owned_label.get_theme_font("font"), panel_owned.size.x - 8, 22)
	owned_label.add_theme_font_size_override("font_size", fitted)

	var def: CardManager.CardDef = CardManager.defs[card.def_id]
	end_info_name.text = def.name
	end_info_pdef_val.text = str(card.physical_defense)
	end_info_mdef_val.text = str(card.magical_defense)
	end_info_offense_val.text = str(card.attack_power)
	end_info_type_val.text = CardManager.attack_type_to_string(card.attack_type)

const OWNED_PANEL_GAP := 6.0

func _update_owned_panel_pos(view: CardView) -> void:
	end_owned_view = view
	var x := view.position.x + CARD_W / 2.0 - panel_owned.size.x / 2.0
	var below := view.position.y + CARD_H + OWNED_PANEL_GAP
	# Cards in the bottom row (or dragged near the bottom edge) would push the
	# panel off-screen below them - flip it above the card instead so it's
	# always fully visible regardless of which row the card is in.
	var y: float = below if below + panel_owned.size.y <= SCREEN_H else view.position.y - OWNED_PANEL_GAP - panel_owned.size.y
	panel_owned.position = Vector2(x, y)

# Cards keep moving after the panel is last positioned (drag-release tweens,
# _relayout_row) - pin the panel to its card every frame instead of patching
# every place a tween can move end_owned_view.
func _process(_delta: float) -> void:
	if end_owned_view != null and panel_owned.visible:
		_update_owned_panel_pos(end_owned_view)
	y_continue_hint.visible = ControllerUI.is_gamepad() and button_done.visible

func _return_to_main_menu() -> void:
	Game.crossfade_to_menu_music(0.85)
	get_tree().change_scene_to_file("res://scenes/menu/Opponents.tscn")

# Single Button_Done handler shared by all three end flows (matches which
# one is live via end_flow), same as the reference wiring one ButtonAction
# per UIBattleEnd instance but always to the same-shaped Close callback.
func _on_end_done_pressed() -> void:
	sfx_button.play()
	busy_spinner.visible = true
	end_pick_interactive = false
	button_done.disabled = true
	await get_tree().create_timer(1.2).timeout
	match end_flow:
		EndFlow.PLAYER_PICK:
			_end_player_pick_close()
		EndFlow.CPU_PICK:
			_end_cpu_pick_close()
		EndFlow.DRAW:
			_end_none_pick_close()

# --------------------------------------------------------- end: player pick

func gsEndPlayerPick_Set(result: BattleResult) -> void:
	end_flow = EndFlow.PLAYER_PICK
	end_result = result
	end_sel_view = null
	end_pick_interactive = false
	_current_pick_view = null

	# Shown here rather than at payout time (_end_player_pick_close) so the
	# player sees what they earned while picking their card, not after the
	# screen is already gone. Both read _coin_reward(), which depends on
	# ai.defeated still being false at this point.
	label_coin_reward.text = "[center]+%d [img=28x28]res://assets/coins_icon.png[/img][/center]" % _coin_reward()
	label_coin_reward.visible = true

	if result == BattleResult.PLAYER_PERFECT:
		end_remaining = 5
		label_central_msg.text = StringTable.get_string(StringTable.ID_MSG_PICK_5_CARD)
		label_central_msg.position = END_TAKEALL_MSG_POS
		label_central_msg.size = END_TAKEALL_MSG_SIZE
		label_central_msg.add_theme_font_size_override("font_size", END_TAKEALL_MSG_FONT_SIZE)
		label_central_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label_central_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UIButtonStyle.fit_button_text(label_central_msg)
		button_takeall.position = END_TAKEALL_BUTTON_POS
	else:
		end_remaining = 1
		label_central_msg.text = StringTable.get_string(StringTable.ID_MSG_PICK_1_CARD)
		label_central_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	label_central_msg.visible = true
	label_central_msg.modulate.a = 0.0
	var tw_msg := create_tween()
	tw_msg.tween_property(label_central_msg, "modulate:a", 1.0, 1.5)

	if result == BattleResult.PLAYER_PERFECT:
		button_takeall.visible = true
		button_takeall.modulate.a = 0.0
		var tw_all := create_tween()
		tw_all.tween_property(button_takeall, "modulate:a", 1.0, 1.5)
	else:
		help_arrow.visible = true
		help_arrow.modulate.a = 0.0
		var tw_arrow := create_tween()
		tw_arrow.tween_property(help_arrow, "modulate:a", 1.0, 3.0)

	end_movable.clear()
	for view in end_down_cards:
		var card: Card = view.card
		end_movable[view] = (card.original_owner == 1 and card.owner == 0)

	var delay := 0.0
	for view in end_down_cards:
		if end_movable.get(view, false):
			var tw := create_tween()
			tw.tween_property(view, "position:y", view.position.y - END_PL_OFFSET_Y, 0.4) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)
			delay += 0.4 * 0.2

	await get_tree().create_timer(delay + 0.45).timeout
	end_pick_interactive = true
	_refresh_end_pick_nav()

func _end_player_pick_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_end_player_pick_click(event.position)
		else:
			_end_player_pick_unclick(event.position)
	elif event is InputEventMouseMotion and end_sel_view != null:
		_end_player_pick_drag(event.position)

func _end_player_pick_click(pos: Vector2) -> void:
	if not end_pick_interactive or end_sel_view != null:
		return

	end_pick_from_up = false
	var found: CardView = null

	for view in end_up_cards:
		if end_movable.get(view, false) and _card_view_contains(view, pos):
			found = view
			end_pick_from_up = true
			break

	if found == null:
		for view in end_down_cards:
			if end_movable.get(view, false) and _card_view_contains(view, pos) and end_remaining > 0:
				found = view
				end_pick_from_up = false
				break

	if found == null:
		return

	if end_result == BattleResult.PLAYER_PERFECT:
		# perfect mode: only allows previewing a card's stats
		_show_end_card_info(found.card)
		_update_owned_panel_pos(found)
		return

	end_sel_view = found
	end_card_start_pos = found.position
	end_drag_start = pos
	if not end_pick_from_up:
		end_sel_original_pos = found.position

	found.z_index = 50
	_show_end_card_info(found.card)
	_update_owned_panel_pos(found)

	if help_arrow.visible:
		help_arrow.visible = false

func _end_player_pick_drag(pos: Vector2) -> void:
	end_sel_view.position = end_card_start_pos + (pos - end_drag_start)
	_update_owned_panel_pos(end_sel_view)

## The "confirm this card" body shared by a mouse drag-into-the-up-row
## (_end_player_pick_unclick's move_up branch) and a pad A-press on a
## down-row pick target (_on_nav_activated's &"pick" branch).
func _end_commit_pick(view: CardView) -> void:
	end_pick_interactive = false
	end_up_cards.append(view)
	end_down_cards.erase(view)
	_relayout_row(end_up_cards, END_PL0_START, END_PL0_WIDTH, 0.3)
	end_remaining -= 1
	_fade_in(button_done, 0.3)
	await get_tree().create_timer(0.3).timeout
	end_pick_interactive = true

## The reverse of _end_commit_pick - sends a previously pad-picked card back
## down. Used only to swap the single pick for a non-perfect win (see the
## &"pick" branch above); the mouse's own un-pick (dragging a card back down)
## has its own move_down branch in _end_player_pick_unclick, since a drag has
## an exact drop position to tween back to that a pad swap never sets.
func _end_uncommit_pick(view: CardView) -> void:
	end_pick_interactive = false
	end_down_cards.append(view)
	end_up_cards.erase(view)
	_relayout_row(end_up_cards, END_PL0_START, END_PL0_WIDTH, 0.3)
	_relayout_row(end_down_cards, END_PL1_START, END_PL1_WIDTH, 0.3)
	end_remaining += 1
	_fade_out(button_done, 0.3)
	await get_tree().create_timer(0.3).timeout
	end_pick_interactive = true

func _end_player_pick_unclick(_pos: Vector2) -> void:
	if end_sel_view == null:
		return

	var view := end_sel_view
	var up_rect := Rect2(END_PL0_START, Vector2(END_PL0_WIDTH, CARD_H))
	var down_rect := Rect2(END_PL1_START, Vector2(END_PL1_WIDTH, CARD_H))
	var card_rect := Rect2(view.position, Vector2(CARD_W, CARD_H))

	var move_up := false
	var move_down := false
	var move_back := false

	if card_rect.intersects(up_rect):
		if end_pick_from_up:
			move_back = true
		else:
			move_up = true
	elif card_rect.intersects(down_rect):
		if end_pick_from_up:
			move_down = true
		else:
			move_back = true
	else:
		move_back = true

	end_pick_interactive = false
	end_sel_view = null

	if move_up:
		await _end_commit_pick(view)
		# Kept in sync with the pad's own tracking (_current_pick_view) so
		# mixing mouse and pad in the same session doesn't leave the pad's
		# swap logic uncommitting a card the mouse actually staged, or
		# vice versa.
		_current_pick_view = view
	elif move_down:
		end_down_cards.append(view)
		end_up_cards.erase(view)
		var tw := create_tween()
		tw.tween_property(view, "position", end_sel_original_pos, 0.2) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_relayout_row(end_up_cards, END_PL0_START, END_PL0_WIDTH, 0.3)
		end_remaining += 1
		_fade_out(button_done, 0.3)
		if view == _current_pick_view:
			_current_pick_view = null
		await get_tree().create_timer(0.2).timeout
	else:
		var tw := create_tween()
		tw.tween_property(view, "position", end_card_start_pos, 0.2) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		await tw.finished

	end_pick_interactive = true

func _fade_in(node: CanvasItem, duration: float) -> void:
	node.visible = true
	var tw := create_tween()
	tw.tween_property(node, "modulate:a", 1.0, duration)

func _fade_out(node: CanvasItem, duration: float) -> void:
	var tw := create_tween()
	tw.tween_property(node, "modulate:a", 0.0, duration)
	tw.tween_callback(func(): node.visible = false)

func _on_end_takeall_pressed() -> void:
	sfx_button.play()
	for view in end_down_cards:
		end_up_cards.append(view)
	end_down_cards.clear()

	_relayout_row(end_up_cards, END_PL0_START, END_PL0_WIDTH, 0.7)

	end_pick_interactive = false
	end_remaining = 0
	_show_end_card_info(null)

	_fade_in(button_done, 0.25)
	_fade_out(button_takeall, 0.25)
	_fade_out(label_central_msg, 0.25)

const COIN_FIRST_BASE := 120
const COIN_FIRST_STEP := 70
const COIN_REMATCH_BASE := 25
const COIN_REMATCH_STEP := 14

# Battles paid nothing at all before this - the only way to ever get a coin
# was selling cards, so a new player sat at 0 with nothing worth selling.
# The first win over an opponent pays the real prize (that's when the money
# is actually needed); every rematch after it pays about a fifth, enough
# that replaying isn't pointless but not enough to farm.
#
# ai.defeated is already the persisted "I've beaten this one" flag, which is
# why this must be called BEFORE _end_player_pick_close sets it - both the
# readout and the actual payout go through here so they can't drift apart.
func _coin_reward() -> int:
	var ai: AIManager.AIData = AIManager.get_ai(Game.opponent_index)
	var reward := (COIN_FIRST_BASE + COIN_FIRST_STEP * Game.opponent_index) if not ai.defeated \
			else (COIN_REMATCH_BASE + COIN_REMATCH_STEP * Game.opponent_index)
	if end_result == BattleResult.PLAYER_PERFECT:
		reward *= 2
	return reward

func _end_player_pick_close() -> void:
	var ai: AIManager.AIData = AIManager.get_ai(Game.opponent_index)
	Game.player.coins += _coin_reward()

	ai.defeated = true
	if Game.opponent_index + 1 < Game.player.available_opponents.size():
		Game.player.available_opponents[Game.opponent_index + 1] = true
	Game.opponent_index = -1

	for view in end_up_cards:
		if end_movable.get(view, false):
			var card: Card = view.card
			if Game.rage_quit_mode:
				Game.player.add_captured_rage_quit_card(card)
			else:
				Game.player.add_captured_card(card)
			AIManager.remove_card(ai, card)

	Game.player.match_started = false
	Game.player.matches_won += 1
	SaveSystem.save_player(Game.player)
	busy_spinner.visible = false
	_return_to_main_menu()

# ------------------------------------------------------------ end: CPU pick

func gsEndCPUPick_Set(result: BattleResult) -> void:
	end_flow = EndFlow.CPU_PICK
	end_result = result
	end_cpu_sel_view = null
	end_cpu_pick_mode = false
	end_cpu_total_picks = float(randi_range(40, 49))
	end_cpu_cur_pick = end_cpu_total_picks

	if result == BattleResult.CPU_PERFECT:
		label_central_msg.text = StringTable.get_string(StringTable.ID_MSG_CPU_PICK_5_CARD)
		label_central_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel_info.visible = false
	else:
		label_central_msg.text = StringTable.get_string(StringTable.ID_MSG_CPU_PICK_1_CARD)

	label_central_msg.visible = true
	label_central_msg.modulate.a = 0.0
	var tw_msg := create_tween()
	tw_msg.tween_property(label_central_msg, "modulate:a", 1.0, 1.5)

	end_movable.clear()
	for view in end_up_cards:
		var card: Card = view.card
		end_movable[view] = (card.original_owner == 0 and card.owner == 1)

	end_cpu_pickable.clear()
	for view in end_up_cards:
		if end_movable.get(view, false):
			end_cpu_pickable.append(view)

	if end_cpu_pickable.size() == 1:
		end_cpu_cur_pick = 4.0
		end_cpu_total_picks = 4.0

	var delay := 0.0
	for view in end_up_cards:
		if end_movable.get(view, false):
			var tw := create_tween()
			tw.tween_property(view, "position:y", view.position.y - END_PL_OFFSET_Y, 0.4) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)
			delay += 0.4 * 0.2

	await get_tree().create_timer(delay + 0.45).timeout

	if result == BattleResult.CPU_WINS:
		end_cpu_pick_mode = true
		_end_cpu_pick_roulette()
	else:
		_end_cpu_pick_setup_move()

# Slot-machine-style reveal: curPick decays 1% per rendered frame (same
# per-frame math as gsEndCPUPick.cs's OnUpdate, so it's frame-rate coupled
# there too, not a deviation) cycling through the pickable cards faster and
# faster until it settles on one.
func _end_cpu_pick_roulette() -> void:
	while end_cpu_pick_mode:
		end_cpu_cur_pick *= 0.9801  # 0.99 squared - decays twice as fast, half the reveal time
		var val: int = int(end_cpu_total_picks - end_cpu_cur_pick)
		var sel: CardView = end_cpu_pickable[val % end_cpu_pickable.size()]

		image_arrow.visible = true
		image_arrow.position = Vector2(sel.position.x + CARD_W / 2.0 - image_arrow.size.x / 2.0, sel.position.y + CARD_H)

		if end_cpu_sel_view != sel:
			_show_end_card_info(sel.card)
			panel_owned.visible = false
			end_cpu_sel_view = sel

		if end_cpu_cur_pick <= 2.0:
			end_cpu_pick_mode = false
			await get_tree().create_timer(0.3).timeout
			_end_cpu_pick_setup_move()
			return

		await get_tree().process_frame

func _end_cpu_pick_setup_move() -> void:
	var mov_time: float

	if end_result == BattleResult.CPU_PERFECT:
		for view in end_up_cards:
			end_down_cards.append(view)
		end_up_cards.clear()
		mov_time = 0.8
	else:
		end_down_cards.append(end_cpu_sel_view)
		end_up_cards.erase(end_cpu_sel_view)
		mov_time = 1.0

	_relayout_row(end_down_cards, END_PL1_START, END_PL1_WIDTH, mov_time)

	image_arrow.visible = false
	_fade_in(button_done, mov_time)

func _end_cpu_pick_close() -> void:
	var ai: AIManager.AIData = AIManager.get_ai(Game.opponent_index)

	for view in end_down_cards:
		if end_movable.get(view, false):
			if not Game.rage_quit_mode:
				AIManager.add_captured_card(ai, view.card)
			Game.player.remove_card(view.card)

	Game.player.match_started = false
	SaveSystem.save_player(Game.player)
	busy_spinner.visible = false
	_return_to_main_menu()

# --------------------------------------------------------------- end: draw

func gsEndNonePick_Set() -> void:
	end_flow = EndFlow.DRAW

	label_central_msg.text = StringTable.get_string(StringTable.ID_BATTLE_END_DRAW)
	label_central_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel_info.visible = false

	label_central_msg.visible = true
	label_central_msg.modulate.a = 0.0
	_fade_in(label_central_msg, 1.5)
	_fade_in(button_done, 1.5)

func _end_none_pick_close() -> void:
	Game.player.match_started = false
	SaveSystem.save_player(Game.player)
	busy_spinner.visible = false
	_return_to_main_menu()
