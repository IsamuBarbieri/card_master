extends Node
## Verifies BattleScene._collect_chain_levels splits a single win's cascade
## into independent branches by depth: a branch that dead-ends at depth 1 is
## Combo-only, a branch that reaches depth 2+ is Chain - even when both
## branch off the very same captured card.
##
## A Node (not `extends SceneTree` run via --script) because Card.gd/
## CardManager need the project's autoloads, which --script mode skips.
## Run: godot --headless --quit-after 10 res://tests/test_chain_combo_split.tscn

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

	# W (winner, owner 0) just captured L at (1,2).
	# L branches two ways:
	#   N -> A (0,2): no return arrow -> dead end -> Combo.
	#   E -> B (1,3) -> S -> C (2,3): B returns W-ward -> depth 2 -> Chain,
	#   and the whole branch (L's E-step AND B) counts as Chain, not just C.
	var w := _make_card(1, 1, 1, 0)
	var l := _make_card(2, 1, 2, 0)  # already flipped to the winner's side
	var a := _make_card(3, 0, 2, 1)
	var b := _make_card(4, 1, 3, 1)
	var c := _make_card(5, 2, 3, 1)

	l.arrows[N] = true
	l.arrows[E] = true
	a.arrows[S] = false  # no return arrow -> dead end
	b.arrows[W] = true   # returns toward L -> continues
	b.arrows[S] = true   # -> reaches C

	board.place_card(w, 1, 1)
	board.place_card(l, 1, 2)
	board.place_card(a, 0, 2)
	board.place_card(b, 1, 3)
	board.place_card(c, 2, 3)

	var battle_scene_script := load("res://scripts/battle/BattleScene.gd")
	var scene: Object = battle_scene_script.new()
	scene.board = board

	var split: Dictionary = scene._collect_chain_levels(l, w.owner)
	var chain_levels: Array = split["chain_levels"]
	var combo_cards: Array = split["combo_cards"]

	assert(combo_cards.size() == 1 and combo_cards[0] == a, "combo_cards should be exactly [A], got %s" % [combo_cards])
	assert(chain_levels.size() == 2, "expected 2 chain depth-levels (B, then C), got %d" % chain_levels.size())
	assert(chain_levels[0].size() == 1 and chain_levels[0][0] == b, "chain level 1 should be [B], got %s" % [chain_levels[0]])
	assert(chain_levels[1].size() == 1 and chain_levels[1][0] == c, "chain level 2 should be [C], got %s" % [chain_levels[1]])
	scene.free()

	# Sanity: a pure single-level cascade (no continuing branch at all) is
	# combo-only, same as before this split existed.
	var board2 := Board.new()
	var w2 := _make_card(10, 1, 1, 0)
	var l2 := _make_card(11, 1, 2, 0)
	var a2 := _make_card(12, 0, 2, 1)
	l2.arrows[N] = true
	a2.arrows[S] = false
	board2.place_card(w2, 1, 1)
	board2.place_card(l2, 1, 2)
	board2.place_card(a2, 0, 2)
	var scene2: Object = battle_scene_script.new()
	scene2.board = board2
	var split2: Dictionary = scene2._collect_chain_levels(l2, w2.owner)
	assert((split2["chain_levels"] as Array).is_empty(), "pure single-level cascade must have no chain_levels")
	assert((split2["combo_cards"] as Array) == [a2], "pure single-level cascade should be combo-only [A2]")
	scene2.free()

	print("OK - chain/combo branch split verified")
	get_tree().quit()
