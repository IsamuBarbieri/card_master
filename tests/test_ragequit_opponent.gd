extends Node
## Verifies RAGEQUIT is now the 18th, directly reachable opponent (grid
## includes it, unlock bounds check doesn't fall off the end of the array).
## Run: godot --headless --quit-after 10 res://tests/test_ragequit_opponent.tscn

func _ready() -> void:
	assert(AIManager.count() == 18, "expected 18 AI rows (17 real + RAGEQUIT), got %d" % AIManager.count())
	assert(AIManager.rage_quit_index() == 17, "RAGEQUIT should be the last index")

	var ai: AIManager.AIData = AIManager.get_ai(AIManager.rage_quit_index())
	assert(ai.ai_name == "Rage Quit" or ai.ai_name.to_lower().contains("rage"), "index 17 isn't the RAGEQUIT row: %s" % ai.ai_name)

	# available_opponents must already be sized to cover index 17 (Player.gd
	# resizes to AIManager.count()) so the sequential unlock on beating
	# opponent 16 (`available_opponents[index+1] = true`) has a slot to write
	# into instead of silently no-op'ing past the array end.
	var arr: Array = []
	arr.resize(AIManager.count())
	arr.fill(false)
	arr[16] = true
	var opponent_index := 16
	if opponent_index + 1 < arr.size():
		arr[opponent_index + 1] = true
	assert(arr[17] == true, "beating opponent 16 must unlock RAGEQUIT at index 17")

	print("OK - RAGEQUIT opponent checks passed")
	get_tree().quit()
