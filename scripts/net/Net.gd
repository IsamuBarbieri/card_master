extends Node
## Autoload. Everything this game says to the outside world goes through here.
##
## Supabase over plain HTTPRequest - no addon, no Realtime socket. The game is
## turn-based, so a 1s poll is indistinguishable from a push and costs a
## fraction of the code a Phoenix channel client would.
## ponytail: swap the poll for Realtime only if turn latency ever actually
## bothers a player.
##
## SECURITY: SUPABASE_ANON_KEY below is meant to be public - it is shipped in
## every client and grants nothing on its own. All it does is let a request
## reach the mp_* SQL functions in server/schema.sql, which enforce every rule
## themselves (row level security denies direct table access outright). Do NOT
## put the service_role key here; that one really is a master key.

## Fill these in from your Supabase project: Settings -> API.
## Anonymous sign-ins must also be enabled under Authentication -> Providers.
const SUPABASE_URL := "https://usgpvabliwhidfaqutdu.supabase.co"
const SUPABASE_ANON_KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVzZ3B2YWJsaXdoaWRmYXF1dGR1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY5NTMyNjcsImV4cCI6MjEwMjUyOTI2N30.lc0WeWZ4G9AkBm2KrLldkNu88QJTFxuPjYanvxkC0dQ"

## One account per SAVE SLOT, not per device: Card.unique_id is a per-slot
## counter (SaveSystem's next_uid), so two slots on the same machine number
## their cards identically and would collide inside one account's card
## registry. Stored next to the slot's player.save.
const SESSION_FILE := "net.save"

signal auth_changed(signed_in: bool)

var access_token := ""
var refresh_token := ""
var user_id := ""
var _slot := -1

func is_configured() -> bool:
	return SUPABASE_URL != "" and SUPABASE_ANON_KEY != ""

func is_signed_in() -> bool:
	return access_token != ""

func _session_path(slot: int) -> String:
	return "user://slot%d/%s" % [slot, SESSION_FILE]

# ------------------------------------------------------------------ requests

## One HTTPRequest per call, freed on completion. Reusing a single node would
## mean serializing or tracking concurrent calls by hand; creating one is a
## couple of microseconds and removes the whole class of "two requests raced
## on the same node" bug.
func _request(url: String, headers: PackedStringArray, method: int, body: String) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "request failed to start (%d)" % err}

	var result: Array = await http.request_completed
	http.queue_free()

	var code: int = result[1]
	var text := (result[3] as PackedByteArray).get_string_from_utf8()
	var parsed = JSON.parse_string(text) if text != "" else null

	if code < 200 or code >= 300:
		# Supabase reports both auth errors and raised plpgsql exceptions as
		# JSON with a message/msg field - surface that rather than a bare code,
		# since those messages are the server's rule violations ("card X has
		# stats above its species cap") and are what makes failures debuggable.
		var msg := "HTTP %d" % code
		if parsed is Dictionary:
			msg = str(parsed.get("message", parsed.get("msg", parsed.get("error_description", msg))))
		return {"ok": false, "code": code, "error": msg}

	return {"ok": true, "data": parsed}

func _auth_headers() -> PackedStringArray:
	return PackedStringArray([
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + (access_token if access_token != "" else SUPABASE_ANON_KEY),
		"Content-Type: application/json",
	])

# --------------------------------------------------------------------- auth

## Signs the given save slot in, reusing its stored session when there is one.
## Safe to call every time the online menu opens.
func sign_in(slot: int, player_name: String) -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": "online is not configured in this build"}

	_slot = slot
	if access_token == "" and _load_session(slot):
		# A stored refresh token outlives the access token, so try it first;
		# a failure here just falls through to a fresh anonymous account.
		var refreshed := await _refresh()
		if not refreshed["ok"]:
			access_token = ""
			refresh_token = ""

	if access_token == "":
		var res := await _request(
			SUPABASE_URL + "/auth/v1/signup",
			_auth_headers(), HTTPClient.METHOD_POST, "{}")
		if not res["ok"]:
			return res
		if not _adopt_session(res["data"]):
			return {"ok": false, "error": "the server returned no session"}
		_save_session(slot)

	var profile := await call_rpc("mp_profile_ensure", {"p_name": player_name})
	if not profile["ok"]:
		return profile
	auth_changed.emit(true)
	return {"ok": true, "data": profile["data"]}

## Is this display name still free? Answerable without a session - the game
## asks while the player is naming a save slot that has no account yet - so
## this goes out on the anon key alone.
func is_name_available(candidate: String) -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": "online is not configured in this build"}
	var res := await _request(SUPABASE_URL + "/rest/v1/rpc/mp_name_available",
		PackedStringArray([
			"apikey: " + SUPABASE_ANON_KEY,
			"Authorization: Bearer " + SUPABASE_ANON_KEY,
			"Content-Type: application/json",
		]), HTTPClient.METHOD_POST, JSON.stringify({"p_name": candidate}))
	if not res["ok"]:
		return res
	return {"ok": true, "available": bool(res["data"])}

