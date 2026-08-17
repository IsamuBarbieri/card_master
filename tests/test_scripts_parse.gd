extends Node
## Every script in the project must actually parse.
##
## This exists because Online.gd shipped broken: `var won := some_dict["ok"]
## and ...` can't be type-inferred, so the whole script failed to load and the
## Online menu was simply dead. Nothing caught it - the suite exercises logic
## through direct calls, and no test had ever loaded a menu scene, so a screen
## could stop existing entirely and every test would still pass.
##
## load() returns null on a parse error, which is the entire check. Cheap
## enough to run over the whole tree, and it covers the screens no other test
## touches - which are exactly the ones where a mistake goes unnoticed.
## Run: godot --headless --quit-after 400 res://tests/test_scripts_parse.tscn

const ROOTS := ["res://scripts", "res://scenes"]

func _files(dir_path: String, suffix: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path + "/" + entry
		if dir.current_is_dir():
			_files(full, suffix, out)
		elif entry.ends_with(suffix):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()

func _ready() -> void:
	var scripts: Array = []
	_files("res://scripts", ".gd", scripts)
	assert(scripts.size() > 30, "found only %d scripts - the scan is not reaching the source" % scripts.size())

	var broken := []
	for path in scripts:
		if load(path) == null:
			broken.append(path)
	assert(broken.is_empty(), "these scripts do not parse:\n  " + "\n  ".join(broken))

	# The scenes too: a screen whose .tscn points at a missing script or a
	# renamed class is just as dead as one that doesn't compile.
	var scenes: Array = []
	_files("res://scenes", ".tscn", scenes)
	assert(scenes.size() > 5, "found only %d scenes" % scenes.size())

	var unloadable := []
	for path in scenes:
		if load(path) == null:
			unloadable.append(path)
	assert(unloadable.is_empty(), "these scenes do not load:\n  " + "\n  ".join(unloadable))

	print("OK - %d scripts parse, %d scenes load" % [scripts.size(), scenes.size()])
	get_tree().quit()
