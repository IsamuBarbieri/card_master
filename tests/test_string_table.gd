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

	# The last enum member must line up with the last column, which is what
	# proves the enum and the rows grew together.
	assert(StringTable.ID_DELETE_SLOT_ONLINE == expected - 1,
		"the enum has %d entries but each language row has %d" % [StringTable.ID_DELETE_SLOT_ONLINE + 1, expected])

	# Every language index the OS locale map can produce has to exist.
	for locale in StringTable.LANGUAGE_BY_LOCALE:
		var idx: int = StringTable.LANGUAGE_BY_LOCALE[locale]
		assert(idx >= 0 and idx < StringTable.TABLE.size(),
			"locale '%s' maps to language %d, which has no table row" % [locale, idx])

	print("OK - all %d languages carry %d strings" % [StringTable.TABLE.size(), expected])
	get_tree().quit()