## Brings the local collection in line with the server's record of what this
## account has lost. Returns how many cards were removed.
##
## Needed because a card can leave an account while its owner isn't looking: a
## timeout win is claimed by the winner, which may be long after the loser
## closed the game. The loser's save kept the card, the server did not, and
## every deck containing it was refused with "card N no longer belongs to
## you" - permanently, since there was no path that would ever remove it.
func reconcile_lost_cards(player: Player) -> int:
	if not is_signed_in() or player == null:
		return 0
	var res := await call_rpc("mp_lost_cards")
	if not res["ok"] or not (res["data"] is Array):
		return 0

	var lost := {}
	for uid in res["data"]:
		lost[int(uid)] = true
	if lost.is_empty():
		return 0

	var removed := 0
	for i in range(player.cards.size() - 1, -1, -1):
		if lost.has(player.cards[i].unique_id):
			player.cards.remove_at(i)
			removed += 1
	if removed > 0:
		# The deck may have been holding one of them.
		for slot in player.last_deck.size():
			if lost.has(player.last_deck[slot]):
				player.last_deck[slot] = -1
		SaveSystem.save_player(player)
	return removed

## Gives the slot's online account back, freeing its name. Called before the
## local save is erased - the session file lives inside the slot folder that
## erase is about to remove.
func delete_account(slot: int) -> Dictionary:
	if not is_configured():
		return {"ok": true}
	if not FileAccess.file_exists(_session_path(slot)):
		return {"ok": true}  # slot never went online, nothing to give back
	sign_out()
	# The profile lookup inside sign_in may well fail here (a slot whose
	# account was half-created has no profile row to fetch) - what matters is
	# that it left us holding a valid token for the account being deleted.
	await sign_in(slot, "")
	if access_token == "":
		return {"ok": false, "error": "could not reach this slot's account"}
	var res := await call_rpc("mp_delete_account")
	sign_out()
	return res

func sign_out() -> void:
	access_token = ""
	refresh_token = ""
	user_id = ""
	auth_changed.emit(false)

func _refresh() -> Dictionary:
	if refresh_token == "":
		return {"ok": false, "error": "no refresh token"}
	var res := await _request(
		SUPABASE_URL + "/auth/v1/token?grant_type=refresh_token",
		_auth_headers(), HTTPClient.METHOD_POST,
		JSON.stringify({"refresh_token": refresh_token}))
	if res["ok"] and _adopt_session(res["data"]):
		_save_session(_slot)
		return {"ok": true}
	return {"ok": false, "error": res.get("error", "refresh failed")}

func _adopt_session(data) -> bool:
	if not (data is Dictionary) or not data.has("access_token"):
		return false
	access_token = str(data["access_token"])
	refresh_token = str(data.get("refresh_token", refresh_token))
	var user = data.get("user")
	if user is Dictionary:
		user_id = str(user.get("id", user_id))
	return true

func _save_session(slot: int) -> void:
	if slot < 0:
		return
	DirAccess.make_dir_recursive_absolute("user://slot%d" % slot)
	var f := FileAccess.open(_session_path(slot), FileAccess.WRITE)
	if f == null:
		return
	f.store_var({"refresh_token": refresh_token, "user_id": user_id})

func _load_session(slot: int) -> bool:
	if not FileAccess.file_exists(_session_path(slot)):
		return false
	var f := FileAccess.open(_session_path(slot), FileAccess.READ)
	if f == null:
		return false
	var data = f.get_var()
	if not (data is Dictionary):
		return false
	refresh_token = str(data.get("refresh_token", ""))
	user_id = str(data.get("user_id", ""))
	return refresh_token != ""

# ---------------------------------------------------------------------- rpc

## Calls one of the mp_* functions in server/schema.sql. Retries once through
## a token refresh on a 401, because an access token expiring mid-match would
## otherwise read to the player as a random disconnect.
##
## Named call_rpc, not rpc: Node already has an rpc() (Godot's own multiplayer
## remote-call), and shadowing it on an autoload is a parse error.
func call_rpc(fn: String, args: Dictionary = {}) -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": "online is not configured in this build"}

	var url := SUPABASE_URL + "/rest/v1/rpc/" + fn
	var res := await _request(url, _auth_headers(), HTTPClient.METHOD_POST, JSON.stringify(args))
	if not res["ok"] and res.get("code", 0) == 401:
		var refreshed := await _refresh()
		if refreshed["ok"]:
			res = await _request(url, _auth_headers(), HTTPClient.METHOD_POST, JSON.stringify(args))
	return res

# ------------------------------------------------------------------- helpers

## Serializes a battle deck the way server/schema.sql's mp_validate_deck
## expects it. Kept here next to the transport so the wire format has exactly
## one definition on the client side.
func deck_payload(cards: Array) -> Array:
	var out := []
	for card in cards:
		if card == null:
			continue
		out.append({
			"uid": card.unique_id,
			"def": card.def_id,
			"atk": card.attack_power,
			"pdef": card.physical_defense,
			"mdef": card.magical_defense,
			"atype": card.attack_type,
			"arrows": MatchState.arrow_mask(card),
		})
	return out

## Rebuilds the opponent's hand from the deck json the server sent back. The
## stats are the ones the server validated, not anything the opponent's client
## claimed afterwards.
func deck_from_payload(payload: Array) -> Array:
	var out: Array = []
	for entry in payload:
		var card := Card.new()
		card.unique_id = int(entry["uid"])
		card.def_id = int(entry["def"])
		card.attack_power = int(entry["atk"])
		card.physical_defense = int(entry["pdef"])
		card.magical_defense = int(entry["mdef"])
		card.attack_type = int(entry["atype"])
		var mask := int(entry["arrows"])
		for i in 8:
			card.arrows[i] = (mask & (1 << i)) != 0
		out.append(card)
	return out
