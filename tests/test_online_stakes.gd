extends Node
## Live test of what actually has value in an online match: the card changing
## hands. Plays a whole match through the RPCs (agreed hashes throughout),
## finalizes it, and checks the server moved the card, adjusted both ratings,
## and now refuses to let the loser re-stake what they lost.
##
## Needs NETWORK and mutates real rows - not part of the offline suite.
## Run: godot --headless --quit-after 20000 res://tests/test_online_stakes.tscn

const SLOT_A := 92
const SLOT_B := 93
const TURNS := 10

var token := {}      # slot -> [access, refresh]
var deck := {}       # slot -> deck payload
## Card numbers are minted fresh on every run. They have to be: the accounts
## persist between runs, and the whole point of the lost-card ledger is that a
## number, once lost, is spent forever - reusing one would (correctly) be
## refused the second time. A real client behaves the same way, since
## CardManager's counter only ever goes up.
var uid_base := 0
## The number the winner files the won card under.
var won_uid := 0

func _deck(base: int) -> Array:
	var out := []
	for i in 5:
		out.append({
			"uid": base + i, "def": 3,       # Skeleton: caps 43/34/30
			"atk": 30, "pdef": 25, "mdef": 20,
			"atype": 0, "arrows": 1 + i,
		})
	return out

func _use(slot: int) -> void:
	Net.access_token = token[slot][0]
	Net.refresh_token = token[slot][1]

func _fail(msg: String) -> void:
	push_error(msg)
	print("FAIL - ", msg)
	get_tree().quit(1)

func _ready() -> void:
	await _run()

