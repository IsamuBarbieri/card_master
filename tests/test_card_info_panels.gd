extends Node
## The card-stats readouts (the panel that shows Attack/Type/P.Def/M.Def for
## whichever card is selected) were enlarged to use the space their panels
## actually have. Bigger text plus fit-to-width shrinking is only an
## improvement while the shrinking doesn't quietly undo it - a caption that
## has to drop to 11px in German is worse than where we started.
##
## So this checks every label in the battle and collection panels, in all nine
## languages, against its real box: it must fit, and it must not have to
## shrink below a size that is still comfortably readable on a phone.
## Run: godot --headless --quit-after 200 res://tests/test_card_info_panels.tscn

## Anything below this stops being an improvement over the sizes these panels
## used before the pass (24 in battle, 25 in collection).
const READABLE_FLOOR := 22

func _consts(path: String) -> Dictionary:
	var script: GDScript = load(path)
	assert(script != null, "could not load " + path)
	return script.get_script_constant_map()

## StringTable.get_string() reads Game.language, and setting that persists to
## user://settings.save - which a test has no business doing. The table is
## read directly instead.
func _string(lang: int, id: int) -> String:
	return StringTable.TABLE[lang][id]

func _check(font: Font, text: String, width: float, max_size: int, where: String) -> void:
	var fitted := UIButtonStyle.fit_text_to_width(text, font, width, max_size, 1)
	var actual_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x
	assert(actual_width <= width + 0.5,
		"%s: \"%s\" is %.1fpx at its smallest allowed size, box is %.1fpx" % [where, text, actual_width, width])
	assert(fitted >= READABLE_FLOOR,
		"%s: \"%s\" has to shrink to %dpx to fit %.0fpx - below the %dpx floor" % [where, text, fitted, width, READABLE_FLOOR])

