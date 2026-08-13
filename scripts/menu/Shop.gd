extends Control
## Port of ShopScene.cs / UIShop.cs / UIShop.composer.cs + gsWaitingInput/
## gsDeckScroll/gsDragCard (960x544 design canvas). Reuses DeckSelectorWheel
## (the single left carousel, useFavourite=false/useAll=true/shopMode=true)
## and SelectionOutline from the DeckSelect port - same carousel widget,
## same input-routing shape (WaitingInput/DeckScroll/DragCard), just one
## wheel and one card slot instead of two wheels and a 5-slot lower deck.
##
## Label_ShopCardText0..3 are never actually assigned any text anywhere in
## the reference (grep confirms `card.text` is a dead field, always the
## composer's design-time placeholder in a real build) - left blank here to
## match observed behavior rather than the never-executed composer text.

const SCREEN_W := 960
const SCREEN_H := 544
const ASSETS := "res://assets/"
const CARD_W := 96
const CARD_H := 128
const GET_BACK_TIME := 0.1
# label_shop reuses button_shop.png's "two icon halves + transparent gap"
# trick at this screen's icon size (214x56, scale 0.5 vs native 428x112):
# native gap 276px * 0.5 = 138px on-screen.
const TITLE_ICON_GAP_WIDTH := 138.0

# Per shop-card-slot index, the [min,max] card definitionId range to generate
# from. Whether a slot is visible at all, and how far up its range actually
# reaches, come from _shop_def_cap() - not from this table. The reference
# folded both meanings into these same two numbers by reading them as
# availableOpponents indices as well, which doesn't hold up: card ids and
# opponent indices aren't the same namespace (opponent 16 is The Void, whose
# card is id 19).
#
# Nothing above Kraken Queen (15) is ever sold: Lich, Odin, Dragon, The Void
# and Rage Quit are capture-only rewards.
const GEN_TABLE := [
	[0, 2],    # Slime..Ghost
	[2, 5],    # Ghost..Goblin Sciaman
	[5, 8],    # Goblin Sciaman..Ginger
	[8, 11],   # Ginger..Minotaur
	[10, 13],  # Pegasus..Elementals
	[12, 15],  # Griffin..Kraken Queen
]

# Cards sell for price/3 but buy back at price/2. Buyback MUST stay the more
# expensive of the two: if selling ever paid at least what buying back costs,
# sell-then-rebuy would be an infinite coin generator. At 3 and 2 the round
# trip loses price/6.
const SELL_DIVISOR := 3
const BUYBACK_DIVISOR := 2

# The shop restocks every this many wins instead of every 24 real hours. A
# long session no longer finds the shop frozen, restocking is tied to
# progress rather than the wall clock, and changing the system date stops
# being an exploit.
const RESTOCK_WINS := 3

# Six slots at a 45px pitch fit the 115..385 band left between the offer
# column's top and the buyback card/button row at y 391.
const SHOP_CARD_PANEL_POS := [
	Vector2(636, 115), Vector2(636, 160), Vector2(636, 205),
	Vector2(636, 250), Vector2(636, 295), Vector2(636, 340),
]
const SHOP_CARD_PANEL_SIZE := Vector2(306, 43)
const SHOP_CARD_IMAGE_POS := Vector2(4, 1)
const SHOP_CARD_IMAGE_SIZE := Vector2(30, 40)  # keeps the 96x128 card aspect
const SHOP_CARD_PRICE_POS := Vector2(167, 1)
const SHOP_CARD_PRICE_SIZE := Vector2(124, 41)
const BUYBACK_SIZE := Vector2(40, 54)

enum GameState { WAITING_INPUT, DECK_SCROLL, DRAG_CARD }

var game_state: GameState = GameState.WAITING_INPUT
var game_state_mode: int = 0
var next_sel: int = 0  # 0 none, 1 wheel, 2 card_slot, 3 buyback, 4 shop_card

var deck_selector := DeckSelectorWheel.new()

var panel_left: Control
var panel_card_slot: Control
var card_slot_placeholder: TextureRect
var card_slot_view: CardView

var label_coins: Label
var label_buy_value: Label
var label_sell_value: Label
var button_sell: Button
var button_buy: Button
var button_buy_back: Button
var image_buyback_card: CardView
var busy_spinner: BusySpinner
var selection_outline: SelectionOutline
var drag_ghost: CardView

var label_info_name: Label
var label_value_offense: Label
var label_value_type: Label
var label_value_pdef: Label
var label_value_mdef: Label

# One entry per GEN_TABLE slot, all filled by the build loop in _build_ui().
var shop_card_panels: Array = []        # Control
var shop_card_views: Array = []         # CardView
var shop_card_price_labels: Array = []  # Label
var shop_cards: Array = []              # Card or null
var shop_cards_active: Array = []       # bool
var shop_cards_time: Array = []         # float: matches_won when this slot was rolled

var cur_sell_card: Card = null
var cur_buy_card: Card = null
var buy_back_card: Card = null
var last_chosen_shop_card_index := -1

var sfx_button: AudioStreamPlayer
var sfx_back: AudioStreamPlayer
var sfx_sell: AudioStreamPlayer
var sfx_buy: AudioStreamPlayer