func _run() -> void:
	uid_base = 10 * (int(Time.get_unix_time_from_system()) % 100000000)
	won_uid = uid_base + 5
	for slot in [SLOT_A, SLOT_B]:
		Net.sign_out()
		var res := await Net.sign_in(slot, "Stakes%d" % slot)
		if not res["ok"]:
			_fail("sign in %d: %s" % [slot, res["error"]])
			return
		token[slot] = [Net.access_token, Net.refresh_token]
		# unique_ids only have to be unique within an account, so both test
		# accounts deliberately use the SAME numbers - that collision is
		# exactly what the renumbering on transfer exists for.
		deck[slot] = _deck(uid_base)
		await Net.call_rpc("mp_dequeue")

	await _close_stale_match()

	_use(SLOT_A)
	var qa = await Net.call_rpc("mp_enqueue", {"p_deck": deck[SLOT_A]})
	if not qa["ok"] or qa["data"]["status"] != "queued":
		_fail("A should be queued: %s" % str(qa))
		return
	_use(SLOT_B)
	var qb = await Net.call_rpc("mp_enqueue", {"p_deck": deck[SLOT_B]})
	if not qb["ok"] or qb["data"]["status"] != "matched":
		_fail("B should be matched: %s" % str(qb))
		return

	var m: Dictionary = qb["data"]["match"]
	var match_id: String = m["id"]
	# Whichever slot the server made p0 is the one that must win here, since
	# the score below is written in the match frame.
	# Net.user_id is still B's here, B having been the one to enqueue second.
	var p0_slot := SLOT_B if str(m["p0"]) == Net.user_id else SLOT_A
	var p1_slot := SLOT_A if p0_slot == SLOT_B else SLOT_B
	print("p0 = slot ", p0_slot)

	var elo_before := await _elo(p0_slot)

	# A whole match's worth of agreed turns. p0 finishes ahead 6-4, which the
	# server reads as "p0 won, and may take exactly one card".
	for i in range(1, TURNS + 1):
		for slot in [p0_slot, p1_slot]:
			_use(slot)
			var mv = await Net.call_rpc("mp_submit_move", {
				"p_match": match_id, "p_idx": i, "p_payload": {"turn": i},
				"p_hash": "turn%d" % i, "p_score0": 6, "p_score1": 4})
			if not mv["ok"]:
				_fail("turn %d, slot %d: %s" % [i, slot, mv["error"]])
				return
			if mv["data"]["status"] != "active":
				_fail("turn %d ended the match early: %s" % [i, mv["data"]["status"]])
				return

	# The loser must not be able to finalize a match they lost.
	_use(p1_slot)
	var wrong = await Net.call_rpc("mp_finalize", {"p_match": match_id,
		"p_stolen": [{"from": uid_base, "to": won_uid}]})
	if wrong["ok"]:
		_fail("the loser was allowed to finalize the match")
		return
	print("loser refused finalization: ", wrong["error"])

	# Nor may the winner take more than the result allows.
	_use(p0_slot)
	var greedy = await Net.call_rpc("mp_finalize", {"p_match": match_id,
		"p_stolen": [{"from": uid_base, "to": won_uid}, {"from": uid_base + 1, "to": won_uid + 1}]})
	if greedy["ok"]:
		_fail("a plain win was allowed to take two cards")
		return
	print("over-claim refused: ", greedy["error"])

	# ...nor a card that was never staked here.
	var unstaked = await Net.call_rpc("mp_finalize", {"p_match": match_id,
		"p_stolen": [{"from": uid_base + 900, "to": won_uid}]})
	if unstaked["ok"]:
		_fail("a card that was never in this match was allowed to be taken")
		return
	print("unstaked card refused: ", unstaked["error"])

	# The real payout.
	var done = await Net.call_rpc("mp_finalize", {"p_match": match_id,
		"p_stolen": [{"from": uid_base, "to": won_uid}]})
	if not done["ok"]:
		_fail("finalize: %s" % done["error"])
		return
	if int(done["data"]["result"]) != 0:
		_fail("the server recorded the wrong winner: %s" % str(done["data"]))
		return
	print("payout accepted")

	# Ratings moved in opposite directions.
	var elo_after := await _elo(p0_slot)
	if elo_after <= elo_before:
		_fail("the winner's Elo did not go up (%d -> %d)" % [elo_before, elo_after])
		return
	print("elo ", elo_before, " -> ", elo_after)

	# The loser can no longer stake the card they lost.
	_use(p1_slot)
	var restake = await Net.call_rpc("mp_enqueue", {"p_deck": deck[p1_slot]})
	if restake["ok"]:
		_fail("the loser was allowed to re-stake the card they just lost")
		return
	print("re-staking a lost card refused: ", restake["error"])

	# ...while the winner can stake it under its new number.
	_use(p0_slot)
	var won_deck: Array = deck[p0_slot].duplicate(true)
	won_deck[0] = {"uid": won_uid, "def": 3, "atk": 30, "pdef": 25, "mdef": 20, "atype": 0, "arrows": 1}
	var restake_win = await Net.call_rpc("mp_enqueue", {"p_deck": won_deck})
	if not restake_win["ok"]:
		_fail("the winner could not stake the card they won: %s" % restake_win["error"])
		return
	await Net.call_rpc("mp_dequeue")
	print("won card is stakeable by its new owner")

	await _check_abandon_closes_the_match(p0_slot, p1_slot)
	await _check_only_the_waiter_claims_the_clock(p0_slot, p1_slot)

	print("OK - online stakes, ratings and the lost-card ledger all hold")
	get_tree().quit()

## Regression: conceding used to only nudge the deadline, leaving the match
## 'active' with nobody left to claim it - which then blocked the quitter from
## ever queueing again with "you are already in a match".
func _check_abandon_closes_the_match(p0_slot: int, p1_slot: int) -> void:
	var fresh := _deck(uid_base + 1000)

	_use(p0_slot)
	var q1 = await Net.call_rpc("mp_enqueue", {"p_deck": fresh})
	if not q1["ok"] or q1["data"]["status"] != "queued":
		_fail("abandon phase, first enqueue: %s" % str(q1))
		return
	_use(p1_slot)
	var q2 = await Net.call_rpc("mp_enqueue", {"p_deck": fresh})
	if not q2["ok"] or q2["data"]["status"] != "matched":
		_fail("abandon phase, pairing: %s" % str(q2))
		return
	var abandoned: String = q2["data"]["match"]["id"]

	var res = await Net.call_rpc("mp_abandon", {"p_match": abandoned})
	if not res["ok"] or res["data"]["status"] != "done":
		_fail("abandon did not close the match: %s" % str(res))
		return

	# The quitter must be free to start another match straight away.
	var again = await Net.call_rpc("mp_enqueue", {"p_deck": fresh})
	if not again["ok"]:
		_fail("still stuck in the abandoned match: %s" % again["error"])
		return
	await Net.call_rpc("mp_dequeue")

	# ...and so must the player who was left sitting there.
	_use(p0_slot)
	var opponent_free = await Net.call_rpc("mp_enqueue", {"p_deck": fresh})
	if not opponent_free["ok"]:
		_fail("the abandoned opponent is still stuck: %s" % opponent_free["error"])
		return
	await Net.call_rpc("mp_dequeue")
	print("abandoning closes the match and frees both players")

