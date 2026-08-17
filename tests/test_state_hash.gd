extends Node
## The other half of the lockstep guarantee: two independent simulations of
## the same seed and the same moves must agree on MatchState.state_hash at
## every step, and any deviation must change the digest. The server compares
## exactly these two things, so a false match here means cheating goes
## unnoticed and a false mismatch here means honest players get voided.
## Run: godot --headless --quit-after 20 res://tests/test_state_hash.tscn

# Fixed decks - stats chosen so battles actually happen and go both ways,
# arrows chosen so both instant captures and fights are exercised.
const DECK_0 := [
	[120, 40, 40, 0b00000001, Card.AttackType.PHYSICAL],
	[90, 80, 30, 0b00000101, Card.AttackType.MAGICAL],
	[60, 60, 60, 0b00010001, Card.AttackType.FLEXIBLE],
	[200, 20, 20, 0b11111111, Card.AttackType.ASSAULT],
	[30, 150, 90, 0b00001010, Card.AttackType.PHYSICAL],
]
const DECK_1 := [
	[110, 50, 50, 0b00010000, Card.AttackType.PHYSICAL],
	[70, 90, 40, 0b01010000, Card.AttackType.MAGICAL],
	[55, 65, 75, 0b00000100, Card.AttackType.FLEXIBLE],
	[180, 25, 25, 0b10101010, Card.AttackType.ASSAULT],
	[35, 140, 100, 0b00100001, Card.AttackType.PHYSICAL],
]

func _make_hand(spec: Array, owner: int, uid_base: int) -> Array:
	var hand := []
	for i in spec.size():
		var row: Array = spec[i]
		var c := Card.new()
		c.unique_id = uid_base + i
		c.def_id = i
		c.attack_power = row[0]
		c.physical_defense = row[1]
		c.magical_defense = row[2]
		for bit in 8:
			c.arrows[bit] = (int(row[3]) & (1 << bit)) != 0
		c.attack_type = row[4]
		c.owner = owner
		c.original_owner = owner
		hand.append(c)
	return hand

## Cut-down version of BattleScene's turn loop: enough of the real rules
## (blocks, instant captures, GsBattle rolls) to make the digest sensitive to
## a determinism regression, without dragging the scene tree in. Returns the
## hash after every placement.
##
## ponytail: no chain/combo recursion here - the recursion reuses the same
## Board queries and the same GsBattle roll this already covers, so it would
## add length without adding a failure mode this test can't already see.
func _simulate(seed_value: int, swap_move: int = -1) -> Array:
	BattleRng.set_seed(seed_value)
	var board := Board.new()
	board.place_random_blocks(6)

	var hands := [_make_hand(DECK_0, 0, 1000), _make_hand(DECK_1, 1, 2000)]
	var hashes := []

	for turn in 10:
		var side := turn % 2
		var hand: Array = hands[side]

		var index := -1
		for i in hand.size():
			if hand[i] != null:
				index = i
				break
		# swap_move makes the sim play its SECOND available card instead of
		# its first on one specific turn - the "a client did something
		# different" case the referee has to catch.
		if turn == swap_move:
			for i in range(index + 1, hand.size()):
				if hand[i] != null:
					index = i
					break
		if index == -1:
			break

		var card: Card = hand[index]
		var empties := board.empty_slots()
		if empties.is_empty():
			break
		var cell: Array = empties[0]
		board.place_card(card, cell[0], cell[1])
		hand[index] = null

		for other in board.get_capturable_cards(card):
			board.capture(other, card.owner)
		for other in board.get_adjacent_battle_cards(card):
			var res := GsBattle.resolve_battle(card, other)
			if res["winner"] == card:
				board.capture(other, card.owner)
			elif res["winner"] == other:
				board.capture(card, other.owner)

		hashes.append(MatchState.state_hash(board, hands[0], hands[1], turn))

	return hashes