# --- WaitingInput state ---
var wi_x: int = 0
var wi_y: int = 0
var wi_active := false

# --- DeckScroll state ---
var ds_elapsed: float = 0.0
var ds_start_angle: float = 0.0
var ds_diff: float = 0.0
var ds_moving_vert: bool = false
var ds_cur_card_stats: Card = null

# --- DragCard state ---
var dc_from_left := false
var dc_from_right := false
var dc_from_slot := false
var dc_index := -1
var dc_start_x: int = 0
var dc_start_y: int = 0
var dc_card_pos: Vector2 = Vector2.ZERO
var dc_ghost_size: Vector2 = Vector2(CARD_W, CARD_H)
var dc_dragged_card: Card = null
var dc_get_back_tween: Tween = null

var _pointer_down := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	for card in Game.player.cards:
		card.is_on_deck = false

	_build_ui()

	deck_selector.init(panel_left, Game.player.cards, false, true, true)

	_load_shop_cards()
	for i in GEN_TABLE.size():
		_setup_shop_card(i, false)

	label_coins.text = str(Game.player.coins)

	_enter_waiting_input()

# ---------------------------------------------------------------- UI build

func _build_ui() -> void:
	var font_stylish: Font = Game.font_stylish

	var bg := TextureRect.new()
	bg.texture = load(ASSETS + "common_bkg_clean.png")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	add_child(bg)

	panel_left = Control.new()
	panel_left.position = Vector2(10, 82)
	panel_left.size = Vector2(348, 348)
	panel_left.clip_contents = true
	panel_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel_left)

	var symbol := TextureRect.new()
	symbol.texture = load(ASSETS + "common_symbol_a.png")
	symbol.stretch_mode = TextureRect.STRETCH_SCALE
	symbol.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	symbol.size = Vector2(348, 348)
	symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_left.add_child(symbol)

	panel_card_slot = Control.new()
	panel_card_slot.position = Vector2(432, 391)
	panel_card_slot.size = Vector2(CARD_W, CARD_H)
	panel_card_slot.clip_contents = true
	panel_card_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slot_bg := ColorRect.new()
	slot_bg.color = Color(153.0 / 255.0, 153.0 / 255.0, 153.0 / 255.0, 127.0 / 255.0)
	slot_bg.size = Vector2(CARD_W, CARD_H)
	slot_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_card_slot.add_child(slot_bg)
	add_child(panel_card_slot)

	card_slot_placeholder = TextureRect.new()
	card_slot_placeholder.texture = load(ASSETS + "common_transp_box_single.png")
	card_slot_placeholder.stretch_mode = TextureRect.STRETCH_SCALE
	card_slot_placeholder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_slot_placeholder.size = Vector2(CARD_W, CARD_H)
	card_slot_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_card_slot.add_child(card_slot_placeholder)

	card_slot_view = CardView.new()
	card_slot_view.visible = false
	card_slot_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_card_slot.add_child(card_slot_view)

	button_buy_back = _make_button(StringTable.get_string(StringTable.ID_BUY_BACK), Vector2(744, 391), Vector2(156, 54), font_stylish)
	button_buy_back.visible = false
	button_buy_back.pressed.connect(_on_buyback_pressed)

	var label_shop_help := _make_label(Vector2(0, 79), Vector2(959, 34), font_stylish, 20)
	label_shop_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_shop_help.text = StringTable.get_string(StringTable.ID_SHOP_HELP)
	add_child(label_shop_help)
	UIButtonStyle.fit_button_text(label_shop_help)

	# font_size 36 to match every other screen's Back button (DeckSelect,
	# Opponents, Options) - this helper's other buttons stay at the default
	# 25, tuned for their own tighter boxes.
	var back_button := _make_button(StringTable.get_string(StringTable.ID_BACK), Vector2(42, 463), Vector2(115, 56), font_stylish, 36)
	back_button.pressed.connect(_on_back_pressed)

	var label_shop := _make_label(Vector2(348, 21), Vector2(264, 47), font_stylish, 46)
	label_shop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_shop.text = StringTable.get_string(StringTable.ID_SHOP)
	add_child(label_shop)
	UIButtonStyle.fit_menu_button_text(label_shop, TITLE_ICON_GAP_WIDTH)

	var label_sell := _make_label(Vector2(67, 32), Vector2(214, 36), font_stylish, 36)
	label_sell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_sell.text = StringTable.get_string(StringTable.ID_SELL)
	add_child(label_sell)
	UIButtonStyle.fit_button_text(label_sell)

	var label_buy := _make_label(Vector2(679, 32), Vector2(214, 36), font_stylish, 36)
	label_buy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_buy.text = StringTable.get_string(StringTable.ID_BUY)
	add_child(label_buy)
	UIButtonStyle.fit_button_text(label_buy)

	UIShadow.behind(self, Vector2(867, 463), Vector2(60, 60))
	var coins_icon := TextureRect.new()
	coins_icon.texture = load(ASSETS + "coins_icon.png")
	coins_icon.position = Vector2(867, 463)
	coins_icon.size = Vector2(60, 60)
	coins_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	add_child(coins_icon)

	label_coins = _make_label(Vector2(711, 477), Vector2(156, 46), font_stylish, 36)
	label_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(label_coins)

	label_buy_value = _make_label(Vector2(530, 473), Vector2(123, 46), font_stylish, 46)
	label_buy_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_buy_value.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label_buy_value.text = "---"
	add_child(label_buy_value)

	label_sell_value = _make_label(Vector2(309, 473), Vector2(119, 46), font_stylish, 46)
	label_sell_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_sell_value.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label_sell_value.text = "---"
	add_child(label_sell_value)

	var image_shop_icon := TextureRect.new()
	image_shop_icon.texture = load(ASSETS + "button_shop.png")
	image_shop_icon.stretch_mode = TextureRect.STRETCH_SCALE
	image_shop_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image_shop_icon.position = Vector2(372, 16)
	image_shop_icon.size = Vector2(214, 56)
	image_shop_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image_shop_icon)

	var info_bkg := TextureRect.new()
	info_bkg.texture = load(ASSETS + "common_transp_box_a.png")
	info_bkg.stretch_mode = TextureRect.STRETCH_SCALE
	info_bkg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	info_bkg.position = Vector2(364, 117)
	info_bkg.size = Vector2(260, 252)
	add_child(info_bkg)

	label_info_name = _make_label(Vector2(373, 129), Vector2(242, 41), font_stylish, 36)
	label_info_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_info_name.text = StringTable.get_string(StringTable.ID_CARD_STATS)
	add_child(label_info_name)
	UIButtonStyle.fit_button_text(label_info_name)

	var info_offense_lbl := _make_label(Vector2(373, 172), Vector2(174, 41), font_stylish, 36)
	info_offense_lbl.text = StringTable.get_string(StringTable.ID_CARD_ATTACK)
	add_child(info_offense_lbl)
	UIButtonStyle.fit_button_text(info_offense_lbl)
	label_value_offense = _make_label(Vector2(505, 172), Vector2(108, 41), font_stylish, 36)
	label_value_offense.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_value_offense.text = "- - -"
	add_child(label_value_offense)

	var info_type_lbl := _make_label(Vector2(373, 220), Vector2(174, 41), font_stylish, 36)
	info_type_lbl.text = StringTable.get_string(StringTable.ID_CARD_TYPE)
	add_child(info_type_lbl)
	UIButtonStyle.fit_button_text(info_type_lbl)
	label_value_type = _make_label(Vector2(507, 220), Vector2(108, 41), font_stylish, 36)
	label_value_type.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_value_type.text = "---"
	add_child(label_value_type)

	var info_pdef_lbl := _make_label(Vector2(373, 268), Vector2(169, 41), font_stylish, 36)
	info_pdef_lbl.text = StringTable.get_string(StringTable.ID_CARD_PHYSICAL_DEFENSE)
	add_child(info_pdef_lbl)
	UIButtonStyle.fit_button_text(info_pdef_lbl)
	label_value_pdef = _make_label(Vector2(505, 268), Vector2(108, 41), font_stylish, 36)
	label_value_pdef.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_value_pdef.text = "- - -"
	add_child(label_value_pdef)

	var info_mdef_lbl := _make_label(Vector2(373, 315), Vector2(169, 41), font_stylish, 36)
	info_mdef_lbl.text = StringTable.get_string(StringTable.ID_CARD_MAGICAL_DEFENSE)
	add_child(info_mdef_lbl)
	UIButtonStyle.fit_button_text(info_mdef_lbl)
	label_value_mdef = _make_label(Vector2(505, 315), Vector2(108, 41), font_stylish, 36)
	label_value_mdef.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_value_mdef.text = "- - -"
	add_child(label_value_mdef)

	button_sell = _make_button(StringTable.get_string(StringTable.ID_SELL_PRICE), Vector2(309, 417), Vector2(119, 54), font_stylish)
	button_sell.disabled = true
	button_sell.pressed.connect(_on_sell_pressed)

	button_buy = _make_button(StringTable.get_string(StringTable.ID_BUY_PRICE), Vector2(534, 417), Vector2(119, 54), font_stylish)
	button_buy.disabled = true
	button_buy.pressed.connect(_on_buy_pressed)

	image_buyback_card = CardView.new()
	image_buyback_card.position = Vector2(694, 391)
	image_buyback_card.scale = Vector2(40, 54) / Vector2(CARD_W, CARD_H)
	image_buyback_card.visible = false
	image_buyback_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image_buyback_card)

	for i in GEN_TABLE.size():
		var panel := Control.new()
		panel.position = SHOP_CARD_PANEL_POS[i]
		panel.size = SHOP_CARD_PANEL_SIZE
		panel.clip_contents = true
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var panel_bg := ColorRect.new()
		panel_bg.color = Color(30.0 / 255.0, 30.0 / 255.0, 30.0 / 255.0, 127.0 / 255.0)
		panel_bg.size = SHOP_CARD_PANEL_SIZE
		panel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(panel_bg)
		add_child(panel)
		shop_card_panels.append(panel)

		var view := CardView.new()
		view.position = SHOP_CARD_IMAGE_POS
		view.scale = SHOP_CARD_IMAGE_SIZE / Vector2(CARD_W, CARD_H)
		view.visible = false
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(view)
		shop_card_views.append(view)

		# 30 rather than the old 46: six slots share the band four used to,
		# so the price has to fit a 41px-tall box now.
		var price_label := _make_label(SHOP_CARD_PRICE_POS, SHOP_CARD_PRICE_SIZE, font_stylish, 30)
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		panel.add_child(price_label)
		shop_card_price_labels.append(price_label)

		shop_cards.append(null)
		shop_cards_active.append(false)
		shop_cards_time.append(0.0)

	busy_spinner = BusySpinner.new()
	busy_spinner.position = Vector2(912, 496)
	busy_spinner.size = Vector2(48, 48)
	busy_spinner.pivot_offset = Vector2(24, 24)
	busy_spinner.visible = false
	add_child(busy_spinner)

	drag_ghost = CardView.new()
	drag_ghost.visible = false
	drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_ghost.z_index = 60
	add_child(drag_ghost)

	selection_outline = SelectionOutline.new()
	selection_outline.set_anchors_preset(Control.PRESET_FULL_RECT)
	selection_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Wheel cards set z_index up to Z_BASE (10, DeckSelectorWheel.gd) so the
	# centered card draws above its neighbors - without a z_index of its own
	# the outline (default 0) drew behind them despite being added last in
	# the tree, since z_index wins over add-order. Kept under drag_ghost (60)
	# so a dragged card still passes over the glow.
	selection_outline.z_index = 50
	add_child(selection_outline)

	_build_audio()

