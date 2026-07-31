extends Control
## 1:1-ish port of Scenes/Battle/BattleScene.cs and its gs*.cs state files
## (960x544 design canvas, same coordinates/timings). Method names keep the
## gsXxx_Set/OnInput/Update prefixes from the original files they replace, so
## it's easy to grep prj_psvita/Scenes/Battle/gsXxx.cs and find the matching
## code here. Godot doesn't need PS Vita's manual per-frame state machine or
## its custom Events/Tween system, so the state transitions themselves are
## expressed as a linear chain of `await`s and native Tweens instead.
##
## Not ported: gsEndLevelUp / gsEndPlayerPick / gsEndCPUPick / gsEndNonePick.
## Those are a post-battle card-picking mini-game against the player's/AI's
## persistent card collections (AIManager save data, SaveSystem) - this is a
## single-skirmish port with no save/collection system, so gsEndStart's
## banner+card animation is kept but resolves straight to a result screen.

const SCREEN_W := 960
const SCREEN_H := 544
const CARD_W := 96
const CARD_H := 128
const ASSETS := "res://assets/"

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

# BattleScene.cs's small opponent-hand stack (quadPlayer1Cards).
const OPPONENT_STACK_POS := Vector2(25, 240)
const OPPONENT_STACK_STEP := 35.0
const OPPONENT_CARD_SCALE := 0.45

# gsBattle.cs timings.
const BATTLE_RUMBLE_TIME := 0.6
const BATTLE_COUNTDOWN_TIME := 1.5
const BATTLE_RUMBLE_DISTANCE := 16.0

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
var board_targets: Array = []     # [row][col] -> TextureRect (sel-target overlay)
var board_hover_glow: TextureRect

var hand_slots: Array = []        # size 5 -> Button

var opponent_stack: Control
var turn_cursor: TextureRect
var name_labels: Array = []
var score_value_labels: Array = []
var status_label: Label

var info_name: Label
var info_attack_val: Label
var info_type_val: Label
var info_pdef_val: Label
var info_mdef_val: Label

var combo_label: Label
var battle_value_labels: Array = []  # 2 Labels
var blink_labels: Array = []         # 2 Labels
var vfx_sprites := {}                # Card.AttackType -> AnimatedSprite2D
var coin_sprite: TextureRect
var coin_blue_tex: Texture2D
var coin_red_tex: Texture2D

var end_panel: Control
var end_bkg: TextureRect
var end_banner: TextureRect
var end_label: Label
var end_restart: Button

var sfx_button: AudioStreamPlayer
var sfx_place: AudioStreamPlayer
var sfx_attack_p: AudioStreamPlayer
var sfx_attack_m: AudioStreamPlayer
var music: AudioStreamPlayer

var font_stylish: Font = load("res://assets/fonts/font_stylish.ttf")
var font_info: Font = load("res://assets/fonts/font_info.ttf")

func _ready() -> void:
	board = Board.new()
	_build_ui()
	start_new_game()

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

	player_hand = CardManager.generate_playable_deck(5)
	cpu_hand = CardManager.generate_playable_deck(5)
	for c in cpu_hand:
		c.owner = 1
		c.original_owner = 1

	busy = false
	_show_card_info(null)
	_refresh_hands()
	_refresh_scores()
	status_label.text = ""

	music.play()
	gsCoinToss_Set()

# ---------------------------------------------------------------- UI build

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := TextureRect.new()
	bg.texture = load(ASSETS + "battle/battle_screen.png")
	bg.position = Vector2.ZERO
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	add_child(bg)

	var pergamena := TextureRect.new()
	pergamena.texture = load(ASSETS + "battle/battle_pergamena.png")
	pergamena.position = Vector2(0, 4)
	pergamena.size = Vector2(280, 282)
	add_child(pergamena)

	var marmo := TextureRect.new()
	marmo.texture = load(ASSETS + "battle/battle_marmo.png")
	marmo.position = Vector2(14, 282)
	marmo.size = Vector2(248, 256)
	add_child(marmo)

	turn_cursor = TextureRect.new()
	turn_cursor.texture = load(ASSETS + "battle/battle_cursor.png")
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
	_build_status_label()
	_build_battle_overlay()
	_build_end_panel()
	_build_audio()

