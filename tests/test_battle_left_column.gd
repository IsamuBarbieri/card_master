extends Node
## The battle screen's left column stacks three things down 280px: the
## pergamena scoreboard, the opponent's remaining cards, and the card-stats
## panel. They have collided twice already - once when the stats panel grew
## taller, once when the pergamena art was reproportioned - and neither time
## did anything complain. Everything is derived from the art now, and this
## checks the derivation actually clears.
## Run: godot --headless --quit-after 200 res://tests/test_battle_left_column.tscn

var Battle: GDScript

func _c(name: String):
	return Battle.get_script_constant_map()[name]

func _ready() -> void:
	Battle = load("res://scripts/battle/BattleScene.gd")

	var tex: Texture2D = load("res://assets/battle/battle_pergamena.png")
	var size: Vector2 = Battle.pergamena_size()
	var inner: Rect2 = Battle.pergamena_inner()
	var pos: Vector2 = _c("PERGAMENA_POS")
	var info_top: float = _c("INFO_PANEL_TOP")

	# 1. the art is drawn at its own aspect, not squashed into a fixed box
	var art_aspect := float(tex.get_width()) / tex.get_height()
	assert(absf(size.x / size.y - art_aspect) < 0.001,
		"the pergamena is drawn at aspect %.3f but the art is %.3f - it will look stretched" % [size.x / size.y, art_aspect])

	var bottom := pos.y + size.y
	assert(bottom < info_top, "the pergamena (ends y=%.0f) runs into the stats panel (starts y=%.0f)" % [bottom, info_top])

	# 2. the writable field is inside the art
	assert(inner.position.x >= pos.x and inner.position.y >= pos.y, "the scoreboard field starts outside the pergamena")
	assert(inner.end.x <= pos.x + size.x + 0.01 and inner.end.y <= bottom + 0.01,
		"the scoreboard field (ends %s) sticks out of the pergamena (ends %s)" % [inner.end, pos + size])

	# 3. all four scoreboard lines land inside that field
	var row_h: float = Battle.scoreboard_row_height()
	assert(row_h > 20.0, "a scoreboard line is only %.0fpx tall - the text will not fit" % row_h)
	for row in 4:
		var y: float = Battle.scoreboard_row_y(row)
		assert(y >= inner.position.y - 0.01, "scoreboard line %d starts above the field" % row)
		assert(y + row_h <= inner.end.y + 0.01,
			"scoreboard line %d ends at y=%.0f, past the field's %.0f" % [row, y + row_h, inner.end.y])

	# 4. the turn marker is centred on its player's two lines and stays out of
	#    the other player's block
	for player in 2:
		var cy: float = Battle.cursor_row_y(player)
		var block_top: float = Battle.scoreboard_row_y(player * 2)
		var block_h := 2.0 * row_h
		assert(cy >= block_top - 0.01 and cy + Battle.cursor_size() <= block_top + block_h + 0.01,
			"the turn marker for player %d spills out of that player's two lines" % player)
		assert(absf((cy + Battle.cursor_size() / 2.0) - (block_top + block_h / 2.0)) < 0.01,
			"the turn marker for player %d is not centred on its block" % player)
	assert(Battle.scoreboard_text_width() > 100.0,
		"only %.0fpx left for a name after the turn marker" % Battle.scoreboard_text_width())
	assert(Battle.scoreboard_text_x() + Battle.scoreboard_text_width() <= inner.end.x + 0.01,
		"the scoreboard text runs past the field's right edge")

	# 4b. the score is the bare number at the name's size, lined up under it.
	assert(absf(Battle.scoreboard_score_width() - Battle.scoreboard_text_width()) < 0.01,
		"the score doesn't share the name's column")
	assert(_c("SCORE_FONT_SIZE") == _c("NAME_FONT_SIZE"), "the score reads smaller than the name above it")
	var widest_score := Game.font_stylish.get_string_size("10", HORIZONTAL_ALIGNMENT_LEFT, -1, _c("SCORE_FONT_SIZE")).x
	assert(widest_score <= Battle.scoreboard_score_width(), "a two-digit score does not fit the field")

	# 5. the opponent's cards fit the gap between the pergamena and the panel,
	#    which is the whole reason the art was made shorter
	var stack: Vector2 = Battle.opponent_stack_pos()
	var card: Vector2 = Vector2(_c("CARD_W"), _c("CARD_H")) * float(_c("OPPONENT_CARD_SCALE"))
	var top: float = stack.y - card.y / 2.0
	var bot: float = stack.y + card.y / 2.0
	assert(top >= bottom, "the opponent's cards (top y=%.0f) overlap the pergamena (ends y=%.0f)" % [top, bottom])
	assert(bot <= info_top, "the opponent's cards (bottom y=%.0f) overlap the stats panel (starts y=%.0f)" % [bot, info_top])

	# ...and the full five of them stay inside the column
	var last: float = stack.x + 4 * float(_c("OPPONENT_STACK_STEP")) + card.x / 2.0
	assert(stack.x - card.x / 2.0 >= 0.0, "the opponent's card stack starts off-screen")
	assert(last <= _c("PERGAMENA_WIDTH"), "the fifth opponent card reaches x=%.0f, past the column's %.0f" % [last, _c("PERGAMENA_WIDTH")])

	print("OK - pergamena %.0fx%.0f, cards centred at y=%.0f in the %.0fpx gap, stats below" % [
		size.x, size.y, stack.y, info_top - bottom])
	get_tree().quit()