func _build_audio() -> void:
	sfx_button = _make_sfx("sfx/button_sound.wav")
	sfx_back = _make_sfx("sfx/button_back_sound.wav")
	sfx_sell = _make_sfx("sfx/shop_sell.wav")
	sfx_buy = _make_sfx("sfx/shop_buy.wav")

func _make_sfx(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = load(ASSETS + path)
	add_child(p)
	return p

func _make_label(pos: Vector2, label_size: Vector2, font: Font, font_size: int) -> Label:
	var label := FixedSizeLabel.new()
	label.position = pos
	label.size = label_size
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.BLACK)
	label.add_theme_color_override("font_shadow_color", Color(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0, 0.5))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

func _make_button(text: String, pos: Vector2, btn_size: Vector2, font: Font, font_size: int = 25) -> Button:
	var btn := FixedSizeButton.new()
	UIButtonStyle.apply(btn)
	btn.text = text
	btn.position = pos
	btn.size = btn_size
	btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color.BLACK)
	btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	btn.add_theme_constant_override("shadow_offset_x", 1)
	btn.add_theme_constant_override("shadow_offset_y", 1)
	add_child(btn)
	UIButtonStyle.fit_button_text(btn)
	return btn

func _hit_test(control: Control, x: int, y: int) -> bool:
	return Rect2(control.global_position, control.size).has_point(Vector2(x, y))

