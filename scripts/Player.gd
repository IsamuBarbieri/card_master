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
		cards.append(CardManager.generate_card(randi() % 2))
