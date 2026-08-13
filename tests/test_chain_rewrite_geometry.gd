extends Node
## The chain/combo engine (BattleScene.gd's gsResolveCardTurn_Set /
## gsBattleChainBattle_Set / gsBattle_End) was rewritten to use REAL
## recursive battles instead of an automatic geometric BFS - see the
## "Flusso Logico del Turno e Priorità" design doc. That control flow is
## RNG-driven (GsBattle.resolve_battle) and needs the full scene's Tween/
## CardView machinery to run at all, so it isn't practically unit-testable
## here (the old BFS-only chain math this replaced WAS pure data and had
## its own test, now removed along with the code it covered).
##
## What IS still pure data, and what the new engine is built entirely out
## of, is Board.get_capturable_cards (Combo sub-phase) and
## Board.get_adjacent_battle_cards (Chain sub-phase) - this pins those down,
## plus a signature/reachability smoke check on the new functions so a typo
## in the rewrite doesn't silently no-op instead of erroring.
##
## Real battle-flow correctness (ties retry the next target, a loss ends
## the lineage, Chain only labels from depth 2, etc.) needs actual
## playtesting - see the summary given alongside this change.
## Run: godot --headless --quit-after 10 res://tests/test_chain_rewrite_geometry.tscn

const N := 0
const E := 2
const S := 4
const W := 6

func _make_card(id: int, row: int, col: int, owner: int) -> Card:
	var c := Card.new()
	c.unique_id = id
	c.row = row
	c.col = col
	c.owner = owner
	return c

func _ready() -> void:
	var board := Board.new()

	# Epicenter E at (1,1), owner 0 (just captured this turn).
	#   N -> A: no return arrow -> Combo target.
	#   E -> B: HAS a return arrow -> Chain target (a real battle now, not
	#           an automatic capture).
	var epicenter := _make_card(1, 1, 1, 0)
	var a := _make_card(2, 0, 1, 1)   # N of epicenter
	var b := _make_card(3, 1, 2, 1)   # E of epicenter
	epicenter.arrows[N] = true
	epicenter.arrows[E] = true
	a.arrows[S] = false  # no return -> Combo
	b.arrows[W] = true   # returns -> Chain (a battle)

	board.place_card(epicenter, 1, 1)
	board.place_card(a, 0, 1)
	board.place_card(b, 1, 2)

	var simple := board.get_capturable_cards(epicenter)
	assert(simple.size() == 1 and simple[0] == a, "Combo sub-phase should find exactly A (no return arrow)")

	var fightable := board.get_adjacent_battle_cards(epicenter)
	assert(fightable.size() == 1 and fightable[0] == b, "Chain sub-phase should find exactly B (has a return arrow)")

	# Signature/reachability smoke check: these must exist and be callable
	# with the new (card, depth[, tied]) shape, or the rewrite has a typo
	# that would otherwise only surface as a silent no-op mid-game. Checked
	# via Object.has_method on a bare instance (Script.has_method doesn't
	# see user-defined GDScript methods) - .new() alone doesn't run _ready.
	var battle_scene_script := load("res://scripts/battle/BattleScene.gd")
	var probe: Object = battle_scene_script.new()
	for method in ["gsResolveCardTurn_Set", "gsBattleChainBattle_Set", "gsBattle_Set", "gsBattle_End"]:
		assert(probe.has_method(method), "BattleScene.gd is missing %s after the rewrite" % method)
	probe.free()

	print("OK - chain rewrite geometry + signature checks passed")
	get_tree().quit()
