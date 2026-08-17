class_name UIPanel
extends RefCounted
## The framed box every info panel and dialog in the game sits on.
##
## Was common_transp_box_a.png: one 300x300 image stretched to whatever the
## caller needed - 248x256 in battle, 299x158 in Collection, 545x56 in
## Opponents. At 9.7:1 the painted border smears into a different thickness on
## every screen, and the corners with it. That is most of why it looked bad;
## nicer art drawn the same way would have looked bad the same way.
##
## Drawn by the engine instead of sampled from a texture. A StyleBoxFlat's
## corner radius and border width are in pixels, so they are identical in
## every panel however it is proportioned, and they stay sharp at any screen
## density - which a texture cannot do, and which is the whole complaint on a
## phone. The 9-patch alternative would keep the corners un-stretched but draw
## them at their own texel size, so they would either be too big for a small
## panel or too soft on a large screen (see SelectionOutline, which had to
## scale its whole node down to work around exactly that).
##
## Deliberately light: every screen puts black text on these.

## Warm parchment rather than the old flat white, to sit with the scroll and
## the card art. Slightly translucent so the background still reads through.
const FILL := Color(0.96, 0.93, 0.85, 0.94)
## Dark bronze, the same family as the gold rims on the buttons and the globe.
const FRAME := Color(0.42, 0.30, 0.14)
## A thin brighter line just inside the frame - the one touch that reads as
## "ornate" rather than "rounded rectangle", for one extra node.
const INNER_LINE := Color(0.80, 0.66, 0.36, 0.75)
const FRAME_WIDTH := 4
const RADIUS := 12
const INNER_INSET := 6.0
const INNER_RADIUS := 7

static func _style(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_width_left = width
	sb.border_width_right = width
	sb.border_width_top = width
	sb.border_width_bottom = width
	sb.border_color = border
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.anti_aliasing = true
	return sb

## A framed panel of `size`, ready to be positioned and added by the caller -
## same shape of call as the TextureRect it replaces. Never takes the mouse:
## these sit under card drags in Shop and DeckSelect.
static func make(size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var outer := _style(FILL, FRAME, FRAME_WIDTH, RADIUS)
	outer.shadow_color = Color(0, 0, 0, 0.35)
	outer.shadow_size = 5
	outer.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", outer)

	var inner := Panel.new()
	inner.position = Vector2(INNER_INSET, INNER_INSET)
	inner.size = size - Vector2(INNER_INSET, INNER_INSET) * 2.0
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_stylebox_override("panel", _style(Color.TRANSPARENT, INNER_LINE, 1, INNER_RADIUS))
	panel.add_child(inner)

	return panel