# ---------------------------------------------------------------- shop cards

func _load_shop_cards() -> void:
	var loaded := SaveSystem.load_shop_cards(Game.player.save_slot)
	# Bounded by what was actually saved, not by the slot count: saves written
	# when the shop had 4 slots stay loadable, the two new slots just start
	# empty and roll on first visit.
	for i in mini(loaded.size(), shop_cards.size()):
		var entry = loaded[i]
		if entry != null:
			shop_cards[i] = entry["card"]
			shop_cards_time[i] = entry["time"]

func _save_shop_cards() -> void:
	var entries := []
	for i in shop_cards.size():
		if shop_cards[i] == null:
			entries.append(null)
		else:
			entries.append({"card": shop_cards[i], "time": shop_cards_time[i]})
	SaveSystem.save_shop_cards(Game.player.save_slot, entries)

## The highest card definitionId the shop is allowed to offer: the portrait
## (image_id) of the furthest opponent the player has actually beaten.
##
## The rule this enforces is that the shop never sells a card belonging to an
## opponent still unbeaten - the first time you see a card it should be across
## the table, and owning one should be the consequence of having beaten it.
## Buying a Minotaur before ever facing one burns exactly the moment the
## campaign is built around.
##
## Uses image_id rather than the opponent index because the two diverge at the
## top: opponent 16 is The Void, whose card is definitionId 19.
func _shop_def_cap() -> int:
	var cap := -1
	for i in AIManager.count():
		var ai: AIManager.AIData = AIManager.get_ai(i)
		if ai.defeated:
			cap = maxi(cap, ai.image_id)
	return cap