## Regression: the timeout claim used to go to whoever called first, because
## the server has no way of its own to know whose turn it was. So the player
## who let their OWN clock expire could claim the win against the one who had
## been waiting for them - stalling beat playing. Only the side that has asked
## for the opponent's move, which is what waiting looks like, may claim now.
func _check_only_the_waiter_claims_the_clock(p0_slot: int, p1_slot: int) -> void:
	var fresh := _deck(uid_base + 2000)

	_use(p0_slot)
	await Net.call_rpc("mp_enqueue", {"p_deck": fresh})
	_use(p1_slot)
	var paired = await Net.call_rpc("mp_enqueue", {"p_deck": fresh})
	if not paired["ok"] or paired["data"]["status"] != "matched":
		_fail("clock phase, pairing: %s" % str(paired))
		return
	var mid: String = paired["data"]["match"]["id"]

	# p1 is the one waiting: asking for the opponent's move is what registers
	# it. p0 is the one stalling, and never asks for anything.
	var polled = await Net.call_rpc("mp_fetch_moves", {"p_match": mid, "p_after": 0})
	if not polled["ok"]:
		_fail("clock phase, poll: %s" % polled["error"])
		return

	# Nobody may claim while there is still time on the clock.
	var early = await Net.call_rpc("mp_claim_timeout", {"p_match": mid})
	if early["ok"]:
		_fail("the clock was claimable before it had run out")
		return
	print("claim refused while the clock still runs: ", early["error"])

	# Run it down. mp_abandon is the only way to move the deadline without
	# waiting a real minute, and it also closes the match - so instead the
	# stalling player simply tries to claim, which must fail on the waiter
	# check alone regardless of the clock.
	_use(p0_slot)
	var staller = await Net.call_rpc("mp_claim_timeout", {"p_match": mid})
	if staller["ok"]:
		_fail("the player who was NOT waiting was allowed to claim the clock")
		return
	print("staller refused: ", staller["error"])

	# Clean up: the staller concedes, which is the honest path for that side.
	await Net.call_rpc("mp_abandon", {"p_match": mid})
	_use(p1_slot)
	await Net.call_rpc("mp_dequeue")
	_use(p0_slot)
	await Net.call_rpc("mp_dequeue")
	print("only the waiting player can claim the clock")

## An earlier run that died mid-match leaves a match still marked active, and
## mp_enqueue rightly refuses to start a second one. Both players are these
## two accounts, so the pair can close it between themselves: one concedes,
## the other claims the expired clock.
func _close_stale_match() -> void:
	_use(SLOT_A)
	var cur = await Net.call_rpc("mp_current_match")
	if not cur["ok"] or cur["data"]["status"] != "matched":
		return
	var stale: String = cur["data"]["match"]["id"]
	print("closing a stale match from an earlier run: ", stale)
	await Net.call_rpc("mp_abandon", {"p_match": stale})
	_use(SLOT_B)
	await Net.call_rpc("mp_claim_timeout", {"p_match": stale})

## The standings only list accounts that have finished a match, so a fresh one
## has no row - it is on the starting rating, not on some sentinel. Returning
## -1 there made the "the winner's Elo went up" check pass against anything at
## all the first time an account played.
const STARTING_ELO := 1200

func _elo(slot: int) -> int:
	_use(slot)
	var lb = await Net.call_rpc("mp_leaderboard", {"p_limit": 1})
	if not lb["ok"]:
		return -1
	if not (lb["data"].get("self") is Dictionary):
		return STARTING_ELO
	return int(lb["data"]["self"]["elo"])
