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
##   genericCards/capturedCards) are folded into the single per-slot player
##   save file (one entry per AI id) instead of the reference's one
##   ai{id}.dat file per AI - same data, one file instead of up to 18.
##
## Ported as-is: 3 save slots, matchStarted flag for rage-quit detection,
## CardManager's unique_id counter (so post-load card generation doesn't
## collide with the save's own card ids), delete-and-recreate on new game.

const SAVE_ROOT := "user://"
const PLAYER_FILE := "player.save"
const SLOT_COUNT := 3
## Global (not per-slot) settings - language and audio volumes are app-level
## preferences, not part of any one player's save data, so they live outside
## the slotN/ folders and load once at Game's own _ready() regardless of
## which slot (if any) gets picked afterward.
const SETTINGS_FILE := "user://settings.save"

static func _slot_dir(slot: int) -> String:
	return SAVE_ROOT + "slot%d" % slot

static func _player_path(slot: int) -> String:
	return _slot_dir(slot) + "/" + PLAYER_FILE

static func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(_player_path(slot))

## Slot-select summary (name/card count/wins/saved_at) without the cost of a
## full load_player - StartMenu's slot list needs display-only data.
static func slot_summary(slot: int) -> Dictionary:
	var data = _read_save(slot)
	if data == null:
		return {}

	var seen := {}
	var card_defs := []
	for card_data in data["cards"]:
		var def_id: int = card_data["def_id"]
		if not seen.has(def_id):
			seen[def_id] = true
			card_defs.append(def_id)
	card_defs.sort()  # ascending def_id - e.g. Slime (id 0) always leads if owned

	return {
		"name": data.get("name"),
		"card_count": data["cards"].size(),
		"wins": data.get("matches_won", 0),
		"coins": data.get("coins", 0),
		"saved_at": data.get("saved_at", 0),
		"card_defs": card_defs,
	}

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

	var ai_data := {}
	for i in AIManager.count():
		var ai: AIManager.AIData = AIManager.get_ai(i)
		var entry := {"defeated": ai.defeated}
		if ai.dynamic_data_loaded:
			entry["top"] = _cards_to_array(ai.top_cards)
			entry["generic"] = _cards_to_array(ai.generic_cards)
			entry["captured"] = _cards_to_array(ai.captured_cards)
		ai_data[i] = entry

	var data := {
		"name": player.player_name,
		"cards": cards_data,
		"available_opponents": player.available_opponents,
		"coins": player.coins,
		"match_started": player.match_started,
		"matches_won": player.matches_won,
		"last_deck": player.last_deck,
		"last_opponent_index": player.last_opponent_index,
		"next_uid": CardManager.next_uid(),
		"ai_data": ai_data,
		"saved_at": Time.get_unix_time_from_system(),
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
	player.matches_won = data.get("matches_won", 0)
	player.last_deck = data.get("last_deck", [-1, -1, -1, -1, -1])
	player.last_opponent_index = data.get("last_opponent_index", -1)

	for card_data in data["cards"]:
		player.cards.append(_card_from_dict(card_data))

	CardManager.set_next_uid(data["next_uid"])

	# Reset first: AIManager's roster is a single global list shared by
	# every save slot, so switching slots must clear whatever the
	# previously loaded slot left behind before applying this slot's data.
	var ai_data: Dictionary = data.get("ai_data", {})
	for i in AIManager.count():
		var ai: AIManager.AIData = AIManager.get_ai(i)
		ai.defeated = false
		ai.dynamic_data_loaded = false
		ai.top_cards = []
		ai.generic_cards = []
		ai.captured_cards = []

		var entry = ai_data.get(i)
		if entry == null:
			continue
		ai.defeated = entry.get("defeated", false)
		if entry.has("top"):
			ai.top_cards = _array_to_cards(entry["top"])
			ai.generic_cards = _array_to_cards(entry["generic"])
			ai.captured_cards = _array_to_cards(entry["captured"])
			ai.dynamic_data_loaded = true

	return player

static func _read_save(slot: int) -> Variant:
	var path := _player_path(slot)
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var data = f.get_var()
	f.close()
	return data if data is Dictionary else null

static func _cards_to_array(cards: Array) -> Array:
	var out := []
	for c in cards:
		out.append(_card_to_dict(c))
	return out

static func _array_to_cards(arr: Array) -> Array:
	var out := []
	for d in arr:
		out.append(_card_from_dict(d))
	return out

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
		"zero_price": card.has_zero_price,
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
	card.has_zero_price = d.get("zero_price", false)
	return card

## Port of SaveShopCard/LoadShopCard/CheckForExistingAi's shop-card path:
## the 4 rotating offer slots persist independently of the main player save
## (reference: one shopcard{index}.dat per slot; here, one shop.save per
## save slot holding all 4). Each entry is null (never generated/inactive)
## or {"card": Card, "time": unix seconds} - `time` drives the once-a-day
## rotation in Shop.gd.
static func _shop_path(slot: int) -> String:
	return _slot_dir(slot) + "/shop.save"

static func save_shop_cards(slot: int, entries: Array) -> void:
	var data := []
	for e in entries:
		if e == null:
			data.append(null)
		else:
			data.append({"card": _card_to_dict(e["card"]), "time": e["time"]})

	DirAccess.make_dir_recursive_absolute(_slot_dir(slot))
	var path := _shop_path(slot)
	var path_tmp := path + ".tmp"
	var f := FileAccess.open(path_tmp, FileAccess.WRITE)
	f.store_var(data)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(path_tmp, path)

static func load_shop_cards(slot: int) -> Array:
	var path := _shop_path(slot)
	if not FileAccess.file_exists(path):
		return [null, null, null, null]
	var f := FileAccess.open(path, FileAccess.READ)
	var data = f.get_var()
	f.close()
	if not (data is Array):
		return [null, null, null, null]

	var out := []
	for e in data:
		if e == null:
			out.append(null)
		else:
			out.append({"card": _card_from_dict(e["card"]), "time": e["time"]})
	while out.size() < 4:
		out.append(null)
	return out

static func save_settings() -> void:
	var data := {
		"language": Game.language,
		"music_volume": Game.music_volume,
		"sfx_volume": Game.sfx_volume,
	}
	var path_tmp := SETTINGS_FILE + ".tmp"
	var f := FileAccess.open(path_tmp, FileAccess.WRITE)
	f.store_var(data)
	f.close()
	if FileAccess.file_exists(SETTINGS_FILE):
		DirAccess.remove_absolute(SETTINGS_FILE)
	DirAccess.rename_absolute(path_tmp, SETTINGS_FILE)

static func load_settings() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS_FILE):
		return {}
	var f := FileAccess.open(SETTINGS_FILE, FileAccess.READ)
	var data = f.get_var()
	f.close()
	return data if data is Dictionary else {}