## Fills one offer slot. The slot turns itself on as soon as _shop_def_cap()
## reaches its low end and widens as the player advances, so the "a new slot
## roughly every three opponents" pacing falls out of GEN_TABLE instead of
## being spelled out separately. Rerolls every RESTOCK_WINS wins, or right
## away when force_regenerate is set (used just after buying that slot).
func _setup_shop_card(index: int, force_regenerate: bool) -> void:
	var cap := _shop_def_cap()
	var minv: int = GEN_TABLE[index][0]
	var maxv: int = mini(GEN_TABLE[index][1], cap)

	# Slot 0 is the opening safety net (see the has_zero_price rule below):
	# while the player can't field a full deck (fewer than 5 cards), it
	# forces Slime specifically instead of its normal roll - Slime is the
	# only species that's ever free, matching the player's own starter deck
	# (Player.generate_base_set()), not whatever species the normal range
	# would have rolled.
	var free_slime := index == 0 and Game.player.cards.size() < 5
	if free_slime:
		minv = 0
		maxv = 0
	elif index == 0:
		maxv = maxi(maxv, 1)

	if maxv < minv:
		shop_card_price_labels[index].text = ""
		shop_cards_active[index] = false
		shop_card_panels[index].visible = false
		return

	var wins: int = Game.player.matches_won
	# shop_cards_time used to hold a unix timestamp. Saves written before the
	# switch to win-counted restocking still do, and a timestamp is so far
	# ahead of any win count that the slot would never expire again. Rewind it
	# past the restock threshold so such a slot rerolls once, right now, and
	# then keeps normal time - the stale offer was rolled from the old def
	# ranges anyway.
	if shop_cards_time[index] > float(wins):
		shop_cards_time[index] = float(wins - RESTOCK_WINS)

	if force_regenerate or shop_cards[index] == null \
			or wins - int(shop_cards_time[index]) >= RESTOCK_WINS \
			or (free_slime and shop_cards[index].def_id != 0):
		shop_cards[index] = CardManager.generate_card(randi_range(minv, maxv))
		shop_cards_time[index] = float(wins)
		_save_shop_cards()

	# New economy rule (not in the reference, which always makes slot 0
	# free): only free when the player doesn't have enough cards to field a
	# deck (5), so this stays a safety net rather than a permanent freebie
	# once they're already fully stocked. Re-checked on every visit (not
	# just when the card is freshly rolled) so an already-offered card
	# doesn't stay stuck at a real price if the player's count drops below
	# 5 later (or stuck free if it climbs back up) - a stale flag from an
	# earlier visit could otherwise price them out of the safety net.
	if index == 0:
		shop_cards[index].has_zero_price = free_slime

	shop_card_panels[index].visible = true
	shop_card_views[index].visible = true
	shop_card_views[index].setup(shop_cards[index], false, false)
	shop_card_price_labels[index].text = str(CardManager.card_price(shop_cards[index]))
	shop_cards_active[index] = true

# ------------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
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
				deck_selector.on_input_click(x, y)
				_deck_scroll_update_card_info()
		GameState.DRAG_CARD:
			_drag_card_on_click(x, y)

func _route_unclick(x: int, y: int) -> void:
	match game_state:
		GameState.WAITING_INPUT:
			_waiting_input_on_unclick(x, y)
		GameState.DECK_SCROLL:
			if game_state_mode == 0:
				game_state_mode = 1
				var res := deck_selector.on_input_unclick()
				ds_start_angle = res.start_angle
				ds_diff = res.angle_diff
				ds_elapsed = 0.0
		GameState.DRAG_CARD:
			_drag_card_on_unclick(x, y)
		_:
			pass

## New QoL addition (not in the reference): a plain click+release with no
## drag on a non-center wheel card auto-scrolls that card to the center,
## same as DeckSelect.gd's identical addition.
func _waiting_input_on_unclick(x: int, y: int) -> void:
	var was_active := wi_active
	wi_active = false
	if not was_active:
		return

	var hi := deck_selector.hit_test_h_box(x, y)
	if hi != -1:
		_snap_to_box(hi, true)
		return

	var vi := deck_selector.hit_test_v_box(x, y)
	if vi != -1:
		_snap_to_box(vi, false)

func _snap_to_box(array_index: int, horz: bool) -> void:
	var delta: float = deck_selector.snap_delta_for_box(array_index, horz)
	if delta == 0.0:
		return

	deck_selector.on_input_setup(0, 0, horz)

	game_state = GameState.DECK_SCROLL
	game_state_mode = 1
	ds_moving_vert = not horz
	ds_cur_card_stats = null
	ds_start_angle = deck_selector.cur_angle_v if not horz else deck_selector.cur_angle_h
	ds_diff = delta
	ds_elapsed = 0.0

