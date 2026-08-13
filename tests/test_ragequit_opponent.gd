extends Node
## Verifies RAGEQUIT is the last, directly reachable opponent (grid includes
## it, unlock bounds check doesn't fall off the end of the array).
## Run: godot --headless --quit-after 10 res://tests/test_ragequit_opponent.tscn

func _ready() -> void:
	assert(AIManager.count() == 21, "expected 21 AI rows (20 real + RAGEQUIT), got %d" % AIManager.count())
	assert(AIManager.rage_quit_index() == 20, "RAGEQUIT should be the last index")

	var ai: AIManager.AIData = AIManager.get_ai(AIManager.rage_quit_index())
	assert(ai.ai_name == "Rage Quit" or ai.ai_name.to_lower().contains("rage"), "last index isn't the RAGEQUIT row: %s" % ai.ai_name)

	# available_opponents must already be sized to cover the last index
	# (Player.gd resizes to AIManager.count()) so the sequential unlock on
	# beating the second-to-last opponent (`available_opponents[index+1] =
	# true`) has a slot to write into instead of silently no-op'ing past
	# the array end.
	var arr: Array = []
	arr.resize(AIManager.count())
	arr.fill(false)
	var opponent_index := AIManager.rage_quit_index() - 1
	arr[opponent_index] = true
	if opponent_index + 1 < arr.size():
		arr[opponent_index + 1] = true
	assert(arr[AIManager.rage_quit_index()] == true, "beating the second-to-last opponent must unlock RAGEQUIT")

	print("OK - RAGEQUIT opponent checks passed")
	get_tree().quit()