func _build_player_panel(idx: int, y: int, color: Color) -> void:
	var name_label := Label.new()
	name_label.position = Vector2(60, y)
	name_label.add_theme_font_override("font", font_stylish)
	name_label.add_theme_font_size_override("font_size", 26)
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
	score_caption.add_theme_font_size_override("font_size", 18)
	score_caption.add_theme_color_override("font_color", color)
	score_caption.text = "Score"
	add_child(score_caption)

	var score_value := Label.new()
	score_value.position = Vector2(184, y + 51)
	score_value.add_theme_font_override("font", font_stylish)
	score_value.add_theme_font_size_override("font_size", 18)
	score_value.add_theme_color_override("font_color", color)
	score_value.text = "0"
	add_child(score_value)
	score_value_labels.append(score_value)

func _build_card_info_panel() -> void:
	var black := Color(0, 0, 0)

	info_name = Label.new()
	info_name.position = Vector2(14, 340)
	info_name.size = Vector2(248, 24)
	info_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_name.add_theme_font_override("font", font_info)
	info_name.add_theme_font_size_override("font_size", 18)
	info_name.add_theme_color_override("font_color", black)
	add_child(info_name)

	var rows := [
		["Attack", 376], ["Type", 410], ["P.Def", 444], ["M.Def", 478],
	]
	var value_labels := []
	for row in rows:
		var caption := Label.new()
		caption.position = Vector2(32, row[1])
		caption.add_theme_font_override("font", font_info)
		caption.add_theme_font_size_override("font_size", 15)
		caption.add_theme_color_override("font_color", black)
		caption.text = row[0]
		add_child(caption)

		var value := Label.new()
		value.position = Vector2(200, row[1])
		value.add_theme_font_override("font", font_info)
		value.add_theme_font_size_override("font_size", 15)
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
			block.position = pos
			block.size = Vector2(CARD_W, CARD_H)
			block.visible = false
			block.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(block)
			block_row.append(block)

			var target := TextureRect.new()
			target.texture = load(ASSETS + "cards/card_sel_target.png")
			target.position = pos
			target.size = Vector2(CARD_W, CARD_H)
			target.visible = false
			target.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(target)
			target_row.append(target)

		board_slots.append(slot_row)
		board_card_views.append(view_row)
		board_blocks.append(block_row)
		board_targets.append(target_row)

	board_hover_glow = TextureRect.new()
	board_hover_glow.texture = load(ASSETS + "cards/card_sel_glow.png")
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

func _build_status_label() -> void:
	status_label = Label.new()
	status_label.position = Vector2(282, 500)
	status_label.size = Vector2(404, 30)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_override("font", font_info)
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color.WHITE)
	status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	status_label.add_theme_constant_override("outline_size", 3)
	add_child(status_label)

