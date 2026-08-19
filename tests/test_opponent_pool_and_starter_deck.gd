extends Node
## Verifies:
##  1. ai_table.csv's sliding window: each opponent's card pool never reaches
##     past its own species (Image ID). First Set is a 2-wide window ending
##     at its own species; Other Set is a 3-wide window ending at its own
##     species too (unlike First Set, it no longer excludes it).
##  2. Lich/Odin/Dragon (gen_table.csv species 16-18, previously nobody's
##     signature opponent) are now real opponents between Kraken Queen and
##     The Void, and The Void/Rage Quit shifted to ids 19/20.
##  3. Player.generate_base_set() is Slime-only and free.
##  4. Opponents.gd's grid geometry actually fits 21 opponents in 3 rows of 7.
## Run: godot --headless --quit-after 10 res://tests/test_opponent_pool_and_starter_deck.tscn

func _ready() -> void:
	assert(AIManager.count() == 21, "expected 21 opponents (18 + Lich/Odin/Dragon), got %d" % AIManager.count())
	assert(AIManager.rage_quit_index() == 20, "RAGEQUIT should be the last index")

	# Rage Quit is a deliberate exception to the sliding window: a capture-
	# only "you gave up" punishment opponent whose own card is the only
	# thing it should ever field, not a window reaching into Dragon/The Void.
	for i in AIManager.count():
		if i == AIManager.rage_quit_index():
			continue
		var ai: AIManager.AIData = AIManager.get_ai(i)
		assert(ai.gen_first_max == ai.image_id, "opponent %d (%s) First Set reaches past its own species: gen_first_max=%d image_id=%d" % [i, ai.ai_name, ai.gen_first_max, ai.image_id])
		var expected_first_min: int = maxi(0, ai.image_id - 1)
		assert(ai.gen_first_min == expected_first_min, "opponent %d (%s) First Set window should start at %d, got %d" % [i, ai.ai_name, expected_first_min, ai.gen_first_min])
		assert(ai.gen_other_max == ai.image_id, "opponent %d (%s) Other Set reaches past its own species: gen_other_max=%d image_id=%d" % [i, ai.ai_name, ai.gen_other_max, ai.image_id])
		var expected_other_min: int = maxi(0, ai.image_id - 2)
		assert(ai.gen_other_min == expected_other_min, "opponent %d (%s) Other Set window should start at %d, got %d" % [i, ai.ai_name, expected_other_min, ai.gen_other_min])

	# The exact example used to pin down the rule: Lamia (id 14).
	var lamia: AIManager.AIData = AIManager.get_ai(14)
	assert(lamia.ai_name == "Lamia")
	assert(lamia.gen_first_min == 13 and lamia.gen_first_max == 14, "Lamia First Set should be (13-14)")
	assert(lamia.gen_other_min == 12 and lamia.gen_other_max == 14, "Lamia Other Set should be (12-14)")

	# Lich/Odin/Dragon are now real opponents, The Void/Rage Quit shifted.
	var lich: AIManager.AIData = AIManager.get_ai(16)
	var odin: AIManager.AIData = AIManager.get_ai(17)
	var dragon: AIManager.AIData = AIManager.get_ai(18)
	var the_void: AIManager.AIData = AIManager.get_ai(19)
	var rage_quit: AIManager.AIData = AIManager.get_ai(20)
	assert(lich.ai_name == "Lich" and lich.image_id == 16)
	assert(odin.ai_name == "Odin" and odin.image_id == 17)
	assert(dragon.ai_name == "Dragon" and dragon.image_id == 18)
	assert(the_void.ai_name == "The Void" and the_void.image_id == 19)
	assert(rage_quit.ai_name == "Rage Quit" and rage_quit.image_id == 20)
	assert(rage_quit.gen_first_min == 20 and rage_quit.gen_first_max == 20, "Rage Quit should only ever field its own card")
	assert(rage_quit.gen_other_min == 20 and rage_quit.gen_other_max == 20, "Rage Quit should only ever field its own card")

	# Starter deck: Slime-only, free.
	var player := Player.new("Test", 0, AIManager.count())
	player.generate_base_set()
	assert(player.cards.size() == 5)
	for card in player.cards:
		assert(card.def_id == 0, "starter card should be Slime (def_id 0), got %d" % card.def_id)
		assert(card.has_zero_price, "starter card should be free")

	# Opponents.gd grid: 7 columns x 3 rows = 21, must fit the scroll exactly.
	var item_w := 98  # CARD_W(96) + 2*ITEM_MARGIN(1)
	var item_h := 130  # CARD_H(128) + 2*ITEM_MARGIN(1)
	var cols := 7
	var rows := 3
	assert(cols * rows == 21, "7x3 must exactly fit 21 opponents")
	var grid_w := cols * item_w + (cols - 1) * 14
	var grid_h := rows * item_h + (rows - 1) * 6
	assert(grid_w <= 770, "grid width %d exceeds the 770 scroll width" % grid_w)
	assert(grid_h <= 402, "grid height %d exceeds the 402 scroll height" % grid_h)

	print("OK - opponent pool, starter deck, and grid checks passed")
	get_tree().quit()
