extends Node
## Dev-only tool: boots one real screen with a populated player, waits for
## layout to settle, and dumps a raw PNG screenshot. Not shipped, not a test -
## used to regenerate assets/help/*.png backgrounds so the help diagrams
## show the current UI instead of a stale one.
## Run (needs a real window, not --headless, or the capture is blank):
##   godot --path "d:\Dropbox\Card Master Godot" --resolution 960x544 --position 100,100 res://tools/help_capture.tscn -- --page=shop --out=C:/some/dir

const SCENES := {
	"mainmenu": "res://scenes/menu/MainMenu.tscn",
	"shop": "res://scenes/menu/Shop.tscn",
	"deckselect": "res://scenes/deckselect/DeckSelect.tscn",
	"battle": "res://scenes/battle/BattleScene.tscn",
}

func _ready() -> void:
	var page := "mainmenu"
	var out_dir := "."
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--page="):
			page = a.substr("--page=".length())
		elif a.begins_with("--out="):
			out_dir = a.substr("--out=".length())

	_setup_player()
	if page == "deckselect":
		# DeckSelect rebuilds is_on_deck from last_deck itself (see its
		# _ready) - populating the cards' own flag isn't enough, the lower
		# deck row would stay empty and Play would never show.
		for i in 5:
			Game.player.last_deck[i] = Game.player.cards[i].unique_id

	var scene: Node = load(SCENES[page]).instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame

	# Let layout/fonts/theme settle (font fitting runs across a couple frames
	# for some panels) before the pixels are read back. Battle also plays a
	# ~2s coin-toss animation on entry - wait it out so the coin isn't
	# mid-spin (or still visible at all) in the screenshot.
	var settle_frames := 200 if page == "battle" else 10
	for i in settle_frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path := out_dir + "/" + page + ".png"
	img.save_png(path)
	print("saved " + path)
	get_tree().quit()

## A believable mid-game player: the 5 starter cards plus a handful more, some
## off-deck so the Shop/DeckSelect wheels aren't a wall of identical Slimes.
func _setup_player() -> void:
	Game.language = 1  # English - matches the neutral language the old help art used.
	Game.opponent_index = 0
	Game.player = Player.new("Player", 0, AIManager.count())
	Game.player.coins = 250
	for i in 6:
		var def_id: int = (i * 3) % CardManager.defs.size()
		var card := CardManager.generate_card(def_id)
		card.is_on_deck = false
		Game.player.cards.append(card)
