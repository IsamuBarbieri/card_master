extends Node
## CardView.STAT_FONT_SIZE is the single knob deciding how legible a card's
## stats are everywhere in the game (battle, shop, collection all scale the
## same 96x128 CardView). It is set as large as the card frame allows, which
## only stays true as long as nobody changes the font or the border art - so
## this measures the real thing instead of trusting the number.
## Run: godot --headless --quit-after 200 res://tests/test_card_stat_fit.tscn

## Every character stat_text() can emit: the 16 hex classes plus the four
## attack-type letters (CardManager.stat_to_hex / attack_type_to_letter).
const HEX_DIGITS := "0123456789ABCDEF"
const TYPE_LETTERS := "PMXA"

func _widest_stat_text(font: Font, size: int) -> Dictionary:
	# stat_text() is digit + letter + digit + digit, so the worst case is the
	# widest digit three times next to the widest letter. Measured rather than
	# assumed: which glyph is widest depends on the font.
	var worst_digit := ""
	var worst_digit_w := -1.0
	for i in HEX_DIGITS.length():
		var w := font.get_string_size(HEX_DIGITS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if w > worst_digit_w:
			worst_digit_w = w
			worst_digit = HEX_DIGITS[i]

	var worst_letter := ""
	var worst_letter_w := -1.0
	for i in TYPE_LETTERS.length():
		var w := font.get_string_size(TYPE_LETTERS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if w > worst_letter_w:
			worst_letter_w = w
			worst_letter = TYPE_LETTERS[i]

	var text := worst_digit + worst_letter + worst_digit + worst_digit
	return {"text": text, "width": font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x}

func _ready() -> void:
	# The quad is drawn in the emphasis cut, not the body one - measuring the
	# wrong weight would report a size that then overflows on screen.
	var font: Font = Game.font_emphasis
	assert(font != null, "Game.font_emphasis is not loaded")

	var available: float = CardView.STAT_AREA_RIGHT - CardView.STAT_AREA_LEFT
	# The outline stroke grows the glyphs outward on both sides, so it eats
	# into the same clear area the text does.
	var usable: float = available - 2.0 * CardView.STAT_OUTLINE

	var current := _widest_stat_text(font, CardView.STAT_FONT_SIZE)
	print("widest stat text \"%s\" at size %d: %.1fpx (usable %.1fpx of %.1f)" % [
		current["text"], CardView.STAT_FONT_SIZE, current["width"], usable, available])
	assert(current["width"] <= usable,
		"stat text overflows the card frame: %.1fpx > %.1fpx - lower CardView.STAT_FONT_SIZE" % [current["width"], usable])

	# The label is placed by STAT_FONT_SIZE_HEIGHT, so that has to cover the
	# rendered line or the text creeps below STAT_AREA_BOTTOM and under the
	# frame's bottom trim. The outline stroke is not counted: it is drawn
	# outside the glyph box and nothing clips it.
	var line_height := font.get_height(CardView.STAT_FONT_SIZE)
	assert(CardView.STAT_FONT_SIZE_HEIGHT >= line_height,
		"STAT_FONT_SIZE_HEIGHT (%d) is shorter than the rendered line (%.1fpx)" % [CardView.STAT_FONT_SIZE_HEIGHT, line_height])

	# ...and the text must not climb so far up the card that it covers the art.
	var top: float = CardView.STAT_AREA_BOTTOM - CardView.STAT_FONT_SIZE_HEIGHT
	assert(top >= CardView.CARD_H * 0.6,
		"the stat band has grown into the card art (top at y=%.0f of %d)" % [top, CardView.CARD_H])

	# Report the headroom, so the next person tuning this can see at a glance
	# whether the current size is actually the largest that fits.
	var largest := CardView.STAT_FONT_SIZE
	while _widest_stat_text(font, largest + 1)["width"] <= usable:
		largest += 1
	print("largest size that still fits: ", largest)
	assert(largest - CardView.STAT_FONT_SIZE <= 2,
		"STAT_FONT_SIZE is %d but %d would still fit - the stats are smaller than they need to be" % [CardView.STAT_FONT_SIZE, largest])

	print("OK - card stat text is as large as the frame allows")
	get_tree().quit()
