extends Node
## Port of AIManager.cs - data only. GetFullAI's deck-generation side
## (topCards/genericCards/capturedCards) isn't ported: BattleScene currently
## generates the CPU hand directly via CardManager.generate_playable_deck,
## bypassing per-AI decks entirely. Kept here: id/name/portrait image and the
## runtime `defeated` flag, enough to drive UIOpponents 1:1.

const CSV_PATH := "res://assets/cards/ai_table.csv"

class AIData:
	var id: int
	var ai_name: String
	var image_id: int
	var level: int
	var defeated: bool = false

var _ai: Array = []  # Array of AIData

func _ready() -> void:
	_load()

func _load() -> void:
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
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
		_ai.append(ai)
	file.close()

func count() -> int:
	return _ai.size()

func rage_quit_index() -> int:
	return _ai.size() - 1

func get_ai(index: int) -> AIData:
	return _ai[index]