func _ready() -> void:
	var a := _simulate(0xC0FFEE)
	var b := _simulate(0xC0FFEE)
	assert(a.size() >= 8, "the simulation stopped early (%d turns) - not a useful check" % a.size())
	assert(a == b, "same seed + same moves produced different state hashes")

	# The board layout and the combat rolls both come off the seed, so a
	# different seed must move the digest.
	var c := _simulate(0xBADF00D)
	assert(a != c, "a different seed produced the same hash sequence")

	# One player deviating on turn 4 must show up in the digest from that
	# point on - this is the actual cheat-detection property.
	var d := _simulate(0xC0FFEE, 4)
	assert(a.slice(0, 4) == d.slice(0, 4), "hashes diverged before the altered move")
	assert(a[4] != d[4], "an altered move did not change the state hash")

	# A tampered stat on a card already in play must change the digest even
	# if nothing else moved - the save-editing case.
	var board := Board.new()
	var hand := _make_hand(DECK_0, 0, 1000)
	board.place_card(hand[0], 1, 1)
	var clean := MatchState.state_hash(board, hand, [], 0)
	hand[0].attack_power += 1
	assert(MatchState.state_hash(board, hand, [], 0) != clean, "a buffed stat did not change the state hash")

	# The digest must be stable across runs of the same inputs in the same
	# process too (no map iteration order or object address sneaking in).
	hand[0].attack_power -= 1
	assert(MatchState.state_hash(board, hand, [], 0) == clean, "state_hash is not a pure function of the state")

	# The two clients see mirrored ownership - each calls itself player 0 -
	# so the same real match must hash the same from both seats. Without the
	# my_slot rebasing this is the failure that would void every honest match.
	_assert_frames_agree()

	# A decision that changes no card (which target to fight, which card to
	# steal) still has to be distinguishable, or two different choices would
	# "agree".
	var tag_a := MatchState.state_hash(board, hand, [], 0, 0, "target:11")
	var tag_b := MatchState.state_hash(board, hand, [], 0, 0, "target:12")
	assert(tag_a != tag_b, "the decision tag is not part of the hash")
	assert(tag_a != clean, "a tagged hash collided with the untagged one")

func _assert_frames_agree() -> void:
	var seat0_board := Board.new()
	var seat1_board := Board.new()
	var seat0_mine := _make_hand(DECK_0, 0, 1000)
	var seat0_theirs := _make_hand(DECK_1, 1, 2000)
	# The same two decks from the other seat: whoever was "mine" is now
	# "theirs", and every owner flips.
	var seat1_mine := _make_hand(DECK_1, 0, 2000)
	var seat1_theirs := _make_hand(DECK_0, 1, 1000)

	# Same three placements on the same cells, described from each seat.
	var cells := [[0, 0], [1, 2], [3, 1]]
	seat0_board.place_card(seat0_mine[0], cells[0][0], cells[0][1])
	seat0_board.place_card(seat0_theirs[1], cells[1][0], cells[1][1])
	seat0_board.place_card(seat0_mine[2], cells[2][0], cells[2][1])
	seat0_mine[0] = null; seat0_theirs[1] = null; seat0_mine[2] = null

	seat1_board.place_card(seat1_theirs[0], cells[0][0], cells[0][1])
	seat1_board.place_card(seat1_mine[1], cells[1][0], cells[1][1])
	seat1_board.place_card(seat1_theirs[2], cells[2][0], cells[2][1])
	seat1_theirs[0] = null; seat1_mine[1] = null; seat1_theirs[2] = null

	# Blocked cells come off the shared seed, so they match on both sides.
	seat0_board.blocked[2][2] = true
	seat1_board.blocked[2][2] = true

	var h0 := MatchState.state_hash(seat0_board, seat0_mine, seat0_theirs, 3, 0)
	var h1 := MatchState.state_hash(seat1_board, seat1_mine, seat1_theirs, 3, 1)
	assert(h0 == h1, "the two seats hash the same match differently:\n  seat0 %s\n  seat1 %s" % [h0, h1])

	# ...and the rebasing must not be so loose that it hides a real difference.
	seat1_board.slots[0][0].attack_power += 1
	assert(MatchState.state_hash(seat1_board, seat1_mine, seat1_theirs, 3, 1) != h0,
		"seat rebasing swallowed a real state difference")

	print("OK - state hashes agree on identical play and diverge on any deviation")
	get_tree().quit()