## New QoL addition (not in the reference): double-click/double-tap a card
## to send it straight to the trade slot, instead of dragging it there by
## hand - a shop offer card stages a buy. Double-clicking the trade slot
## itself is the reverse: a sell-staged card returns to the wheel, a
## buy-staged one just clears (it's still sitting in the offer row).
##
## For the SELL wheel, this only fires on the CENTERED card - hit_test_h_box
## matches any visible box, not just the centered one, and double-clicking
## while quickly browsing through neighboring wheel cards (the normal way to
## move from one card to another) used to stage whatever card got
## double-clicked instead of just navigating to it. A double-click on a
## neighbor card falls through to _route_click instead (see the caller) and
## behaves like an ordinary click: it just navigates/centers that card.
## Returns true if consumed.
func _handle_double_click(x: int, y: int) -> bool:
	if _hit_test(panel_card_slot, x, y):
		if cur_sell_card != null:
			_cancel_current_interaction()
			deck_selector.add_card(cur_sell_card)
			_set_sell_card(null)
			_show_card_slot(null)
			_update_card_info(deck_selector.central_card_stats(), true, 1)
			_enter_waiting_input()
			next_sel = 1
			return true
		elif cur_buy_card != null:
			_cancel_current_interaction()
			_set_buy_card(null)
			_show_card_slot(null)
			_update_card_info(null, false, 0)
			_enter_waiting_input()
			return true
		return false

	if deck_selector.central_card_hit_test(x, y):
		_cancel_current_interaction()
		var selector_card: Card = deck_selector.remove_current_card()
		if cur_sell_card != null:
			deck_selector.add_card(cur_sell_card)
		_show_card_slot(selector_card)
		_set_sell_card(selector_card)
		_enter_waiting_input()
		next_sel = 2
		return true

	for i in shop_cards.size():
		if shop_cards_active[i] and Rect2(shop_card_views[i].global_position, SHOP_CARD_IMAGE_SIZE).has_point(Vector2(x, y)):
			_cancel_current_interaction()
			if cur_sell_card != null:
				deck_selector.add_card(cur_sell_card)
			_show_card_slot(shop_cards[i])
			_set_buy_card(shop_cards[i])
			last_chosen_shop_card_index = i
			_enter_waiting_input()
			next_sel = 2
			return true

	return false

## Also kills any in-flight "get card back" tween from a just-cancelled
## drag - otherwise its tween_callback (which restores the slot's old card
## visual) can fire AFTER a double-click has already cleared the slot,
## making the card image look stuck there.
func _cancel_current_interaction() -> void:
	drag_ghost.visible = false
	if is_instance_valid(dc_get_back_tween):
		dc_get_back_tween.kill()
		dc_get_back_tween = null

func _process(delta: float) -> void:
	deck_selector.update()
	_update_selection_outline()

	if game_state == GameState.DECK_SCROLL and game_state_mode == 1:
		_deck_scroll_process(delta)

# --------------------------------------------------------- WaitingInput ---

func _enter_waiting_input() -> void:
	game_state = GameState.WAITING_INPUT
	game_state_mode = 0
	wi_active = false

func _waiting_input_on_click(x: int, y: int) -> void:
	if not wi_active:
		if _hit_test(panel_card_slot, x, y):
			if cur_sell_card != null or cur_buy_card != null:
				if cur_sell_card != null:
					_update_card_info(cur_sell_card, true, 2)
				else:
					_update_card_info(cur_buy_card, false, 2)
				_drag_card_set(x, y, false, false, true, -1)
			return
		elif _hit_test(panel_left, x, y):
			wi_active = true
			wi_x = x
			wi_y = y
		elif image_buyback_card.visible and Rect2(image_buyback_card.global_position, BUYBACK_SIZE).has_point(Vector2(x, y)):
			_update_card_info(buy_back_card, true, 3)
			return
		else:
			for i in shop_cards.size():
				if shop_cards_active[i] and Rect2(shop_card_views[i].global_position, SHOP_CARD_IMAGE_SIZE).has_point(Vector2(x, y)):
					_update_card_info(shop_cards[i], false, 4)
					last_chosen_shop_card_index = i
					_drag_card_set(x, y, false, true, false, i)
					return

	if wi_active:
		var diff_x: int = absi(wi_x - x)
		var diff_y: int = absi(wi_y - y)

		if deck_selector.central_card_hit_test(x, y):
			var cstats: Card = deck_selector.central_card_stats()
			_update_card_info(cstats, true, 1)
			_drag_card_set(x, y, true, false, false, -1)
		else:
			if diff_x > diff_y:
				if diff_x >= 2:
					_deck_scroll_set(x, y, true)
			else:
				if diff_y >= 2:
					_deck_scroll_set(x, y, false)

# ----------------------------------------------------------- DeckScroll ---

func _deck_scroll_set(x: int, y: int, horz: bool) -> void:
	game_state = GameState.DECK_SCROLL
	game_state_mode = 0
	ds_moving_vert = not horz
	ds_cur_card_stats = null
	deck_selector.on_input_setup(x, y, horz)

func _deck_scroll_process(delta: float) -> void:
	ds_elapsed += delta
	var t: float = clampf(ds_elapsed / 0.25, 0.0, 1.0)
	var val: float = t * (2.0 - t)  # Ease.EaseOutQuadratic

	if ds_moving_vert:
		deck_selector.cur_angle_v = ds_start_angle + val * ds_diff
	else:
		deck_selector.cur_angle_h = ds_start_angle + val * ds_diff

	if t >= 1.0:
		deck_selector.on_input_close()
		_deck_scroll_update_card_info()
		_enter_waiting_input()

func _deck_scroll_update_card_info() -> void:
	var cstats: Card = deck_selector.central_card_stats()
	if cstats != ds_cur_card_stats:
		ds_cur_card_stats = cstats
		if cstats != null:
			_update_card_info(cstats, true, 1)

# ------------------------------------------------------------- DragCard ---

