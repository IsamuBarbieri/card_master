class_name MatchState
extends RefCounted
## Canonical fingerprint of an in-progress match, for the online lockstep
## check: after every move both clients hash their own board+hands and send
## the digest with the move. The server compares the two digests and voids the
## match if they disagree - which is what makes a tampered client unable to
## win instead of merely unable to be detected. Nothing here is used offline.
##
## Everything that can legally differ between the two players' views is
## deliberately excluded (view nodes, animation state, card_price, level-up
## progress); everything a rules divergence would show up in is included.

## Bit-packed arrow flags, so the token stays short and ordering-independent.
static func arrow_mask(card: Card) -> int:
	var mask := 0
	for i in 8:
		if card.arrows[i]:
			mask |= 1 << i
	return mask

## unique_id alone would be ambiguous: the two players' collections number
## their cards independently, so both sides can hold a card with the same
## unique_id. The owner disambiguates, and the stats are in there so a client
## that quietly buffs a card mid-match diverges immediately.
##
## `my_slot` rebases ownership into the MATCH frame. BattleScene always calls
## the local player 0, so the two clients see mirrored owners for the same
## card - hashing the local frame would make every honest match look tampered.
static func card_token(card: Card, my_slot: int) -> String:
	if card == null:
		return "-"
	return "%d:%d:%d:%d:%d:%d:%d:%d" % [
		card.owner if my_slot == 0 else 1 - card.owner,
		card.unique_id,
		card.def_id,
		card.attack_power,
		card.physical_defense,
		card.magical_defense,
		card.attack_type,
		arrow_mask(card),
	]

## `tag` marks decisions that don't move a card (which target to fight, which
## card to steal): the board is identical before and after, so without it the
## two clients would "agree" on a turn where one of them chose differently.
static func state_hash(board: Board, player_hand: Array, cpu_hand: Array,
		turn: int, my_slot: int = 0, tag: String = "") -> String:
	var parts := PackedStringArray()
	parts.append("t%d" % turn)
	parts.append(tag)
	for r in Board.NUM_ROWS:
		for c in Board.NUM_COLS:
			if board.blocked[r][c]:
				parts.append("#")
			else:
				parts.append(card_token(board.slots[r][c], my_slot))
	# The hands are fixed-size arrays with nulls where a card has already been
	# played (BattleScene.gd:109), so the slot positions themselves are part
	# of the fingerprint - no filtering, no sorting. Listed in match order, so
	# both clients write the same player's hand first.
	var hands := [player_hand, cpu_hand] if my_slot == 0 else [cpu_hand, player_hand]
	for side in 2:
		parts.append("h%d" % side)
		for card in hands[side]:
			parts.append(card_token(card, my_slot))
	return ",".join(parts).sha256_text()
