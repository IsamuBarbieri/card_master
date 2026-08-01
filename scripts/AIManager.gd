extends Node
## Port of AIManager.cs - data only. GetFullAI's persistent per-AI deck
## (topCards/genericCards/capturedCards, saved/loaded via SaveSystem) isn't
## ported - no SaveSystem yet. What IS ported: each AI's First Set/Other Set
## card-definition-id ranges from ai_table.csv, so BattleScene can generate
## an appropriately-scaled hand per opponent (AIGenFirstSet's behavior,
## treating every battle as if it's the AI's first use) instead of pulling
## from the whole card table regardless of which opponent was picked.

const CSV_PATH := "res://assets/cards/ai_table.csv"

class AIData:
	var id: int
	var ai_name: String
	var image_id: int
	var level: int
	var gen_first_min: int
	var gen_first_max: int
	var gen_other_min: int
	var gen_other_max: int
	var defeated: bool = false

var _ai: Array = []  # Array of AIData

func _ready() -> void:
	_load()

func _load() -> void:
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open " + CSV_PATH)
		return
	var line_index := 0
	while not file.eof_reached():
		var line := file.get_line()
		line_index += 1
		if line_index == 1 or line.strip_edges() == "":
			continue
		var data := line.split(",")
		var ai := AIData.new()
		ai.id = int(data[0])
		ai.ai_name = data[1]
		ai.image_id = int(data[2])
		ai.level = int(data[3])
		var first_set: Array = CardManager.parse_range(data[4])
		ai.gen_first_min = first_set[0]
		ai.gen_first_max = first_set[1]
		var other_set: Array = CardManager.parse_range(data[5])
		ai.gen_other_min = other_set[0]
		ai.gen_other_max = other_set[1]
		_ai.append(ai)
	file.close()

## Port of AIManager.cs's AIGenFirstSet(): 5 cards with random definitionIds
## drawn from this AI's First Set range (ai_table.csv columns "First Set").
func generate_hand(ai: AIData) -> Array:
	var hand := []
	for i in 5:
		hand.append(CardManager.generate_card(randi_range(ai.gen_first_min, ai.gen_first_max)))
	return hand

func count() -> int:
	return _ai.size()

func rage_quit_index() -> int:
	return _ai.size() - 1

func get_ai(index: int) -> AIData:
	return _ai[index]
