class_name Card
extends RefCounted
## Runtime instance of a card (data only, no rendering).

enum AttackType { PHYSICAL, MAGICAL, FLEXIBLE, ASSAULT }

var def_id: int
var unique_id: int
var attack_power: int
var physical_defense: int
var magical_defense: int
var attack_type: int
var arrows: Array = [false, false, false, false, false, false, false, false]

var owner: int = 0          # 0 = player, 1 = CPU
var original_owner: int = 0
var row: int = -1
var col: int = -1

# DeckSelect state (Card.Stats's isOnDeck/isFavourite in the reference).
var is_on_deck: bool = false
var is_favourite: bool = false

# Shop: starter cards and shop slot 0 are always worth 0 coins to sell,
# so they can't be insta-sold for free money.
var has_zero_price: bool = false

# How many cards THIS card personally captured this match (battle win, chain
# link, or combo burst) - a transient per-match tally, not persistent state,
# so it's deliberately left out of clone_stats() below (same as owner/row/
# col): every fresh battle clone starts at 0 with no reset needed. Read by
# BattleScene.gd's level-up pass to reward cards that actually did
# something, on top of (or in place of) the flat per-match result bonus.
var battle_captures: int = 0

func can_level_up_p_def() -> bool:
	var def: CardManager.CardDef = CardManager.defs[def_id]
	return physical_defense < def.max_physical_defense

func can_level_up_m_def() -> bool:
	var def: CardManager.CardDef = CardManager.defs[def_id]
	return magical_defense < def.max_magical_defense

func can_level_up_a_pow() -> bool:
	var def: CardManager.CardDef = CardManager.defs[def_id]
	return attack_power < def.max_attack_power

## A fresh Card with the same stats but none of the battle/deck state
## (owner, row/col, is_on_deck/is_favourite) - BattleScene needs this so
## captures during a match (Board.capture mutates card.owner in place)
## don't corrupt the persistent Game.player.cards entry the deck card came
## from.
func clone_stats() -> Card:
	var c := Card.new()
	c.def_id = def_id
	c.unique_id = unique_id
	c.attack_power = attack_power
	c.physical_defense = physical_defense
	c.magical_defense = magical_defense
	c.attack_type = attack_type
	c.arrows = arrows.duplicate()
	c.has_zero_price = has_zero_price
	return c

func stat_text() -> String:
	var s := ""
	s += CardManager.stat_to_hex(attack_power)
	s += CardManager.attack_type_to_letter(attack_type)
	s += CardManager.stat_to_hex(physical_defense)
	s += CardManager.stat_to_hex(magical_defense)
	return s
