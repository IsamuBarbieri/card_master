extends Node
## Dev-only: boots the real Help screen, jumps to each page, and screenshots
## it - so the redrawn callout boxes can be checked against the live
## translated instruction text (which Help.gd overlays at runtime and never
## appears in the raw background PNG).

func _ready() -> void:
	var out_dir := "."
	var lang := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr("--out=".length())
		elif a.begins_with("--lang="):
			lang = int(a.substr("--lang=".length()))

	Game.language = lang
	var help: Node = load("res://scenes/menu/Help.tscn").instantiate()
	get_tree().root.add_child.call_deferred(help)
	await get_tree().process_frame
	await get_tree().process_frame

	DirAccess.make_dir_recursive_absolute(out_dir)
	var names := ["presentation", "cards", "main", "deckselect", "battle", "shop"]
	for i in 6:
		help._go_to_page(i)
		for f in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir + "/page_%d_%s_lang%d.png" % [i, names[i], lang])
	print("done")
	get_tree().quit()
