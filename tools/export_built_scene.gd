extends Node
## Dev-only tool: instances a screen scene whose script still builds its UI
## in _ready(), lets it settle, then serializes the resulting live tree as a
## real .tscn - so Control anchors/offsets/theme overrides are written by
## the engine itself instead of hand-typed. Used once per screen while
## migrating UI construction out of script and into editor-edited scenes:
## export the built tree, then slim the screen's own script down to
## @onready references into it instead of building nodes in code.
## Not shipped, not a test.
##
## Run headless:
##   godot --headless --path "d:\Dropbox\Card Master Godot" res://tools/export_built_scene.tscn -- --scene=res://scenes/menu/Credits.tscn --out=C:/tmp/Credits_built.tscn

func _ready() -> void:
	var scene_path := ""
	var out_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene_path = a.substr("--scene=".length())
		elif a.begins_with("--out="):
			out_path = a.substr("--out=".length())
	if scene_path == "" or out_path == "":
		push_error("usage: --scene=<path> --out=<path>")
		get_tree().quit(1)
		return

	_setup_player()

	var inst: Node = load(scene_path).instantiate()
	get_tree().root.add_child.call_deferred(inst)
	await get_tree().process_frame
	# Let _ready()'s construction, any deferred calls, and one round of
	# font-fit shrinking finish before the tree is snapshotted.
	for i in 5:
		await get_tree().process_frame

	# pack() only serializes descendants whose `owner` is set to the packed
	# root - runtime add_child() never sets it, so every node built in
	# _ready() would otherwise be silently dropped from the saved scene.
	_claim_ownership(inst, inst)

	var packed := PackedScene.new()
	var err := packed.pack(inst)
	if err != OK:
		push_error("pack failed: %s" % err)
		get_tree().quit(1)
		return
	err = ResourceSaver.save(packed, out_path)
	if err != OK:
		push_error("save failed: %s" % err)
		get_tree().quit(1)
		return
	print("saved " + out_path)
	get_tree().quit(0)

func _claim_ownership(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_claim_ownership(child, root)

## Mirrors tools/help_capture.gd's setup - some screens (Shop, Collection,
## StartMenu, Battle) read Game.player and error out or render an empty
## state without one.
func _setup_player() -> void:
	Game.opponent_index = 0
	Game.player = Player.new("Player", 0, AIManager.count())
	Game.player.coins = 250
	for i in 6:
		var def_id: int = (i * 3) % CardManager.defs.size()
		var card := CardManager.generate_card(def_id)
		card.is_on_deck = i < 5
		Game.player.cards.append(card)
	for i in 5:
		Game.player.last_deck[i] = Game.player.cards[i].unique_id