func _drag_card_set(x: int, y: int, from_left: bool, from_right: bool, from_slot: bool, index: int) -> void:
	dc_from_left = from_left
	dc_from_right = from_right
	dc_from_slot = from_slot
	dc_index = index
	dc_start_x = x
	dc_start_y = y

	var cstats: Card
	var ghost_center: Vector2

	# Matches gsDragCard.cs setting uiDragCard's size to the SOURCE image's
	# size - full card size from the wheel/slot, but the small shop-card
	# thumbnail size when dragging from the offer row (pops to full size
	# only once it's actually dropped somewhere).
	if from_left:
		cstats = deck_selector.central_card_stats()
		ghost_center = Vector2(deck_selector.central_card_x(), deck_selector.central_card_y())
		drag_ghost.setup(cstats, true, true, true)
		drag_ghost.scale = Vector2.ONE
		dc_ghost_size = Vector2(CARD_W, CARD_H)
	elif from_right:
		cstats = shop_cards[index]
		ghost_center = shop_card_views[index].global_position
		drag_ghost.setup(cstats, false, false, true)
		drag_ghost.scale = SHOP_CARD_IMAGE_SIZE / Vector2(CARD_W, CARD_H)
		dc_ghost_size = SHOP_CARD_IMAGE_SIZE
	else:
		cstats = cur_sell_card if cur_sell_card != null else cur_buy_card
		ghost_center = panel_card_slot.global_position
		_show_card_slot(null)
		drag_ghost.setup(cstats, true, true, true)
		drag_ghost.scale = Vector2.ONE
		dc_ghost_size = Vector2(CARD_W, CARD_H)

	dc_dragged_card = cstats
	drag_ghost.visible = true
	drag_ghost.global_position = ghost_center
	dc_card_pos = drag_ghost.position

	game_state = GameState.DRAG_CARD
	game_state_mode = 0

func _drag_card_on_click(x: int, y: int) -> void:
	drag_ghost.position = dc_card_pos + Vector2(x - dc_start_x, y - dc_start_y)

