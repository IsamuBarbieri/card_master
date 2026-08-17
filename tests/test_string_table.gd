extends Node
## StringTable is 9 parallel arrays indexed by one shared enum, so adding a
## string means editing 9 places and any miss silently shifts every later ID
## in that language. This catches the shift.
## Run: godot --headless --quit-after 20 res://tests/test_string_table.tscn

func _ready() -> void:
	var expected: int = StringTable.TABLE[0].size()
	assert(expected > 0, "the string table is empty")

	for lang in StringTable.TABLE.size():
		var row: Array = StringTable.TABLE[lang]
		assert(row.size() == expected,
			"language %d has %d strings, expected %d - a translation was missed or doubled" % [lang, row.size(), expected])
		for i in row.size():
			assert(row[i] is String and row[i] != "",
				"language %d, string %d is empty" % [lang, i])

	# The enum and the rows must have grown together. Counted rather than
	# checked against whichever ID happens to be last: naming one meant this
	# assertion had to be edited every single time a string was added, which
	# is precisely the moment a test should be doing the noticing for you.
	# Members of an unnamed enum land in the script's constant map.
	var ids := 0
	for key in StringTable.get_script().get_script_constant_map():
		if str(key).begins_with("ID_"):
			ids += 1
	assert(ids == expected,
		"the enum has %d ID_ entries but each language row has %d strings" % [ids, expected])

	# Every language index the OS locale map can produce has to exist.
	for locale in StringTable.LANGUAGE_BY_LOCALE:
		var idx: int = StringTable.LANGUAGE_BY_LOCALE[locale]
		assert(idx >= 0 and idx < StringTable.TABLE.size(),
			"locale '%s' maps to language %d, which has no table row" % [locale, idx])

	print("OK - all %d languages carry %d strings" % [StringTable.TABLE.size(), expected])
	get_tree().quit()
