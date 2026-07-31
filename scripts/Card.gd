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

func stat_text() -> String:
	var s := ""
	s += CardManager.stat_to_hex(attack_power)
	s += CardManager.attack_type_to_letter(attack_type)
	s += CardManager.stat_to_hex(physical_defense)
	s += CardManager.stat_to_hex(magical_defense)
	return s