func _build_battle_overlay() -> void:
	# combo text (textCombo)
	combo_label = Label.new()
	combo_label.add_theme_font_override("font", font_stylish)
	combo_label.add_theme_font_size_override("font_size", 30)
	combo_label.add_theme_color_override("font_color", Color(1, 1, 0))
	combo_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	combo_label.add_theme_constant_override("shadow_offset_x", 1)
	combo_label.add_theme_constant_override("shadow_offset_y", 1)
	combo_label.visible = false
	add_child(combo_label)

	# battle numbers + blinking attack-type letter (textCardBattleValues / textCardBlinkLetters)
	for i in 2:
		var value_label := Label.new()
		value_label.add_theme_font_override("font", font_stylish)
		value_label.add_theme_font_size_override("font_size", 20)
		value_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		value_label.visible = false
		add_child(value_label)
		battle_value_labels.append(value_label)

		var blink_label := Label.new()
		blink_label.add_theme_font_override("font", font_stylish)
		blink_label.add_theme_font_size_override("font_size", 15)
		blink_label.add_theme_color_override("font_color", Color(1, 0, 0))
		blink_label.visible = false
		add_child(blink_label)
		blink_labels.append(blink_label)

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
	end_bkg.size = Vector2(SCREEN_W, SCREEN_H)
	end_bkg.position = Vector2(0, -SCREEN_H)
	end_panel.add_child(end_bkg)

	end_banner = TextureRect.new()
	end_banner.visible = false
	end_panel.add_child(end_banner)

	end_label = Label.new()
	end_label.position = Vector2((SCREEN_W - 300) / 2.0, 460)
	end_label.size = Vector2(300, 30)
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_label.add_theme_font_override("font", font_stylish)
	end_label.add_theme_font_size_override("font_size", 20)
	end_label.visible = false
	end_panel.add_child(end_label)

	end_restart = Button.new()
	end_restart.text = "Play again"
	end_restart.position = Vector2((SCREEN_W - 120) / 2.0, 500)
	end_restart.size = Vector2(120, 32)
	end_restart.visible = false
	end_restart.pressed.connect(start_new_game)
	end_panel.add_child(end_restart)

func _build_audio() -> void:
	sfx_button = _make_sfx("sfx/button_sound.wav")
	sfx_place = _make_sfx("sfx/place_card.wav")
	sfx_attack_p = _make_sfx("sfx/attack_p.wav")
	sfx_attack_m = _make_sfx("sfx/attack_m.wav")

	music = AudioStreamPlayer.new()
	music.stream = load(ASSETS + "music/battle1.mp3")
	music.volume_db = -8.0
	add_child(music)

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
	for i in idle_count:
		var back := TextureRect.new()
		back.texture = back_tex
		back.position = OPPONENT_STACK_POS + Vector2(i * OPPONENT_STACK_STEP, 0)
		back.size = Vector2(CARD_W, CARD_H) * OPPONENT_CARD_SCALE
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
		board_targets[c.row][c.col].visible = on

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
	info_name.add_theme_color_override("font_color", COLOR_P0 if card.owner == 0 else COLOR_P1)

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

	active_player = 0 if player0_wins else 1
	if active_player == 0:
		gsPlayerTurn_Set()
	else:
		gsCPUTurn_Set()

# --------------------------------------------------------------- player turn

func gsPlayerTurn_Set() -> void:
	active_player = 0
	busy = false
	status_label.text = "Your turn"
	turn_cursor.visible = true
	var tw := create_tween()
	tw.tween_property(turn_cursor, "position:y", 23.0, 0.35) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

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
	_update_drag_ghost_pos(get_global_mouse_position())

func _input(event: InputEvent) -> void:
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
	if cell.x >= 0 and board.is_playable(cell.x, cell.y):
		board_hover_glow.position = _board_cell_pos(cell.x, cell.y)
		board_hover_glow.visible = true
	else:
		board_hover_glow.visible = false