func _drag_card_on_unclick(x: int, y: int) -> void:
	var drag_rect := Rect2(drag_ghost.position, dc_ghost_size)
	var slot_rect := Rect2(panel_card_slot.position, panel_card_slot.size)

	var get_card_back := false
	var quit_now := false

	if drag_rect.intersects(slot_rect):
		if dc_from_slot:
			get_card_back = true
		elif dc_from_left:
			var selector_card: Card = deck_selector.remove_current_card()
			if cur_sell_card != null:
				deck_selector.add_card(cur_sell_card)
			_show_card_slot(selector_card)
			_set_sell_card(selector_card)
			next_sel = 2
			quit_now = true
		elif dc_from_right:
			if cur_sell_card != null:
				deck_selector.add_card(cur_sell_card)
			_show_card_slot(shop_cards[dc_index])
			_set_buy_card(shop_cards[dc_index])
			next_sel = 2
			quit_now = true
	elif _hit_test(panel_left, x, y):
		if dc_from_slot and cur_sell_card != null:
			deck_selector.add_card(cur_sell_card)
			_set_sell_card(null)
			_update_card_info(deck_selector.central_card_stats(), true, 1)
			_show_card_slot(null)
			quit_now = true
		else:
			get_card_back = true
	elif _shop_cards_region_intersects(drag_rect):
		if dc_from_slot and cur_buy_card != null:
			_set_buy_card(null)
			_update_card_info(null, false, 0)
			_show_card_slot(null)
			quit_now = true
		else:
			get_card_back = true
	else:
		get_card_back = true

	if get_card_back:
		var tw := create_tween()
		dc_get_back_tween = tw
		tw.tween_property(drag_ghost, "position", dc_card_pos, GET_BACK_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if dc_from_slot:
			# gsDragCard_GetBackToSlotCB: the slot's visual was cleared at
			# drag-start (see _drag_card_set's from_slot branch), so it
			# needs restoring here - unlike the wheel/shop-card cases,
			# which never touched the slot.
			var restored_card := dc_dragged_card
			tw.tween_callback(func() -> void:
				drag_ghost.visible = false
				_show_card_slot(restored_card)
				_enter_waiting_input())
		else:
			tw.tween_callback(func() -> void:
				drag_ghost.visible = false
				_enter_waiting_input())
	else:
		drag_ghost.visible = false
		_enter_waiting_input()

func _shop_cards_region_intersects(rect: Rect2) -> bool:
	# Spans first panel top to last panel bottom. Derived from the actual
	# panel positions rather than height * count, which silently undershoots
	# whenever the layout pitch is larger than the panel height (it is).
	var top: Vector2 = shop_card_panels[0].position
	var bottom: float = shop_card_panels[-1].position.y + SHOP_CARD_PANEL_SIZE.y
	var region := Rect2(top, Vector2(SHOP_CARD_PANEL_SIZE.x, bottom - top.y))
	return rect.intersects(region)

func _show_card_slot(card: Card) -> void:
	if card == null:
		card_slot_placeholder.visible = true
		card_slot_view.visible = false
	else:
		card_slot_placeholder.visible = false
		card_slot_view.visible = true
		card_slot_view.setup(card, true, true, true)

# ------------------------------------------------------------- UI sync ---

func _set_sell_card(cstats: Card) -> void:
	cur_sell_card = cstats
	cur_buy_card = null

	if cstats != null:
		label_sell_value.text = str(CardManager.card_price(cstats) / SELL_DIVISOR)
		# New economy rule (not in the reference, which lets any staged card
		# be sold): zero-price cards can't be sold, closing the free-reroll
		# loop of selling a freebie back to gamble on a better one.
		button_sell.disabled = cstats.has_zero_price
	else:
		label_sell_value.text = "---"
		button_sell.disabled = true

	label_buy_value.text = "---"
	button_buy.disabled = true

func _set_buy_card(cstats: Card) -> void:
	cur_buy_card = cstats
	cur_sell_card = null

	if cstats != null:
		var price := CardManager.card_price(cstats)
		label_buy_value.text = str(price)
		button_buy.disabled = Game.player.coins < price
	else:
		label_buy_value.text = "---"
		button_buy.disabled = true

	label_sell_value.text = "---"
	button_sell.disabled = true

func _update_card_info(cstats: Card, is_player_card: bool, sel: int) -> void:
	next_sel = sel
	label_info_name.add_theme_color_override("font_color", Color.BLACK)

	if cstats != null:
		var def: CardManager.CardDef = CardManager.defs[cstats.def_id]
		label_info_name.text = def.name
		label_value_pdef.text = str(cstats.physical_defense)
		label_value_mdef.text = str(cstats.magical_defense)
		label_value_offense.text = str(cstats.attack_power)
		label_value_type.text = CardManager.attack_type_to_string(cstats.attack_type)
		if is_player_card:
			label_info_name.add_theme_color_override("font_color", Color(0.0, 130.0 / 255.0, 1.0))
	else:
		label_info_name.text = StringTable.get_string(StringTable.ID_CARD_STATS)
		label_value_pdef.text = "---"
		label_value_mdef.text = "---"
		label_value_offense.text = "---"
		label_value_type.text = "---"

func _update_selection_outline() -> void:
	if game_state != GameState.WAITING_INPUT:
		selection_outline.visible = false
		return

	var x := -1.0
	var y := -1.0
	var w := -1.0
	var h := -1.0

	if next_sel == 1:
		x = deck_selector.central_card_x()
		y = deck_selector.central_card_y()
		w = deck_selector.card_width
		h = deck_selector.card_height
	elif next_sel == 2:
		x = panel_card_slot.global_position.x
		y = panel_card_slot.global_position.y
		w = panel_card_slot.size.x
		h = panel_card_slot.size.y
	elif next_sel == 3:
		x = image_buyback_card.global_position.x
		y = image_buyback_card.global_position.y
		w = BUYBACK_SIZE.x
		h = BUYBACK_SIZE.y
	elif next_sel == 4 and last_chosen_shop_card_index >= 0:
		var view: CardView = shop_card_views[last_chosen_shop_card_index]
		x = view.global_position.x
		y = view.global_position.y
		w = SHOP_CARD_IMAGE_SIZE.x
		h = SHOP_CARD_IMAGE_SIZE.y

	if x > 0.0:
		selection_outline.visible = true
		selection_outline.set_target_rect(Rect2(x, y, w, h))
		move_child(selection_outline, get_child_count() - 1)
	else:
		selection_outline.visible = false

# ------------------------------------------------------------- buttons ---

func _on_sell_pressed() -> void:
	buy_back_card = cur_sell_card
	image_buyback_card.setup(cur_sell_card, true, true, true)
	image_buyback_card.visible = true
	button_buy_back.visible = true

	_show_card_slot(null)

	Game.player.coins += CardManager.card_price(cur_sell_card) / SELL_DIVISOR
	label_coins.text = str(Game.player.coins)
	Game.player.remove_card(cur_sell_card)

	cur_sell_card = null
	label_sell_value.text = "---"
	button_sell.disabled = true

	_update_card_info(null, false, 0)

	sfx_sell.play()
	await _save_with_busy()

func _on_buy_pressed() -> void:
	_show_card_slot(null)

	buy_back_card = null
	image_buyback_card.visible = false
	button_buy_back.visible = false

	Game.player.coins -= CardManager.card_price(cur_buy_card)
	label_coins.text = str(Game.player.coins)
	Game.player.add_card(cur_buy_card)
	deck_selector.add_card(cur_buy_card)

	_setup_shop_card(last_chosen_shop_card_index, true)
	last_chosen_shop_card_index = -1

	cur_buy_card = null
	label_buy_value.text = "---"
	button_buy.disabled = true

	_update_card_info(deck_selector.central_card_stats(), true, 1)

	sfx_buy.play()
	await _save_with_busy()

func _on_buyback_pressed() -> void:
	Game.player.coins -= CardManager.card_price(buy_back_card) / BUYBACK_DIVISOR
	label_coins.text = str(Game.player.coins)
	Game.player.add_card(buy_back_card)
	deck_selector.add_card(buy_back_card)

	buy_back_card = null
	button_buy_back.visible = false
	image_buyback_card.visible = false

	_update_card_info(deck_selector.central_card_stats(), true, 1)

	sfx_buy.play()
	await _save_with_busy()

func _save_with_busy() -> void:
	busy_spinner.visible = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	await get_tree().create_timer(1.0).timeout
	SaveSystem.save_player(Game.player)
	busy_spinner.visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

func _on_back_pressed() -> void:
	sfx_back.play()
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
