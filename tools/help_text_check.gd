extends Node
## Headless check (no window needed - pure font metrics): does each Help
## label's text fit its box, in every language, once shrunk to the same
## floor fit_paragraph_to_box uses? Catches what a single-language
## screenshot can't.
## Run: godot --headless --quit-after 30 res://tools/help_text_check.tscn

const START_SIZE := 24
const FLOOR_SIZE := 18

func _ready() -> void:
	var font: Font = Game.font_stylish
	var ok := true
	var items := [
		["cards page", StringTable.ID_HELP_CARDS, Vector2(600, 386)],
		["main1 battle", StringTable.ID_HELP_MAIN1, Vector2(300, 95)],
		["main2 shop", StringTable.ID_HELP_MAIN2, Vector2(300, 95)],
		["main3 collection", StringTable.ID_HELP_MAIN3, Vector2(300, 95)],
		["main_online", StringTable.ID_HELP_MAIN_ONLINE, Vector2(340, 90)],
		["main4 options", StringTable.ID_HELP_MAIN4, Vector2(340, 90)],
	]
	for item in items:
		var label: String = item[0]
		var id: int = item[1]
		var box: Vector2 = item[2]
		for lang in StringTable.TABLE.size():
			var text: String = StringTable.TABLE[lang][id]
			var size := START_SIZE
			while size > FLOOR_SIZE:
				var h := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, box.x, size).y
				if h <= box.y:
					break
				size -= 1
			var h := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, box.x, size).y
			var fits := h <= box.y
			if not fits:
				ok = false
				print("%s lang %d: size=%d height=%.0f/%d CLIPPED" % [label, lang, size, h, box.y])
	print("RESULT: %s" % ("ALL FIT" if ok else "SOME CLIP"))
	get_tree().quit()
