extends Node
## No text a player has to READ may be set below a floor that stays legible on
## a phone. The 960x544 canvas is scaled to fit the short edge of the screen,
## so on a ~6.3" phone in landscape one design pixel is roughly 0.12mm: 22
## lands near 2.7mm, about Android's own floor for body text, and this game's
## decorative font needs more room than a UI font at the same size.
##
## Read out of the source rather than by building every screen: the sizes are
## literals scattered across twenty files, and the point is to catch the next
## one being typed, not to render them.
## Run: godot --headless --quit-after 200 res://tests/test_readable_text.tscn

const SCRIPT_ROOT := "res://scripts"

## Sizes below the floor that are deliberate, with the reason. Anything not
## listed here has to clear the floor.
##
## These are all glanceable marks rather than sentences: a number or a symbol
## whose meaning the player already knows, in a fixed spot, that they check
## rather than read.
const ALLOWED := {
	"res://scripts/CardView.gd": "the stat quad printed on a card face - four characters, hard-limited by the card frame (see test_card_stat_fit), and the same numbers are shown large in the stats panel",
	"res://scripts/ui/ControllerUI.gd": "controller button hints, which sit next to their glyph and are read once",
}

func _gd_files(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path + "/" + entry
		if dir.current_is_dir():
			_gd_files(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()

func _ready() -> void:
	var floor_size: int = load("res://scripts/battle/BattleScene.gd") \
		.get_script_constant_map()["MIN_READABLE_FONT_SIZE"]
	assert(floor_size >= 20, "the readable floor has been lowered to %d" % floor_size)

	var files: Array = []
	_gd_files(SCRIPT_ROOT, files)
	assert(files.size() > 10, "found only %d scripts - the scan is not reaching the source" % files.size())

	var pattern := RegEx.new()
	pattern.compile('font_size_override\\("(?:normal_)?font_size", *([0-9]+)\\)')

	var offenders := []
	for path in files:
		if ALLOWED.has(path):
			continue
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var m := pattern.search(lines[i])
			if m == null:
				continue
			var size := int(m.get_string(1))
			if size < floor_size:
				offenders.append("%s:%d sets %dpx" % [path, i + 1, size])

	assert(offenders.is_empty(),
		"text below the %dpx phone-readable floor:\n  %s" % [floor_size, "\n  ".join(offenders)])

	print("OK - every read-me text in %d scripts is at least %dpx" % [files.size(), floor_size])
	get_tree().quit()