func gsCardPicking_Release(mouse_pos: Vector2) -> void:
	var cell := _slot_under_point(mouse_pos)
	drag_ghost.queue_free()
	drag_ghost = null
	board_hover_glow.visible = false
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
	status_label.text = "CPU's turn"
	var tw := create_tween()
	tw.tween_property(turn_cursor, "position:y", 125.0, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(0.5).timeout

	var live_cpu_hand: Array = cpu_hand.filter(func(c): return c != null)
	var move := GsCPUTurn.choose_move(board, live_cpu_hand)
	var card: Card = move["card"]
	var row: int = move["row"]
	var col: int = move["col"]

	# fly a face-down mini card from the opponent stack to the board slot,
	# then flip it to reveal the real card (gsCPUTurn.cs's quadPlayer1Cards
	# move+rotate, simplified to one ghost instead of a paired UI+real card).
	var idle_count := live_cpu_hand.size()
	var ghost := TextureRect.new()
	ghost.texture = load(ASSETS + "cards/card_back.png")
	ghost.position = OPPONENT_STACK_POS + Vector2((idle_count - 1) * OPPONENT_STACK_STEP, 0)
	ghost.size = Vector2(CARD_W, CARD_H) * OPPONENT_CARD_SCALE
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

# Ports gsPreBattle.cs -> gsBattleCheck.cs -> gsBattle.cs -> (combo) ->
# gsBattleCheck.cs, collapsed into one recursive coroutine.
func gsPreBattle_Set(last_placed: Card) -> void:
	await get_tree().create_timer(0.15).timeout

	for target in board.get_capturable_cards(last_placed):
		await captureCardProcedure(last_placed, target, false)

	await gsBattleCheck_Set(last_placed)

func gsBattleCheck_Set(last_placed: Card) -> void:
	var fightable := board.get_adjacent_battle_cards(last_placed)
	if fightable.is_empty():
		return
	elif fightable.size() == 1:
		await gsBattle_Set(last_placed, fightable[0])
	else:
		var target := await gsBattleSelTarget_Set(last_placed, fightable)
		await gsBattle_Set(last_placed, target)

func gsBattleSelTarget_Set(last_placed: Card, candidates: Array) -> Card:
	_highlight_targets(candidates, true)

	var chosen: Card
	if last_placed.owner == 0:
		status_label.text = "Choose a card to battle"
		target_mode = true
		target_candidates = candidates
		chosen = await target_chosen
		target_mode = false
		target_candidates = []
	else:
		await get_tree().create_timer(0.7).timeout
		chosen = GsCPUTurn.choose_battle_target(last_placed, candidates)

	_highlight_targets(candidates, false)
	return chosen

func _on_slot_pressed(row: int, col: int) -> void:
	if target_mode:
		var card: Card = board.slots[row][col]
		if card != null and target_candidates.has(card):
			target_chosen.emit(card)

# ------------------------------------------------------------------- battle

func gsBattle_Set(card0: Card, card1: Card) -> void:
	var result := GsBattle.resolve_battle(card0, card1)
	status_label.text = ""

	await gsBattle_StartRumble(card0, card1, result)
	await gsBattle_Countdown(card0, card1, result)
	await gsBattle_End(card0, card1, result)

func gsBattle_StartRumble(card0: Card, card1: Card, result: Dictionary) -> void:
	var view0: CardView = board_card_views[card0.row][card0.col]
	var view1: CardView = board_card_views[card1.row][card1.col]
	var pos0 := _board_cell_pos(card0.row, card0.col)
	var pos1 := _board_cell_pos(card1.row, card1.col)
	var vec := (pos1 - pos0).normalized()

	# battle values + blinking letters
	for i in 2:
		battle_value_labels[i].visible = true
	blink_labels[0].text = card0.stat_text()[result["letter0"]]
	blink_labels[1].text = card1.stat_text()[result["letter1"]]
	_position_battle_labels(pos0, pos1)
	_blink_loop_start()

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

func _position_battle_labels(pos0: Vector2, pos1: Vector2) -> void:
	battle_value_labels[0].position = pos0 + Vector2(CARD_W, CARD_H) / 2.0 - Vector2(10, 30)
	battle_value_labels[1].position = pos1 + Vector2(CARD_W, CARD_H) / 2.0 - Vector2(10, 30)
	blink_labels[0].position = pos0 + Vector2(8, CARD_H - 22)
	blink_labels[1].position = pos1 + Vector2(8, CARD_H - 22)

var _blinking := false

func _blink_loop_start() -> void:
	_blinking = true
	_blink_loop()

func _blink_loop() -> void:
	var on := true
	while _blinking:
		blink_labels[0].visible = on
		blink_labels[1].visible = on
		on = not on
		await get_tree().create_timer(0.1).timeout

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

func gsBattle_End(card0: Card, card1: Card, result: Dictionary) -> void:
	_blinking = false
	for i in 2:
		battle_value_labels[i].visible = false
		blink_labels[i].visible = false

	var view0: CardView = board_card_views[card0.row][card0.col]
	var view1: CardView = board_card_views[card1.row][card1.col]
	if is_instance_valid(view0):
		view0.position = Vector2.ZERO
	if is_instance_valid(view1):
		view1.position = Vector2.ZERO

	var winner: Card = result["winner"]
	if winner == null:
		status_label.text = "Draw!"
		await get_tree().create_timer(0.3).timeout
		return

	var loser: Card = result["loser"]
	await captureCardProcedure(winner, loser, true)

	var last_placed: Card = card0
	if winner == last_placed:
		var combo := board.get_combo_cards(loser)
		if not combo.is_empty():
			if winner.original_owner == 0:
				await _show_combo_text(winner, combo.size())
			for c in combo:
				await captureCardProcedure(winner, c, true)
		await gsBattleCheck_Set(last_placed)

# --------------------------------------------------------------- captures

# Ports captureCardProcedure(): the original flips the captured card+a
# temporary card-back overlay by 180 degrees and swaps ownership at the
# midpoint. Godot's 2D canvas has no real Y-rotation, so this fakes the
# same flip with a scale_x 1 -> 0 -> 1 tween and rebuilds the CardView with
# the new owner's colors at the midpoint.
func captureCardProcedure(attacker: Card, captured: Card, from_battle: bool) -> void:
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

func _show_combo_text(winner: Card, count: int) -> void:
	var pos := _board_cell_pos(winner.row, winner.col) + Vector2(CARD_W, CARD_H) / 2.0
	combo_label.text = "Combo x%d" % count
	combo_label.position = pos - Vector2(50, 40)
	combo_label.modulate.a = 0.0
	combo_label.visible = true

	var tw := create_tween()
	tw.tween_property(combo_label, "modulate:a", 1.0, 0.3)
	tw.parallel().tween_property(combo_label, "position:x", pos.x, 0.3)
	tw.tween_interval(0.6)
	tw.tween_property(combo_label, "modulate:a", 0.0, 0.3)
	await tw.finished
	combo_label.visible = false

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
	status_label.text = ""

	var p0 := board.count_cards(0)
	var p1 := board.count_cards(1)
	var result: BattleResult
	var banner_path: String
	var label_text: String

	if p0 > p1 and p0 == 10:
		result = BattleResult.PLAYER_PERFECT
		banner_path = "battle/battle_perfect.png"
		label_text = "Perfect! %d - %d" % [p0, p1]
	elif p0 > p1:
		result = BattleResult.PLAYER_WINS
		banner_path = "battle/battle_win.png"
		label_text = "You win! %d - %d" % [p0, p1]
	elif p1 > p0 and p1 == 10:
		result = BattleResult.CPU_PERFECT
		banner_path = "battle/battle_lose.png"
		label_text = "CPU wins (perfect). %d - %d" % [p0, p1]
	elif p1 > p0:
		result = BattleResult.CPU_WINS
		banner_path = "battle/battle_lose.png"
		label_text = "CPU wins. %d - %d" % [p0, p1]
	else:
		result = BattleResult.DRAW
		banner_path = "battle/battle_draw.png"
		label_text = "Draw. %d - %d" % [p0, p1]

	end_panel.visible = true
	music.stop()

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

	end_label.text = label_text
	end_label.visible = true
	end_restart.visible = true

func _move_cards_to_end_rows() -> void:
	var up_cards: Array = []    # originally the player's cards
	var down_cards: Array = []  # originally the CPU's cards

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
				up_cards.append(view)
			else:
				down_cards.append(view)

	var tw := create_tween()
	tw.set_parallel(true)
	for i in up_cards.size():
		var x := END_PL0_START.x + i * (CARD_W + END_PL_OFFSET_X)
		tw.tween_property(up_cards[i], "position", Vector2(x, END_PL0_START.y), 1.0) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in down_cards.size():
		var x := END_PL1_START.x + i * (CARD_W + END_PL_OFFSET_X)
		tw.tween_property(down_cards[i], "position", Vector2(x, END_PL1_START.y), 1.0) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished
