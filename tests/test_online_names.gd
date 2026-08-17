extends Node
## Live test of the unique-name rule: a name can be checked before an account
## exists, claiming it takes it out of circulation, a second account cannot
## have it, the name is fixed once chosen, and deleting the account gives the
## name back.
##
## Needs NETWORK and mutates real rows - not part of the offline suite.
## Run: godot --headless --quit-after 20000 res://tests/test_online_names.tscn

const SLOT_A := 94
const SLOT_B := 95

func _fail(msg: String) -> void:
	push_error(msg)
	print("FAIL - ", msg)
	get_tree().quit(1)

func _cleanup() -> void:
	for slot in [SLOT_A, SLOT_B]:
		await Net.delete_account(slot)
		DirAccess.remove_absolute("user://slot%d/net.save" % slot)

func _ready() -> void:
	await _run()

func _run() -> void:
	# Names are claimed for good, so every run needs one nobody has had before.
	var name_a := "TestName%d" % (Time.get_unix_time_from_system() as int)
	var name_b := name_a + "B"
	await _cleanup()

	# --- checkable with no account at all, which is when the game asks
	Net.sign_out()
	var free_check := await Net.is_name_available(name_a)
	if not free_check["ok"]:
		_fail("availability check without a session: %s" % free_check["error"])
		return
	if not free_check["available"]:
		_fail("a freshly minted name was reported as taken")
		return
	print("unclaimed name reads as free, with no session")

	var blank := await Net.is_name_available("   ")
	if not blank["ok"] or blank["available"]:
		_fail("a blank name was accepted as available")
		return

	# --- claiming it
	var claimed := await Net.sign_in(SLOT_A, name_a)
	if not claimed["ok"]:
		_fail("claiming a free name: %s" % claimed["error"])
		return
	if str(claimed["data"]["name"]) != name_a:
		_fail("the account was created under the wrong name: %s" % str(claimed["data"]))
		return
	print("claimed ", name_a)

	var taken := await Net.is_name_available(name_a)
	if not taken["ok"] or taken["available"]:
		_fail("a claimed name still reads as free")
		return
	print("claimed name now reads as taken")

	# Case sensitive by design: "Test" and "test" are two different players.
	var other_case := await Net.is_name_available(name_a.to_lower())
	if not other_case["ok"] or not other_case["available"]:
		_fail("a differently-cased spelling was treated as the same name")
		return
	print("a differently-cased spelling is a separate name")

	# --- nobody else may have it
	Net.sign_out()
	var stolen := await Net.sign_in(SLOT_B, name_a)
	if stolen["ok"]:
		_fail("a second account was allowed to take a name already in use")
		return
	print("second account refused: ", stolen["error"])

	# That failed sign-in still minted an anonymous user with no profile;
	# give it a name of its own so the slot is in a known state.
	var second := await Net.sign_in(SLOT_B, name_b)
	if not second["ok"]:
		_fail("second account could not claim its own name: %s" % second["error"])
		return

	# --- names are fixed: asking for a different one is ignored, not applied
	var renamed := await Net.call_rpc("mp_profile_ensure", {"p_name": name_b + "Renamed"})
	if not renamed["ok"]:
		_fail("profile lookup after creation: %s" % renamed["error"])
		return
	if str(renamed["data"]["name"]) != name_b:
		_fail("the name changed to %s - renaming should be impossible" % str(renamed["data"]["name"]))
		return
	print("name is fixed once chosen")

	# --- deleting the account frees the name again
	var deleted := await Net.delete_account(SLOT_A)
	if not deleted["ok"]:
		_fail("deleting the account: %s" % deleted["error"])
		return
	Net.sign_out()
	var freed := await Net.is_name_available(name_a)
	if not freed["ok"] or not freed["available"]:
		_fail("the name was not released when its account was deleted")
		return
	print("deleting the account released the name")

	await _cleanup()
	print("OK - names are unique, fixed once chosen, and released on delete")
	get_tree().quit()
