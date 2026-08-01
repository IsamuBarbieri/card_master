class_name BusySpinner
extends Control
## Stand-in for PSM's built-in BusyIndicator widget (a native engine spinner
## with no texture asset behind it, so there's nothing to port from
## reference assets) - a small procedurally-drawn rotating arc.

func _process(delta: float) -> void:
	if not visible:
		return
	rotation += delta * 6.0
	queue_redraw()

func _draw() -> void:
	var center: Vector2 = size / 2.0
	var radius: float = size.x / 2.0 - 4.0
	draw_arc(center, radius, 0.0, PI * 1.5, 24, Color.WHITE, 4.0, true)
