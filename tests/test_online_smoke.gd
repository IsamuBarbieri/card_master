extends Node
## Live end-to-end smoke test against the real Supabase project: signs in two
## anonymous accounts, has them queue with decks of different power, checks
## they get paired into the same match, exchanges one agreed move, then one
## disagreeing move to confirm the referee voids the match.
##
## Unlike every other test here this one needs NETWORK and mutates real rows,
## so it is not part of the offline suite - run it by hand after changing
## server/schema.sql or scripts/net/Net.gd.
## Run: godot --headless --quit-after 120 res://tests/test_online_smoke.tscn

# Save slots well outside SaveSystem.SLOT_COUNT, so the two throwaway sessions
# can't land on a real player's stored account.
const SLOT_A := 90
const SLOT_B := 91

func _deck(uid_base: int, def_id: int, atk: int) -> Array:
	var out := []
	for i in 5:
		out.append({
			"uid": uid_base + i, "def": def_id,
			"atk": atk, "pdef": atk, "mdef": atk,
			"atype": 0, "arrows": 1 + i,
		})
	return out

func _fail(msg: String) -> void:
	push_error(msg)
	print("FAIL - ", msg)
	get_tree().quit(1)

func _ready() -> void:
	await _run()

func _run() -> void:
	if not Net.is_configured():
		_fail("Net.SUPABASE_URL / SUPABASE_ANON_KEY are empty")
		return

	# --- account A
	var a := await Net.sign_in(SLOT_A, "SmokeA")
	if not a["ok"]:
		_fail("sign in A: %s" % a["error"])
		return
	var token_a := Net.access_token
	var refresh_a := Net.refresh_token
	print("signed in A")

	# Leave any match/queue left over from an interrupted earlier run.
	await Net.call_rpc("mp_dequeue")

	# --- account B
	Net.sign_out()
	var b := await Net.sign_in(SLOT_B, "SmokeB")
	if not b["ok"]:
		_fail("sign in B: %s" % b["error"])
		return
	var token_b := Net.access_token
	var refresh_b := Net.refresh_token
	if token_a == token_b:
		_fail("both slots got the same session - accounts are not per-slot")
		return
	await Net.call_rpc("mp_dequeue")
	print("signed in B")

	# --- an illegal deck must be refused before anything else happens
	var cheat := _deck(500, 0, 200)  # Slime capped at 10 attack
	var cheat_res := await Net.call_rpc("mp_enqueue", {"p_deck": cheat})
	if cheat_res["ok"]:
		_fail("the server accepted a Slime with 200 attack")
		return
	print("rejected over-cap deck: ", cheat_res["error"])

	# --- B queues legitimately. Its deck is deliberately far stronger than A's
	# below: matchmaking takes whoever in the queue is CLOSEST in power, with
	# no maximum distance, so two lonely players always find each other however
	# far apart they are. A window would leave them both waiting forever.
	var deck_b := _deck(200, 3, 30)
	var qb = await Net.call_rpc("mp_enqueue", {"p_deck": deck_b})
	if not qb["ok"]:
		_fail("B enqueue: %s" % qb["error"])
		return
	if qb["data"]["status"] != "queued":
		_fail("B should have been queued, got %s" % qb["data"]["status"])
		return
	print("B queued, power ", qb["data"]["power"])

	# --- A queues and should be paired with B
	Net.access_token = token_a
	Net.refresh_token = refresh_a
	var deck_a := _deck(100, 3, 7)
	var qa = await Net.call_rpc("mp_enqueue", {"p_deck": deck_a})
	if not qa["ok"]:
		_fail("A enqueue: %s" % qa["error"])
		return
	if qa["data"]["status"] != "matched":
		_fail("decks %d and %d apart were left unmatched - matchmaking is not falling back to the closest opponent" % [
			int(qb["data"]["power"]), 105])
		return

	var m: Dictionary = qa["data"]["match"]
	var match_id: String = m["id"]
	print("matched: seed ", m["seed"], " first_player ", m["first_player"])
	if int(m["seed"]) <= 0:
		_fail("the server handed out a useless seed: %s" % str(m["seed"]))
		return

	# --- B sees the same match
	Net.access_token = token_b
	Net.refresh_token = refresh_b
	var cur = await Net.call_rpc("mp_current_match")
	if not cur["ok"] or cur["data"]["status"] != "matched" or cur["data"]["match"]["id"] != match_id:
		_fail("B did not see the same match")
		return
	print("both players see match ", match_id)

	# --- one agreed turn: same hash, same score, from both sides
	var agreed := {"p_match": match_id, "p_idx": 1, "p_payload": {"cell": [0, 0]},
		"p_hash": "deadbeef", "p_score0": 3, "p_score1": 2}
	var mv_b = await Net.call_rpc("mp_submit_move", agreed)
	Net.access_token = token_a
	Net.refresh_token = refresh_a
	var mv_a = await Net.call_rpc("mp_submit_move", agreed)
	if not mv_a["ok"] or not mv_b["ok"]:
		_fail("submit_move failed: %s" % str(mv_a.get("error", mv_b.get("error"))))
		return
	if mv_a["data"]["status"] != "active":
		_fail("an agreed turn should leave the match active, got %s" % mv_a["data"]["status"])
		return
	print("agreed turn accepted")

	# --- the opponent's move is visible to the other side
	var fetched = await Net.call_rpc("mp_fetch_moves", {"p_match": match_id, "p_after": 0})
	if not fetched["ok"] or (fetched["data"]["moves"] as Array).size() != 1:
		_fail("A could not read B's move: %s" % str(fetched))
		return
	print("move relay works")

	# --- now they disagree: the referee must void the match
	var mv2_a = await Net.call_rpc("mp_submit_move", {"p_match": match_id, "p_idx": 2,
		"p_payload": {"cell": [1, 1]}, "p_hash": "honest", "p_score0": 4, "p_score1": 2})
	if not mv2_a["ok"]:
		_fail("second move (A) failed: %s" % mv2_a["error"])
		return
	Net.access_token = token_b
	Net.refresh_token = refresh_b
	var mv2_b = await Net.call_rpc("mp_submit_move", {"p_match": match_id, "p_idx": 2,
		"p_payload": {"cell": [1, 1]}, "p_hash": "tampered", "p_score0": 9, "p_score1": 0})
	if not mv2_b["ok"]:
		_fail("second move (B) failed: %s" % mv2_b["error"])
		return
	if mv2_b["data"]["status"] != "void":
		_fail("mismatched hashes did NOT void the match - the anti-cheat is not working")
		return
	print("mismatched state voided the match")

	# --- leaderboard responds
	var lb = await Net.call_rpc("mp_leaderboard", {"p_limit": 10})
	if not lb["ok"]:
		_fail("leaderboard: %s" % lb["error"])
		return
	print("leaderboard rows: ", (lb["data"]["top"] as Array).size())

	await Net.call_rpc("mp_dequeue")
	print("OK - online smoke test passed")
	get_tree().quit()
