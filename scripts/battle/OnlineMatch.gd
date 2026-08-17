class_name OnlineMatch
extends Node
## The lockstep channel for an online battle, kept out of BattleScene so the
## battle itself stays one readable state machine with a handful of online
## branches rather than two interleaved ones.
##
## How a turn works. Every DECISION a player makes - placing a card, choosing
## which neighbour to fight, choosing which card to steal at the end - is one
## numbered move. Both clients write a row for that number: the one who made
## the decision writes the decision plus a hash of the resulting state, the
## other writes only its own hash once it has replayed the decision. The
## server compares the two hashes (server/schema.sql, mp_submit_move) and
## voids the match if they differ. Neither client is trusted; agreement is.
##
## Everything else about a match - the board layout, the coin toss, every
## combat roll - is derived from the server's seed through BattleRng, so there
## is nothing else to send: the same decisions replayed against the same seed
## produce the same match on both machines.

## How often to ask for the opponent's move. Turn-based, so this is a
## non-issue; a realtime socket would buy tenths of a second for a lot of code.
const POLL_SECONDS := 1.0
## Give up (and let the player back out) rather than spin forever if the
## server keeps answering but the opponent never moves and the deadline logic
## somehow never fires.
const MAX_WAIT_SECONDS := 300.0
## Must match mp_deadline() in server/schema.sql. Used only to predict the
## clock for the countdown on our OWN turn, when nothing is being polled and
## the server therefore has no chance to tell us: every poll overwrites the
## prediction with the server's real deadline, so drift can never accumulate
## into a wrong verdict - the server always decides who actually ran out.
const TURN_SECONDS := 60.0

signal voided
signal opponent_quit
## The server closed the match with us on the losing side while we were still
## waiting - our own clock ran out, or a stale session of ours was conceded
## elsewhere. Distinct from `voided`, where nothing changes hands.
signal lost_by_timeout

var match_id := ""
var my_slot := 0
## Index of the next decision. Both clients count the same decisions in the
## same order, so this stays in step without ever being sent.
var idx := 0
var finished := false
## Unix time the current mover runs out at, 0 before the first move.
var deadline_unix := 0.0

func setup() -> void:
	match_id = str(Game.online_match.get("id", ""))
	my_slot = int(Game.online_match.get("my_slot", 0))
	deadline_unix = Time.get_unix_time_from_system() + TURN_SECONDS

## Whole seconds left on the current turn, floored at 0. -1 when there is no
## clock to show (match over, or not started).
func seconds_left() -> int:
	if finished or deadline_unix <= 0.0:
		return -1
	return maxi(0, int(ceil(deadline_unix - Time.get_unix_time_from_system())))

## Board control in the match frame (p0's count first), so both clients report
## the same numbers for the same board - the server reads the winner off this.
func match_score(board: Board) -> Array:
	var mine := board.count_cards(0)
	var theirs := board.count_cards(1)
	return [mine, theirs] if my_slot == 0 else [theirs, mine]

func state_hash(board: Board, player_hand: Array, cpu_hand: Array, tag: String) -> String:
	return MatchState.state_hash(board, player_hand, cpu_hand, idx, my_slot, tag)

## Records a decision this player made. Call it AFTER applying the decision
## locally, so the hash describes the state the opponent has to arrive at too.
func submit(payload: Dictionary, board: Board, player_hand: Array, cpu_hand: Array, tag: String) -> bool:
	if finished:
		return false
	var score := match_score(board)
	var res := await Net.call_rpc("mp_submit_move", {
		"p_match": match_id, "p_idx": idx, "p_payload": payload,
		"p_hash": state_hash(board, player_hand, cpu_hand, tag),
		"p_score0": score[0], "p_score1": score[1],
	})
	idx += 1
	# The server restarted the clock for whoever moves next; mirror that here
	# so the countdown doesn't sit at zero until the next poll corrects it.
	deadline_unix = Time.get_unix_time_from_system() + TURN_SECONDS
	if not res["ok"]:
		_die(res["error"])
		return false
	if str(res["data"]["status"]) == "void":
		_void()
		return false
	return true

## Waits for the opponent's decision at the current index and returns its
## payload ({} if the match ended while waiting). The caller applies it and
## then calls submit() with its own hash for the same index.
## `allow_timeout_claim` is false once the board is full and we are only
## waiting for the winner to choose their prize: the move clock stopped
## advancing with the last placement, so a slow-but-honest winner would
## otherwise be robbed of the match by their own victory screen.
func receive(allow_timeout_claim: bool = true) -> Dictionary:
	if finished:
		return {}
	var waited := 0.0
	while not finished:
		var res := await Net.call_rpc("mp_fetch_moves", {"p_match": match_id, "p_after": idx - 1})
		if finished:
			return {}
		if not res["ok"]:
			_die(res["error"])
			return {}

		# The awaited move is checked BEFORE the match status, not after: the
		# winner announces their prize and finalizes in the same breath, so by
		# the time this poll lands the match is often already 'done' with the
		# move sitting right there. Reading the status first made every normal
		# payout look to the loser like the opponent had walked out.
		for entry in (res["data"]["moves"] as Array):
			if int(entry["idx"]) == idx:
				return entry["payload"]

		var status := str(res["data"]["status"])
		if status == "void":
			_void()
			return {}
		if status == "done":
			# Closed without the move we were waiting for. Which way it went is
			# the server's to say, not ours.
			finished = true
			var winner := int(res["data"].get("result", -1))
			if winner >= 0 and winner == my_slot:
				opponent_quit.emit()
			else:
				lost_by_timeout.emit()
			return {}

		# Their clock ran out: claim the win rather than keep waiting. The
		# opponent's own client calls mp_abandon when its window closes, which
		# brings this deadline forward so an obvious quit isn't a 90s stare.
		var deadline := Time.get_unix_time_from_datetime_string(str(res["data"]["deadline"]))
		if deadline > 0:
			deadline_unix = deadline
		if allow_timeout_claim and deadline > 0 and Time.get_unix_time_from_system() > deadline:
			var claim := await Net.call_rpc("mp_claim_timeout", {"p_match": match_id})
			if claim["ok"]:
				finished = true
				opponent_quit.emit()
				return {}

		waited += POLL_SECONDS
		if waited > MAX_WAIT_SECONDS:
			_die("the opponent stopped responding")
			return {}
		await get_tree().create_timer(POLL_SECONDS).timeout
	return {}

## Winner-only. Hands the server the cards being taken; it checks they were
## actually staked in this match and that the count matches the agreed score
## (1 for a win, 5 for a perfect).
func finalize(stolen: Array) -> Dictionary:
	if match_id == "":
		return {"ok": false, "error": "no match"}
	finished = true
	return await Net.call_rpc("mp_finalize", {"p_match": match_id, "p_stolen": stolen})

## The opponent sent something that isn't a legal move (a card that isn't in
## their hand, an occupied cell). A correct client cannot produce this, so
## treat it exactly like a hash mismatch: nothing changes hands.
func reject_illegal(what: String) -> void:
	push_warning("illegal move from the opponent: " + what)
	_void()

## Concede without waiting out the clock - window closed, or Forfeit pressed.
func abandon() -> void:
	if match_id == "" or finished:
		return
	finished = true
	await Net.call_rpc("mp_abandon", {"p_match": match_id})

func _void() -> void:
	finished = true
	voided.emit()

func _die(reason: String) -> void:
	push_warning("online match ended: " + reason)
	finished = true
	voided.emit()
