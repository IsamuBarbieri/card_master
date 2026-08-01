class_name SelectionOutline
extends Control
## 1:1 port of DeckSelectScene's selectionLines (DrawableLines): a double
## rectangle outline drawn around whichever card is the current input
## target - the wheels' central card or a lower-deck slot.

const OUTLINE_COLOR := Color(0.93, 0.93, 0.93, 1.0)

var rect: Rect2 = Rect2()

func set_target_rect(r: Rect2) -> void:
	rect = r
	queue_redraw()

func _draw() -> void:
	var outer := PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
		rect.position,
	])
	var inner := PackedVector2Array([
		rect.position + Vector2(-1, -1),
		rect.position + Vector2(rect.size.x + 1, -1),
		rect.end + Vector2(1, 1),
		rect.position + Vector2(-1, rect.size.y + 1),
		rect.position + Vector2(-1, -1),
	])
	draw_polyline(outer, OUTLINE_COLOR, 1.0)
	draw_polyline(inner, OUTLINE_COLOR, 1.0)
