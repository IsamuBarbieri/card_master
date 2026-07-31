class_name GsCPUTurn
extends RefCounted
## Ported from Scenes/Battle/gsCPUTurn.cs. gsCPUTurn_EvalCard/EvalFightableCard
## in the original score a placement using AITables (per-opponent generated
## data tables loaded from save data); those don't exist in this skirmish-only
## port, so choose_move()/choose_battle_target() replace them with a fixed
## heuristic evaluator that plays the same role.

# Rough odds that card0 beats card1 in a gsBattle.gd resolution, based on
# the stats that would actually be compared for card0's attack type.
static func _win_margin(card0: Card, card1: Card) -> float:
	var attack_stat := 0
	var defense_stat := 0
	match card0.attack_type:
		Card.AttackType.PHYSICAL:
			attack_stat = card0.attack_power
			defense_stat = card1.physical_defense
		Card.AttackType.MAGICAL:
			attack_stat = card0.attack_power
			defense_stat = card1.magical_defense
		Card.AttackType.FLEXIBLE:
			attack_stat = card0.attack_power
			defense_stat = min(card1.magical_defense, card1.physical_defense)
		Card.AttackType.ASSAULT:
			attack_stat = max(card0.attack_power, card0.physical_defense, card0.magical_defense)
			defense_stat = min(card1.attack_power, card1.physical_defense, card1.magical_defense)
	if attack_stat + defense_stat == 0:
		return 0.0
	return float(attack_stat - defense_stat) / float(attack_stat + defense_stat)

# Score of placing `card` at (row, col) on `board`: instant captures count a
# lot, winnable fights count some, and cards left exposed to a strong enemy
# counter-fight count against it.
static func _score_placement(board: Board, card: Card, row: int, col: int) -> float:
	card.row = row
	card.col = col

	var score := 0.0
	for target in board.get_capturable_cards(card):
		score += 2.0 + _win_margin(card, target)
	for target in board.get_adjacent_battle_cards(card):
		score += _win_margin(card, target)

	# Mild penalty for exposing undefended sides toward empty slots an
	# opponent could still play into.
	for i in 8:
		if card.arrows[i]:
			continue
		var r: int = row + Board.SLOT_OFFSETS[i][0]
		var c: int = col + Board.SLOT_OFFSETS[i][1]
		if board.is_valid(r, c) and not board.has_card(r, c):
			score -= 0.15

	card.row = -1
	card.col = -1
	return score

# Returns {"card": Card, "row": int, "col": int} for the best move found.
static func choose_move(board: Board, hand: Array) -> Dictionary:
	var best_score := -INF
	var best := {}
	for card in hand:
		for slot in board.empty_slots():
			var score := _score_placement(board, card, slot[0], slot[1])
			if score > best_score:
				best_score = score
				best = {"card": card, "row": slot[0], "col": slot[1]}
	return best

static func choose_battle_target(attacker: Card, candidates: Array) -> Card:
	var best: Card = candidates[0]
	var best_margin := _win_margin(attacker, best)
	for c in candidates:
		var m := _win_margin(attacker, c)
		if m > best_margin:
			best_margin = m
			best = c
	return best
