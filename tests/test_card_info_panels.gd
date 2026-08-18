extends Node
## The card readout (name, then Attack / Type / P.Def / M.Def) is one shared
## control now - CardStatPanel - laid out from nothing but the box each screen
## gives it. This checks that every one of those boxes still works, in all
## nine languages.
##
## What went wrong when there were five hand-laid copies, and what this exists
## to catch coming back:
##   - rows drawn at different sizes, because each label was fitted to its own
##     text ("255" large, "Magical" small, in the same panel)
##   - text running past the column, because fitting bottomed out at a floor
##     size and drew anyway
##   - a column too narrow for what goes in it (DeckSelect had 108px for the
##     spelled-out attack type and cut "Physical" to "Physic")
## Run: godot --headless --quit-after 200 res://tests/test_card_info_panels.tscn

## Every screen's readout box. These are the numbers passed to
## CardStatPanel.make() - if one moves, move it here too.
const BOXES := {
	"Shop": Vector2(242, 232),
	"DeckSelect": Vector2(242, 232),
	"Collection": Vector2(279, 146),
	"Battle": Vector2(228, 236),
	"Battle end": Vector2(216, 208),
}

## Below this the readout stops being readable on a phone. Was 22 when the
## panels were hand-laid and is still 22.
const READABLE_FLOOR := 22

func _ready() -> void:
	var font: Font = Game.font_stylish
	assert(font != null, "Game.font_stylish is not loaded")

	for screen in BOXES:
		var box: Vector2 = BOXES[screen]
		var cap_box := CardStatPanel.caption_box(box)
		var val_box := CardStatPanel.value_box(box)

		for lang in StringTable.TABLE.size():
			var size := CardStatPanel.row_size_for(box, lang)

			# The whole point of one shared size: it has to be a size every
			# string in the panel actually fits at, or a row overflows.
			for id in CardStatPanel.CAPTION_IDS:
				_fits(font, StringTable.TABLE[lang][id], size, cap_box,
					"%s caption (lang %d)" % [screen, lang])
			for id in CardStatPanel.ATTACK_TYPE_IDS:
				_fits(font, StringTable.TABLE[lang][id], size, val_box,
					"%s attack type (lang %d)" % [screen, lang])
			for text in ["255", "- - -"]:
				_fits(font, text, size, val_box, "%s value (lang %d)" % [screen, lang])

			assert(size >= READABLE_FLOOR,
				"%s drops to %dpx in language %d - below the %dpx floor" % [screen, size, lang, READABLE_FLOOR])

		# Card names are fitted separately (they don't grow with the
		# language), but they still have to fit the heading.
		var heading := Vector2(box.x, CardStatPanel.heading_height(box))
		for def in CardManager.defs:
			var name_size := UIButtonStyle.fit_text_to_box(def.name, font, heading,
				CardStatPanel.MAX_FONT_SIZE, CardStatPanel.MIN_FONT_SIZE)
			_fits(font, def.name, name_size, heading, "%s card name" % screen)
			assert(name_size >= READABLE_FLOOR,
				"%s: \"%s\" drops to %dpx - below the %dpx floor" % [screen, def.name, name_size, READABLE_FLOOR])

		# The rows have to stay inside the box they were given.
		var bottom := CardStatPanel.heading_height(box) + box.y * CardStatPanel.HEADING_GAP_SHARE \
			+ CardStatPanel.ROW_COUNT * CardStatPanel.row_height(box)
		assert(bottom <= box.y + 0.5, "%s rows end at %.1f, past the %.0f box" % [screen, bottom, box.y])

	print("OK - the shared card readout fits every screen in every language")
	get_tree().quit()

func _fits(font: Font, text: String, size: int, box: Vector2, where: String) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	assert(w <= box.x + 0.5, "%s: \"%s\" is %.1fpx at %dpx, column is %.1fpx" % [where, text, w, size, box.x])
	var h := font.get_height(size)
	assert(h <= box.y + 0.5, "%s: \"%s\" is %.1fpx tall at %dpx, row is %.1fpx" % [where, text, h, size, box.y])
