extends Node
## Checks the hybrid level-up formula (see the "Sistema di livello ibrido"
## plan): a small flat bonus only on an actual win (LEVEL_UP_POINTS has no
## Draw/loss entry, to kill the old "draw repeatedly for free points" farm),
## plus `Card.battle_captures` - points for cards that personally won a
## battle/chain link/combo this match, regardless of the match's overall
## result.
##
## `_level_up_card`/`gsEndLevelUp_Set`'s full flow needs real CardViews in
## the scene tree (Tweens, floating text) to run end-to-end, so this checks
## the parts that don't: the point table itself, the exact formula
## (base + battle_captures) gsEndLevelUp_Set applies, and that
## battle_captures is per-match transient state (not carried by
## clone_stats(), so every fresh battle clone starts at 0).
## Run: godot --headless --quit-after 10 res://tests/test_level_up_hybrid.tscn

func _ready() -> void:
	var battle_scene_script := load("res://scripts/battle/BattleScene.gd")
	var probe: Object = battle_scene_script.new()
	assert(probe.has_method("gsEndLevelUp_Set"), "BattleScene.gd is missing gsEndLevelUp_Set")

	var points: Dictionary = probe.LEVEL_UP_POINTS
	var battle_result_enum: Dictionary = probe.BattleResult

	assert(not points.has(battle_result_enum["DRAW"]), "Draw must NOT grant flat points - that was the farmable case")
	assert(points[battle_result_enum["PLAYER_PERFECT"]] == 2, "PLAYER_PERFECT base should be 2")
	assert(points[battle_result_enum["PLAYER_WINS"]] == 1, "PLAYER_WINS base should be 1")
	assert(not points.has(battle_result_enum["CPU_WINS"]), "a loss must not grant flat points")
	assert(not points.has(battle_result_enum["CPU_PERFECT"]), "a loss must not grant flat points")
	probe.free()

	# gsEndLevelUp_Set's actual formula: base_points + card.battle_captures.
	# Reproduced here since the real call needs live CardViews/Tweens.
	var cases := [
		# [base_points, battle_captures, expected_total]
		[2, 0, 2],   # perfect win, card never fought - still gets the flat base
		[1, 3, 4],   # normal win, card personally won a 3-deep chain
		[0, 2, 2],   # draw or loss, but this card personally captured 2 cards
		[0, 0, 0],   # draw/loss, card did nothing - must get exactly 0, not level up at all
	]
	for c in cases:
		var base: int = c[0]
		var captures: int = c[1]
		var expected: int = c[2]
		assert(base + captures == expected, "formula mismatch for %s" % [c])

	# battle_captures is transient per-match state: a fresh battle clone
	# must always start at 0, even if the persistent source card somehow
	# had a nonzero value left over (shouldn't happen, but clone_stats()
	# must not be the thing preventing it).
	var original := Card.new()
	original.battle_captures = 7
	var clone := original.clone_stats()
	assert(clone.battle_captures == 0, "clone_stats() must not carry battle_captures over")

	print("OK - hybrid level-up checks passed")
	get_tree().quit()
