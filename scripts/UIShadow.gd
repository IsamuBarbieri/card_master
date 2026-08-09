class_name UIShadow
extends RefCounted
## Small flat drop shadow for image nodes (TextureRect/CardView) that have
## no built-in shadow support, unlike Label/RichTextLabel's theme-level
## font_shadow_color. Add the shadow BEFORE adding the image itself so it
## draws underneath.

static func behind(parent: Node, position: Vector2, size: Vector2, offset: Vector2 = Vector2(2, 3), alpha: float = 0.35) -> ColorRect:
	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, alpha)
	shadow.position = position + offset
	shadow.size = size
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(shadow)
	return shadow