func _ready() -> void:
	var font: Font = Game.font_stylish
	assert(font != null, "Game.font_stylish is not loaded")

	var battle := _consts("res://scripts/battle/BattleScene.gd")
	var collection := _consts("res://scripts/menu/Collection.gd")

	# Shop and Collection have room for the full captions; the two battle
	# panels use the abbreviated ones.
	var caption_ids := [
		StringTable.ID_CARD_ATTACK, StringTable.ID_CARD_TYPE,
		StringTable.ID_CARD_PHYSICAL_DEFENSE, StringTable.ID_CARD_MAGICAL_DEFENSE,
	]
	var short_caption_ids := [
		StringTable.ID_CARD_ATTACK_SHORT, StringTable.ID_CARD_TYPE_SHORT,
		StringTable.ID_CARD_PDEF_SHORT, StringTable.ID_CARD_MDEF_SHORT,
	]
	var type_ids := [
		StringTable.ID_ATTACK_TYPE_PHYSICAL, StringTable.ID_ATTACK_TYPE_MAGICAL,
		StringTable.ID_ATTACK_TYPE_FLEXIBLE, StringTable.ID_ATTACK_TYPE_ASSAULT,
	]

	# --- Collection: localized captions AND localized full-word attack types.
	for lang in StringTable.TABLE.size():
		for id in caption_ids:
			_check(font, _string(lang, id), collection["INFO_CAPTION_WIDTH"],
				collection["INFO_FONT_SIZE"], "collection caption (lang %d)" % lang)
		for id in type_ids:
			_check(font, _string(lang, id), collection["INFO_VALUE_WIDTH"],
				collection["INFO_FONT_SIZE"], "collection type value (lang %d)" % lang)

	# The rows have to stay inside the panel (236,375 299x158).
	var last_row_bottom: float = collection["INFO_ROWS_TOP"] + 3 * collection["INFO_ROW_STEP"] + collection["INFO_ROW_HEIGHT"]
	assert(last_row_bottom <= 375.0 + 158.0,
		"collection rows end at y=%.0f, past the panel's 533" % last_row_bottom)
	assert(collection["INFO_CAPTION_WIDTH"] + collection["INFO_VALUE_WIDTH"] <= 299.0 - 10.0,
		"collection caption+value are wider than the panel")

	# --- Battle: the same readout as the end-of-match one below, down to the
	# spelled-out attack type, so it faces the same strings in the same widths.
	var name_width: float = battle["INFO_RIGHT"] - battle["INFO_LEFT"]
	for def in CardManager.defs:
		_check(font, def.name, name_width, battle["INFO_FONT_SIZE"], "battle card name")
	for lang in StringTable.TABLE.size():
		_check(font, _string(lang, StringTable.ID_CARD_STATS), name_width,
			battle["INFO_FONT_SIZE"], "battle panel heading (lang %d)" % lang)
	for lang in StringTable.TABLE.size():
		for id in short_caption_ids:
			_check(font, _string(lang, id), battle["INFO_CAPTION_WIDTH"],
				battle["INFO_FONT_SIZE"], "battle caption (lang %d)" % lang)
		for id in type_ids:
			_check(font, _string(lang, id), battle["INFO_VALUE_WIDTH"],
				battle["INFO_FONT_SIZE"], "battle type value (lang %d)" % lang)
	_check(font, "255", battle["INFO_VALUE_WIDTH"], battle["INFO_FONT_SIZE"], "battle stat value")

	# The two panels must stay identical where it counts, or the same card
	# reads two different ways depending on which screen you are on.
	assert(battle["INFO_FONT_SIZE"] == battle["END_INFO_FONT_SIZE"], "the two battle readouts use different type sizes")
	assert(battle["INFO_CAPTION_WIDTH"] == battle["END_INFO_CAPTION_WIDTH"], "the two battle readouts give captions different room")
	assert(battle["INFO_VALUE_WIDTH"] == battle["END_INFO_VALUE_WIDTH"], "the two battle readouts give values different room")

	# --- End-of-match readout: same captions, but the attack type is spelled
	# out in full here, so the value column carries the long strings.
	for lang in StringTable.TABLE.size():
		for id in short_caption_ids:
			_check(font, _string(lang, id), battle["END_INFO_CAPTION_WIDTH"],
				battle["END_INFO_FONT_SIZE"], "end-panel caption (lang %d)" % lang)
		for id in type_ids:
			_check(font, _string(lang, id), battle["END_INFO_VALUE_WIDTH"],
				battle["END_INFO_FONT_SIZE"], "end-panel type value (lang %d)" % lang)
	for def in CardManager.defs:
		_check(font, def.name, battle["END_INFO_WIDTH"], battle["END_INFO_FONT_SIZE"], "end-panel card name")

	var end_bottom: float = battle["END_INFO_ROWS_TOP"] + 3 * battle["END_INFO_ROW_STEP"] + battle["END_INFO_ROW_HEIGHT"]
	assert(end_bottom <= 224.0, "end-panel rows end at y=%.0f, past the 224 box" % end_bottom)
	assert(battle["END_INFO_CAPTION_WIDTH"] + battle["END_INFO_VALUE_WIDTH"] <= battle["END_INFO_WIDTH"],
		"end-panel caption+value overlap")
	assert(battle["END_INFO_FONT_SIZE"] > 25, "the end-of-match readout is no larger than before")

	var battle_bottom: float = battle["INFO_TOP"] + 44.0 + 3 * battle["INFO_ROW_STEP"] + battle["INFO_ROW_HEIGHT"]
	assert(battle_bottom <= battle["INFO_BOTTOM"],
		"battle rows end at y=%.0f, past the marble's %.0f" % [battle_bottom, battle["INFO_BOTTOM"]])
	assert(battle["INFO_CAPTION_WIDTH"] + battle["INFO_VALUE_WIDTH"] <= battle["INFO_RIGHT"] - battle["INFO_LEFT"],
		"battle caption+value overlap")

	# Both panels must actually be bigger than what they replaced, or this
	# whole pass achieved nothing.
	assert(battle["INFO_FONT_SIZE"] > 24, "the battle readout is no larger than before")
	assert(collection["INFO_FONT_SIZE"] > 25, "the collection readout is no larger than before")

	print("OK - card info panels fit every language at %d/%d px" % [
		battle["INFO_FONT_SIZE"], collection["INFO_FONT_SIZE"]])
	get_tree().quit()
