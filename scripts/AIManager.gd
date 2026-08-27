extends Node
## Port of AIManager.cs. Each AI has a persistent battle-deck pool
## (topCards/genericCards/capturedCards) that grows and gets drawn down
## across matches - generated once ever (AIGenFirstSet, from the First Set
## range in ai_table.csv) and then reused/extended via captures, instead of
## a fresh random hand every battle. Loaded/saved through SaveSystem.gd
## (folded into the per-slot player save instead of the reference's one
## ai{id}.dat file per AI - same data, simpler file layout).

const CSV_PATH := "res://assets/cards/ai_table.csv"
const NUM_FIRST_SET_CARDS := 5

class AIData:
	var id: int
	var ai_name: String
	var image_id: int
	var level: int
	var gen_first_min: int
	var gen_first_max: int
	var gen_other_min: int
	var gen_other_max: int
	var defeated: bool = false

	# Dynamic (per save slot) - see ensure_dynamic_data().
	var dynamic_data_loaded: bool = false
	var top_cards: Array = []       # Array[Card]
	var generic_cards: Array = []   # Array[Card]
	var captured_cards: Array = []  # Array[Card]

var _ai: Array = []  # Array of AIData

func _ready() -> void:
	_load()

func _load() -> void:
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open " + CSV_PATH)
		return
	var line_index := 0
	while not file.eof_reached():
		var line := file.get_line()
		line_index += 1
		if line_index == 1 or line.strip_edges() == "":
			continue
		var data := line.split(",")
		var ai := AIData.new()
		ai.id = int(data[0])
		ai.ai_name = data[1]
		ai.image_id = int(data[2])
		ai.level = int(data[3])
		var first_set: Array = CardManager.parse_range(data[4])
		ai.gen_first_min = first_set[0]
		ai.gen_first_max = first_set[1]
		var other_set: Array = CardManager.parse_range(data[5])
		ai.gen_other_min = other_set[0]
		ai.gen_other_max = other_set[1]
		_ai.append(ai)
	file.close()

func count() -> int:
	return _ai.size()

func rage_quit_index() -> int:
	return _ai.size() - 1

func get_ai(index: int) -> AIData:
	return _ai[index]

## Port of AIManager.cs's GetFullAI()'s lazy-init: the first time an AI's
## battle deck is actually needed in a session, its pools either come from
## SaveSystem.load_player() (already populated by then, if this AI was
## used before in this slot) or get generated fresh here (AIGenFirstSet -
## 5 cards from the First Set range). SaveSystem resets dynamic_data_loaded
## to false for every AI on load, so this only ever generates once per AI
## per slot.
func ensure_dynamic_data(ai: AIData) -> void:
	if ai.dynamic_data_loaded:
		return
	for i in NUM_FIRST_SET_CARDS:
		ai.top_cards.append(CardManager.generate_card(randi_range(ai.gen_first_min, ai.gen_first_max)))
	ai.dynamic_data_loaded = true

## Port of AIManager.cs's AIPrepareSet(): this AI's 5-card battle hand,
## drawn from its captured cards first, then its starting set, then
## (generating more if needed) its generic filler pool.
func prepare_set(ai: AIData) -> Array:
	var cards := []
	var picked := {}

	if ai.captured_cards.size() <= 5:
		for c in ai.captured_cards:
			cards.append(c)
	else:
		for i in 5:
			cards.append(ai.captured_cards[_pick_unique(ai.captured_cards.size(), picked)])

	if cards.size() < 5:
		var count_top: int = ai.top_cards.size()
		picked = {}
		var num_inserted := 0
		while cards.size() < 5 and num_inserted < count_top:
			cards.append(ai.top_cards[_pick_unique(count_top, picked)])
			num_inserted += 1

	if cards.size() < 5:
		if cards.size() + ai.generic_cards.size() < 5:
			var needed: int = 5 - (cards.size() + ai.generic_cards.size())
			for i in needed:
				ai.generic_cards.append(CardManager.generate_card(randi_range(ai.gen_other_min, ai.gen_other_max)))
		var count_gen: int = ai.generic_cards.size()
		picked = {}
		while cards.size() < 5:
			cards.append(ai.generic_cards[_pick_unique(count_gen, picked)])

	# Ensure the AI always has at least one card of its own species in the
	# hand (identified by image_id, which matches the card def_id). Without
	# this, an AI whose type-matching cards have all been captured by the
	# player would field a deck with none of its own kind - losing its
	# identity.
	var has_own_type := false
	for c in cards:
		if c.def_id == ai.image_id:
			has_own_type = true
			break
	if not has_own_type and cards.size() > 0:
		cards[-1] = CardManager.generate_card(ai.image_id)

	return cards

func _pick_unique(count: int, picked: Dictionary) -> int:
	var index := randi() % count
	while picked.has(index):
		index = (index + 1) % count
	picked[index] = true
	return index

func add_captured_card(ai: AIData, card: Card) -> void:
	card.is_favourite = false
	card.is_on_deck = false
	ai.captured_cards.append(card)

func remove_card(ai: AIData, card: Card) -> void:
	if _erase_by_uid(ai.top_cards, card.unique_id):
		return
	if _erase_by_uid(ai.generic_cards, card.unique_id):
		return
	_erase_by_uid(ai.captured_cards, card.unique_id)

func _erase_by_uid(pool: Array, uid: int) -> bool:
	for i in pool.size():
		if pool[i].unique_id == uid:
			pool.remove_at(i)
			return true
	return false
