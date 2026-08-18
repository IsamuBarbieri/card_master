extends Node
## Measures candidate body fonts against this game's real constraints, so a
## face can be judged before the whole layout is reflowed around it.
##
## Twice now a font has been swapped in, the layout tests have failed one
## panel at a time, everything has been rebalanced, and the answer has been
## "I don't like it". This does the measuring part up front, for every
## candidate at once: drop .ttf files in assets/fonts/candidates/ and run it.
##
## Reports, per font:
##   coverage  characters missing from any of the nine language tables
##   width     total width of every UI string, against the current font
##   card      largest stat quad that fits the card frame
##   panels    the tightest fitted size any stat panel is forced down to,
##             across all nine languages, counting BOTH dimensions - the
##             number that decides whether a layout has to change at all
##   height     line height at 30, which is what the fixed-height rows have to
##             hold; it is the half that was missing when the first two swaps
##             came out clipped top and bottom
## Run: godot --headless --quit-after 2000 --script res://tools/font_audit.gd
## (or open tools/font_audit.tscn)

const CANDIDATES_DIR := "res://assets/fonts/candidates"
const FLOOR := 22

func _panels() -> Array:
	# [name, box width, max size, string ids] - the boxes that actually bind.
	var battle: Dictionary = load("res://scripts/battle/BattleScene.gd").get_script_constant_map()
	var collection: Dictionary = load("res://scripts/menu/Collection.gd").get_script_constant_map()
	var shop: Dictionary = load("res://scripts/menu/Shop.gd").get_script_constant_map()
	var captions := [StringTable.ID_CARD_ATTACK_SHORT, StringTable.ID_CARD_TYPE_SHORT,
		StringTable.ID_CARD_PDEF_SHORT, StringTable.ID_CARD_MDEF_SHORT]
	var types := [StringTable.ID_ATTACK_TYPE_PHYSICAL, StringTable.ID_ATTACK_TYPE_MAGICAL,
		StringTable.ID_ATTACK_TYPE_FLEXIBLE, StringTable.ID_ATTACK_TYPE_ASSAULT]
	# [name, box, max size, string ids] - box carries the row height too, which
	# is what a width-only measurement kept missing.
	return [
		["battle caption", Vector2(battle["INFO_CAPTION_WIDTH"], battle["INFO_ROW_HEIGHT"]), battle["INFO_FONT_SIZE"], captions],
		["battle value", Vector2(battle["INFO_VALUE_WIDTH"], battle["INFO_ROW_HEIGHT"]), battle["INFO_FONT_SIZE"], types],
		["end caption", Vector2(battle["END_INFO_CAPTION_WIDTH"], battle["END_INFO_ROW_HEIGHT"]), battle["END_INFO_FONT_SIZE"], captions],
		["end value", Vector2(battle["END_INFO_VALUE_WIDTH"], battle["END_INFO_ROW_HEIGHT"]), battle["END_INFO_FONT_SIZE"], types],
		["shop caption", Vector2(shop["SHOP_INFO_CAPTION_WIDTH"], 41.0), shop["SHOP_INFO_FONT_SIZE"], captions],
		["shop value", Vector2(shop["SHOP_INFO_VALUE_WIDTH"], 41.0), shop["SHOP_INFO_FONT_SIZE"], types],
		["collection caption", Vector2(collection["INFO_CAPTION_WIDTH"], collection["INFO_ROW_HEIGHT"]), collection["INFO_FONT_SIZE"], captions],
		["collection value", Vector2(collection["INFO_VALUE_WIDTH"], collection["INFO_ROW_HEIGHT"]), collection["INFO_FONT_SIZE"], types],
	]

## Every character the nine language tables can put on screen.
func _needed_chars() -> Dictionary:
	var chars := {}
	for lang in StringTable.TABLE.size():
		for s in StringTable.TABLE[lang]:
			for i in str(s).length():
				chars[str(s).unicode_at(i)] = true
	return chars

## Total width of every string at a fixed size - a single number for "is this
## face wider or narrower than what we have", which is what decides whether
## the panels need touching at all.
func _total_width(font: Font) -> float:
	var total := 0.0
	for lang in StringTable.TABLE.size():
		for s in StringTable.TABLE[lang]:
			total += font.get_string_size(str(s), HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	return total

func _widest_stat(font: Font, size: int) -> float:
	var worst := ""
	var worst_w := -1.0
	for d in "0123456789ABCDEF":
		for l in "PMXA":
			var t := d + l + d + d
			var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			if w > worst_w:
				worst_w = w
				worst = t
	return worst_w

func _max_card_size(font: Font) -> int:
	var card: Dictionary = load("res://scripts/CardView.gd").get_script_constant_map()
	var usable: float = card["STAT_AREA_RIGHT"] - card["STAT_AREA_LEFT"] - 2 * card["STAT_OUTLINE"]
	var size := 8
	while size < 60 and _widest_stat(font, size + 1) <= usable:
		size += 1
	return size

func _report(label: String, font: Font, baseline: float) -> void:
	var missing := 0
	for code in _needed_chars():
		if not font.has_char(code):
			missing += 1

	var tightest := 99
	var tightest_where := ""
	for p in _panels():
		for id in p[3]:
			for lang in StringTable.TABLE.size():
				var fitted := UIButtonStyle.fit_text_to_box(
					StringTable.TABLE[lang][id], font, p[1], p[2], 1)
				if fitted < tightest:
					tightest = fitted
					tightest_where = "%s, \"%s\"" % [p[0], StringTable.TABLE[lang][id]]

	var width := _total_width(font)
	print("%-24s | miss %4d %-13s | width %+5.1f%% | line %2.0f | card %2d | panel %2d | %s" % [
		label, missing, ("(%d non-latin)" % missing) if missing > 0 else "",
		0.0 if baseline == 0.0 else (width / baseline - 1.0) * 100.0,
		font.get_height(30), _max_card_size(font), tightest,
		tightest_where if tightest < FLOOR else "clears the %dpx floor" % FLOOR])

func _ready() -> void:
	var current: Font = Game.font_stylish
	var baseline := _total_width(current)

	print("")
	print("width is against the font in use now; card is the largest stat quad")
	print("that fits the card frame; tightest panel is the smallest size any")
	print("stat readout is forced to in any of the nine languages (floor %d).\n" % FLOOR)

	_report("[in use] " + current.resource_path.get_file(), current, baseline)
	_report("[titles] " + Game.font_title.resource_path.get_file(), Game.font_title, baseline)

	var dir := DirAccess.open(CANDIDATES_DIR)
	if dir == null:
		print("\nno candidates: put .ttf/.otf files in %s and run again" % CANDIDATES_DIR)
		get_tree().quit()
		return

	print("")
	dir.list_dir_begin()
	var entry := dir.get_next()
	var names := []
	while entry != "":
		if entry.ends_with(".ttf") or entry.ends_with(".otf"):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()

	for name in names:
		var font: FontFile = load(CANDIDATES_DIR + "/" + name)
		if font == null:
			print("%-26s could not be loaded" % name)
			continue
		_report(name, font, baseline)

	get_tree().quit()
