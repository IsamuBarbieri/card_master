extends Node
## Dev-only tool: instances a converted screen scene, lets its script run and
## assign real text (StringTable, in Italian by default) to every label/
## button, then patches those live text values back into the SOURCE .tscn
## file as literal `text = "..."` preview content - purely so the scene
## reads/edits naturally in the Godot editor instead of showing blank boxes.
## Harmless at runtime: every screen's own script always overwrites this text
## at _ready() based on the player's actual language, so baking a snapshot
## here changes nothing about how the game behaves.
## Not shipped, not a test.
##
## Run headless:
##   godot --headless --path "d:\Dropbox\Card Master Godot" res://tools/bake_preview_text.tscn -- --scene=res://scenes/menu/Help.tscn

func _ready() -> void:
	var scene_path := ""
	var out_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene_path = a.substr("--scene=".length())
		elif a.begins_with("--out="):
			out_path = a.substr("--out=".length())
	if scene_path == "":
		push_error("usage: --scene=<path> [--out=<path>, defaults to overwriting --scene]")
		get_tree().quit(1)
		return
	if out_path == "":
		out_path = scene_path

	Game.language = StringTable.LANGUAGE_BY_LOCALE["it"]
	_setup_player()

	var inst: Node = load(scene_path).instantiate()
	get_tree().root.add_child.call_deferred(inst)
	for i in 6:
		await get_tree().process_frame

	var texts := {}  # NodePath string -> text
	_collect(inst, inst, texts)

	var abs_in: String = ProjectSettings.globalize_path(scene_path)
	var f := FileAccess.open(abs_in, FileAccess.READ)
	var content := f.get_as_text()
	f.close()

	var patched := _patch(content, texts)
	var abs_out: String = out_path if out_path.begins_with("res://") == false else ProjectSettings.globalize_path(out_path)
	f = FileAccess.open(abs_out, FileAccess.WRITE)
	f.store_string(patched)
	f.close()

	print("baked ", texts.size(), " text values from ", scene_path, " into ", out_path)
	get_tree().quit(0)

## Any node with a non-empty "text" property. Internal children
## FixedSizeLabel/FixedSizeButton create for themselves at _init() have no
## name matching a block in the hand-authored .tscn (those files never
## include them - see export_built_scene.gd's own doc comment on why), so
## _patch() below simply finds no matching [node] block for those paths and
## leaves them alone; no special-casing needed here.
func _collect(node: Node, root: Node, out: Dictionary) -> void:
	for child in node.get_children():
		var text: Variant = child.get("text")
		if text is String and text != "":
			out[str(root.get_path_to(child))] = text
		_collect(child, root, out)

## Inserts/replaces a `text = "..."` line right after each [node] block's own
## header line, for every block whose NodePath is in `texts`. Splits with a
## capturing lookahead so every "[node " delimiter this finds is preserved
## in-place in the pieces themselves - nothing gets manually re-prefixed on
## rejoin, which is what corrupted the file the first time this was tried.
func _patch(content: String, texts: Dictionary) -> String:
	# RegEx.split() on a zero-width lookahead pattern hangs (confirmed) -
	# find each "[node " start position by hand and slice between them
	# instead of asking the regex engine to split on a zero-length match.
	var regex := RegEx.new()
	regex.compile("(?m)^\\[node ")
	var matches := regex.search_all(content)
	var parts := PackedStringArray()
	var prev := 0
	for m in matches:
		if m.get_start() > prev:
			parts.append(content.substr(prev, m.get_start() - prev))
		prev = m.get_start()
	parts.append(content.substr(prev))
	var out := PackedStringArray()
	for block in parts:
		if block.begins_with("[node "):
			var header_end: int = block.find("\n")
			var header: String = block.substr(0, header_end)
			var name := header.get_slice('name="', 1).get_slice('"', 0)
			var parent := ""
			if header.find('parent="') != -1:
				parent = header.get_slice('parent="', 1).get_slice('"', 0)
			var path := (parent + "/" + name) if parent != "." and parent != "" else name
			if texts.has(path):
				var escaped: String = str(texts[path]).replace("\\", "\\\\").replace('"', '\\"')
				var lines := block.split("\n")
				# Drop any existing text= line (multi-line values included)
				# before re-inserting the fresh one right after the header.
				var new_lines := PackedStringArray()
				var skipping := false
				for line in lines:
					if skipping:
						if line.ends_with('"'):
							skipping = false
						continue
					if line.begins_with("text = \""):
						if not line.ends_with('"') or line == "text = \"":
							skipping = true
						continue
					new_lines.append(line)
				new_lines.insert(1, 'text = "%s"' % escaped)
				block = "\n".join(new_lines)
		out.append(block)
	return "".join(out)

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
	for i in 5:
		AIManager.get_ai(i).defeated = true
