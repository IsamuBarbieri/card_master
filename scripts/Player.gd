class_name Player
extends RefCounted
## Port of Player.cs. No SaveSystem yet (comes later) - a Player is created
## fresh in memory each run (StartMenu.gd's slot tap), matching a brand-new
## save slot: only opponent 0 unlocked, no cards owned yet.

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
