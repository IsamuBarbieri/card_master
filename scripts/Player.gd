class_name Player
extends RefCounted
## Port of Player.cs. No SaveSystem yet (comes later) - a Player is created
## fresh in memory each run (StartMenu.gd's slot tap), matching a brand-new
## save slot: only opponent 0 unlocked, starts with generate_base_set()'s
## 5 starter cards (mirrors SaveSystem.CreateNewPlayer).

var cards: Array = []
var player_name: String
var save_slot: int
var coins: int = 0
var match_started: bool = false
var available_opponents: Array = []  # bool per AIManager opponent index

func _init(new_name: String, slot: int, opponent_count: int) -> void:
	player_name = new_name
	save_slot = slot
	available_opponents.resize(opponent_count)
	available_opponents.fill(false)
	available_opponents[0] = true

## Port of Player.cs's GenerateBaseSet(): 5 starter cards from definitions
## 0 or 1 only (Slime/whatever gen_table.csv's 2nd row is), randomly chosen
## per card.
func generate_base_set() -> void:
	for i in 5:
		var card := CardManager.generate_card(randi() % 2)
		card.has_zero_price = true
		cards.append(card)

func add_card(cstats: Card) -> void:
	cards.append(cstats)

func add_captured_card(cstats: Card) -> void:
	cstats.is_favourite = false
	cstats.is_on_deck = false
	cards.append(cstats)

## (RAGEQUIT) - captured rage-quit cards reset to a low level instead of
## keeping their real stats.
func add_captured_rage_quit_card(cstats: Card) -> void:
	cstats.attack_power = randi_range(1, 9)
	cstats.physical_defense = randi_range(1, 9)
	cstats.magical_defense = randi_range(1, 9)
	cstats.is_favourite = false
	cstats.is_on_deck = false
	cards.append(cstats)

## Matches by unique_id rather than object identity: Card.Stats is a struct
## in the reference (List.Remove compares by value), but Card is a
## RefCounted class here - and BattleScene deals in clone_stats() copies of
## the player's deck cards (so captures don't mutate the persistent entry),
## so the instance passed in is rarely the same object stored in `cards`.
func remove_card(cstats: Card) -> void:
	for i in cards.size():
		if cards[i].unique_id == cstats.unique_id:
			cards.remove_at(i)
			return

func get_num_cards_of_this_type(cstats: Card) -> int:
	var count := 0
	for card in cards:
		if card.def_id == cstats.def_id:
			count += 1
	return count
