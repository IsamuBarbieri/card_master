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
	card.arrows = generate_arrows()
	return card

## Each additional arrow beyond the first is strictly rarer than the last,
## instead of every direction rolling an independent 50/50 (the old system -
## every card averaged ~4.5/8 arrows regardless of species, which is why a
## captured card's Chain almost always found a way to keep going: ~32%
## chance any two adjacent enemies had a mutual return arrow). ARROW_BASE is
## the odds of getting a 2nd arrow at all; each arrow past that multiplies
## the odds by ARROW_DECAY again, so the chain of rolls stops at the first
## failure - a monotonically decreasing count distribution (1 arrow ~35% of
## cards, 8 arrows ~0.08%, average ~2.2) instead of a bell curve centered on
## "most cards have half the compass covered."
const ARROW_BASE := 0.65
const ARROW_DECAY := 0.82

## The guaranteed 1st arrow is random in direction too, same as every arrow
## after it - "guaranteed" only means the count never drops below 1, not
## that any particular direction is predictable. A shuffled direction order
## decides which slot is the guaranteed one and which order the rest are
## attempted in.
func generate_arrows() -> Array:
	var arrows := [false, false, false, false, false, false, false, false]
	var order: Array = range(8)
	order.shuffle()

	arrows[order[0]] = true

	var continue_chance := ARROW_BASE
	for i in range(1, 8):
		if randf() >= continue_chance:
			break
		arrows[order[i]] = true
		continue_chance *= ARROW_DECAY

	return arrows

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
	# The reference multiplied straight by the arrow count, making an 8-arrow
	# card worth 8x the same species at 1 arrow. That assumed "more arrows is
	# strictly better", which isn't true here: an arrow is also an entry point
	# for the opponent (a card with no return arrow is captured without a
	# fight, and a captured card's own arrows are what lets a Chain keep
	# going - see Board.get_capturable_cards/get_adjacent_battle_cards). A
	# low-arrow card is a deliberate anti-chain anchor, not a dud. The +2
	# offset keeps arrows a price factor but compresses the spread from 8x
	# to 3.3x so they no longer dominate the valuation.
	#
	# 15.4 (was 10.0): generate_arrows' rarer-each-time curve dropped the
	# average arrow count from ~4.5 to ~2.2, which would silently shrink
	# every price (and, since buy/sell/buyback in Shop.gd all derive from
	# this same number, the whole coin economy) by ~35% as a side effect.
	# Rescaled so the average (2.0 + f) factor lands back on the same ~6.5
	# it was before (10.0 * 6.5 == 15.4 * (2.0 + ~2.22)) - same prices on
	# average, same 3.3x spread between a 1-arrow and an 8-arrow card, just
	# priced against the new rarity curve instead of the old one.
	var total: float = 15.4 * (2.0 + f) * pow(val, t)
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

## How much of its own growth headroom this card has already consumed, 0..1.
## Average of the three numeric stats (stat_delta indices 0/2/3 - index 1 is
## the attack type, which isn't part of growth). Drives the attack-type
## evolution thresholds in BattleScene._level_up_card: the type advances
## partway up the curve rather than at the end, so a card's power ramps
## continuously instead of doubling once it's already maxed out.
func growth(card: Card) -> float:
	return (stat_delta(card, 0) + stat_delta(card, 2) + stat_delta(card, 3)) / 3.0
