extends Node
## Autoload singleton. Loads card definitions from the original psvita CSV
## and generates randomized Card instances from them.

const CSV_PATH := "res://assets/cards/gen_table.csv"
const STATS_RANGE := [15,31,47,63,79,95,111,127,143,159,175,191,207,223,239,255]

class CardDef:
	var id: int
	var name: String
	var image: String
	var atk_min: int
	var atk_max: int
	var attack_type: int
	var pdef_min: int
	var pdef_max: int
	var mdef_min: int
	var mdef_max: int
	var max_attack_power: int
	var max_attack_type: int
	var max_physical_defense: int
	var max_magical_defense: int
	var arrow_ranges: Array = []  # Array of [min,max] per direction

var defs: Array = []  # Array of CardDef
var _next_uid := 0

func _ready() -> void:
	load_definitions()

## SaveSystem persists this (CardManager.cardGeneratorNextId in the
## reference) so cards created after loading a save don't collide with
## unique_ids already used by that save's cards.
func next_uid() -> int:
	return _next_uid

func set_next_uid(value: int) -> void:
	_next_uid = value

func letter_to_attack_type(letter: String) -> int:
	match letter:
		"P": return Card.AttackType.PHYSICAL
		"M": return Card.AttackType.MAGICAL
		"X": return Card.AttackType.FLEXIBLE
		"A": return Card.AttackType.ASSAULT
	push_error("Unrecognized attack type letter: " + letter)
	return Card.AttackType.PHYSICAL

func attack_type_to_letter(type: int) -> String:
	match type:
		Card.AttackType.PHYSICAL: return "P"
		Card.AttackType.MAGICAL: return "M"
		Card.AttackType.FLEXIBLE: return "X"
		Card.AttackType.ASSAULT: return "A"
	return "?"

func attack_type_to_string(type: int) -> String:
	match type:
		Card.AttackType.PHYSICAL: return StringTable.get_string(StringTable.ID_ATTACK_TYPE_PHYSICAL)
		Card.AttackType.MAGICAL: return StringTable.get_string(StringTable.ID_ATTACK_TYPE_MAGICAL)
		Card.AttackType.FLEXIBLE: return StringTable.get_string(StringTable.ID_ATTACK_TYPE_FLEXIBLE)
		Card.AttackType.ASSAULT: return StringTable.get_string(StringTable.ID_ATTACK_TYPE_ASSAULT)
	return "?"

func stat_to_hex(stat: int) -> String:
	for i in STATS_RANGE.size():
		if stat <= STATS_RANGE[i]:
			return "%X" % i
	return "0"

func parse_range(data: String) -> Array:
	if data.begins_with("("):
		var inner := data.substr(1, data.length() - 2)
		var parts := inner.split("-")
		return [int(parts[0]), int(parts[1])]
	var v := int(data)
	return [v, v]

func load_definitions() -> void:
	defs.clear()
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
		var def := CardDef.new()
		def.id = int(data[0])
		def.name = data[1]
		def.image = data[2]

		var atk := parse_range(data[3])
		def.atk_min = atk[0]; def.atk_max = atk[1]
		def.attack_type = letter_to_attack_type(data[4])

		var pdef := parse_range(data[5])
		def.pdef_min = pdef[0]; def.pdef_max = pdef[1]

		var mdef := parse_range(data[6])
		def.mdef_min = mdef[0]; def.mdef_max = mdef[1]

		def.max_attack_power = int(data[7])
		def.max_attack_type = letter_to_attack_type(data[8])
		def.max_physical_defense = int(data[9])
		def.max_magical_defense = int(data[10])

		def.arrow_ranges = []
		for i in 8:
			def.arrow_ranges.append(parse_range(data[11 + i]))

		defs.append(def)

func generate_card(def_id: int) -> Card:
	var def: CardDef = defs[def_id]
	var card := Card.new()
	card.def_id = def_id
	card.unique_id = _next_uid
	_next_uid += 1
	card.attack_type = def.attack_type
	card.attack_power = randi_range(def.atk_min, def.atk_max)
	card.physical_defense = randi_range(def.pdef_min, def.pdef_max)
	card.magical_defense = randi_range(def.mdef_min, def.mdef_max)
	card.arrows = []
	for i in 8:
		var r: Array = def.arrow_ranges[i]
		card.arrows.append(randi_range(r[0], r[1]) == 1)
	return card

## Port of CardManager.cs's CardPrice(). Flexible/Assault types command a
## premium (exponent > 1 on the average stat), more arrows raise the price
## linearly, hasZeroPrice (starter cards, shop slot 0) overrides to 0.
func card_price(card: Card) -> int:
	if card.has_zero_price:
		return 0

	var t: float
	if card.attack_type == Card.AttackType.FLEXIBLE:
		t = 1.1
	elif card.attack_type == Card.AttackType.ASSAULT:
		t = 1.3
	else:
		t = 1.0

	var f := 0.0
	for b in card.arrows:
		if b:
			f += 1.0

	var val: float = float(card.attack_power + card.physical_defense + card.magical_defense) / 3.0
	var total: float = 10.0 * f * pow(val, t)
	return int(total)

func generate_random_deck(count: int) -> Array:
	var deck := []
	for i in count:
		deck.append(generate_card(randi() % defs.size()))
	return deck

# Excludes special reward cards (The Void, Rage Quit) that need bespoke
# rendering/rules in the original game - not part of a normal random hand.
func playable_ids() -> Array:
	var ids := []
	for def in defs:
		if def.name != "The Void" and def.name != "Rage Quit":
			ids.append(def.id)
	return ids

func generate_playable_deck(count: int) -> Array:
	var ids := playable_ids()
	var deck := []
	for i in count:
		deck.append(generate_card(ids[randi() % ids.size()]))
	return deck

# Ported from Card.cs's drawStats: for each of the 4 stat_text() characters,
# how "maxed out" it is relative to that card definition's possible range
# (0=min .. 1=max). CardView uses this to pick the min/med/max color.
func stat_delta(card: Card, index: int) -> float:
	var def: CardDef = defs[card.def_id]
	var diff := 0.0
	match index:
		0:
			diff = def.max_attack_power - def.atk_min
			if diff > 0.0:
				return float(card.attack_power - def.atk_min) / diff
		1:
			diff = def.max_attack_type - def.attack_type
			if diff > 0.0:
				return float(card.attack_type - def.attack_type) / diff
		2:
			diff = def.max_physical_defense - def.pdef_min
			if diff > 0.0:
				return float(card.physical_defense - def.pdef_min) / diff
		3:
			diff = def.max_magical_defense - def.mdef_min
			if diff > 0.0:
				return float(card.magical_defense - def.mdef_min) / diff
	return 1.0
