extends Node
## No text may be taller than the box it is drawn in.
##
## Every fixed-height label in this game was sized by measuring WIDTH and
## nothing else, but a line needs about 1.4x its font size vertically - ascent
## plus descent - so a 36px caption in a 42px row overflows by eight pixels
## and is clipped top and bottom. It was true of every typeface tried,
## including the one the game shipped with; changing font only changed how
## badly. This is the check that was missing.
##
## The panels fit themselves now (UIButtonStyle.fit_text_to_box), so this
## guards the constants they fit against: if a box is too short for even the
## smallest readable size, no amount of shrinking will save it.
## Run: godot --headless --quit-after 400 res://tests/test_text_fits_its_box.tscn

## The size fitting is allowed to shrink to before the box is simply too
## short - matching the readable floor the rest of the UI is held to.
const FLOOR := 22

func _consts(path: String) -> Dictionary:
	return load(path).get_script_constant_map()

func _ready() -> void:
	var font: Font = Game.font_stylish
	var battle := _consts("res://scripts/battle/BattleScene.gd")

	# The card-stat rows (battle, end-of-match, collection, shop, deck select)
	# are all CardStatPanel now, and test_card_info_panels already checks
	# those boxes in every language against every string that can land in
	# them - no need to duplicate that here.
	# [what, box height, size it would like]
	var boxes := [
		["scoreboard line", load("res://scripts/battle/BattleScene.gd").new().scoreboard_row_height(),
			battle["NAME_FONT_SIZE"]],
		["online clock", battle["ONLINE_TIMER_HEIGHT"], 34],
	]

	for b in boxes:
		var box_h: float = b[1]
		var wanted: int = b[2]
		# What the box can actually hold, whatever it was asked for.
		var fits := UIButtonStyle.fit_text_to_box("Ag", font, Vector2(9999, box_h), wanted, 1)
		assert(fits >= FLOOR,
			"%s is %.0fpx tall, which only holds %dpx of this font - below the %dpx floor, so the box itself has to grow" % [
				b[0], box_h, fits, FLOOR])
		assert(font.get_height(fits) <= box_h + 0.5,
			"%s: %dpx renders %.0fpx tall in a %.0fpx box" % [b[0], fits, font.get_height(fits), box_h])

	# The card band is the one place the size is fixed rather than fitted, so
	# it has to be right on its own - and it is drawn in the emphasis cut.
	var card := _consts("res://scripts/CardView.gd")
	font = Game.font_emphasis
	assert(font.get_height(card["STAT_FONT_SIZE"]) <= float(card["STAT_FONT_SIZE_HEIGHT"]) + 0.5,
		"the card's stat band is %dpx for a %.0fpx line" % [card["STAT_FONT_SIZE_HEIGHT"], font.get_height(card["STAT_FONT_SIZE"])])

	print("OK - every fixed-height text box can hold a readable line")
	get_tree().quit()
