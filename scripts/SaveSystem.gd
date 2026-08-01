class_name SaveSystem
extends RefCounted
## Port of SaveSystem.cs. Static utility, same as the reference (no
## instance state) - Godot 4 GDScript supports `static func` directly, so
## no autoload wrapper is needed.
##
## Deliberate deviations from the reference, both pure implementation
## plumbing with no behavioral difference:
## - One save file per slot (Godot's store_var/get_var, a Dictionary of
##   plain types) instead of the reference's hand-packed binary layout
##   (byte offsets, BlockCopy, manual hash checksum for corruption
##   detection). Nothing reads these files but this game, so the exact byte
##   layout isn't a real contract worth the bug surface of reimplementing
##   by hand.
## - AIManager.AIPrepareSet's persistent per-AI card pools (topCards/
##   genericCards/capturedCards) aren't ported (see BattleScene.gd's header
##   comment - CPU hands are generated fresh from the opponent's First Set
##   range each battle instead), so there's nothing to save for those. Only
##   the per-AI `defeated` flag persists, folded into the player save file
##   instead of the reference's one ai{id}.dat file per AI.
##
## Ported as-is: 3 save slots, matchStarted flag for rage-quit detection,
## CardManager's unique_id counter (so post-load card generation doesn't
## collide with the save's own card ids), delete-and-recreate on new game.

const SAVE_ROOT := "user://"
const PLAYER_FILE := "player.save"
const SLOT_COUNT := 3

static func _slot_dir(slot: int) -> String:
	return SAVE_ROOT + "slot%d" % slot

static func _player_path(slot: int) -> String:
	return _slot_dir(slot) + "/" + PLAYER_FILE

static func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(_player_path(slot))

## Port of CheckForExistingPlayers(): returns an array of 3 entries, each
## the saved player's name or null if that slot is empty.
static func check_existing_players() -> Array:
	var names: Array = [null, null, null]
	for i in SLOT_COUNT:
		if slot_exists(i):
			var data = _read_save(i)
			if data != null:
				names[i] = data.get("name")
	return names

static func create_new_player(slot: int, player_name: String) -> Player:
	delete_player(slot)
	DirAccess.make_dir_recursive_absolute(_slot_dir(slot))

	var player := Player.new(player_name, slot, AIManager.count())
	player.generate_base_set()
	save_player(player)
	return player

static func delete_player(slot: int) -> void:
	var dir_path := _slot_dir(slot)
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dir := DirAccess.open(dir_path)
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(dir_path)

static func save_player(player: Player) -> void:
	var cards_data := []
	for card in player.cards:
		cards_data.append(_card_to_dict(card))

	var defeated := []
	for i in AIManager.count():
		defeated.append(AIManager.get_ai(i).defeated)

	var data := {
		"name": player.player_name,
		"cards": cards_data,
		"available_opponents": player.available_opponents,
		"coins": player.coins,
		"match_started": player.match_started,
		"next_uid": CardManager.next_uid(),
		"ai_defeated": defeated,
	}

	DirAccess.make_dir_recursive_absolute(_slot_dir(player.save_slot))
	var path := _player_path(player.save_slot)
	var path_tmp := path + ".tmp"

	var f := FileAccess.open(path_tmp, FileAccess.WRITE)
	f.store_var(data)
	f.close()

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(path_tmp, path)

static func load_player(slot: int) -> Player:
	var data = _read_save(slot)
	if data == null:
		return null

	var player := Player.new(data["name"], slot, AIManager.count())
	player.available_opponents = data["available_opponents"]
	player.coins = data["coins"]
	player.match_started = data["match_started"]

	for card_data in data["cards"]:
		player.cards.append(_card_from_dict(card_data))

	CardManager.set_next_uid(data["next_uid"])

	# Reset first: AIManager's roster is a single global list shared by
	# every save slot, so switching slots must clear whatever the
	# previously loaded slot left behind before applying this slot's data.
	var defeated: Array = data.get("ai_defeated", [])
	for i in AIManager.count():
		AIManager.get_ai(i).defeated = i < defeated.size() and defeated[i]

	return player

static func _read_save(slot: int) -> Variant:
	var path := _player_path(slot)
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var data = f.get_var()
	f.close()
	return data if data is Dictionary else null

static func _card_to_dict(card: Card) -> Dictionary:
	return {
		"uid": card.unique_id,
		"def_id": card.def_id,
		"atk": card.attack_power,
		"pdef": card.physical_defense,
		"mdef": card.magical_defense,
		"atype": card.attack_type,
		"arrows": card.arrows,
		"fav": card.is_favourite,
		# is_on_deck deliberately not saved - matches the reference (not in
		# CardStatsToByteArray either), since it's re-derived fresh by
		# DeckSelect at the start of every deck-select session.
	}

static func _card_from_dict(d: Dictionary) -> Card:
	var card := Card.new()
	card.unique_id = d["uid"]
	card.def_id = d["def_id"]
	card.attack_power = d["atk"]
	card.physical_defense = d["pdef"]
	card.magical_defense = d["mdef"]
	card.attack_type = d["atype"]
	card.arrows = d["arrows"]
	card.is_favourite = d["fav"]
	return card
