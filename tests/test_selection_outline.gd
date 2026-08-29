extends SceneTree
## Geometry checks for SelectionOutline's 9-patch glow, plus a load check on
## the generated glow texture.
##
## Everything here is measured as ON-SCREEN size, never as the node's raw
## `size`. NinePatchRect always draws its corners at native texel size, so
## after the art was upscaled 4x SelectionOutline started building the patch
## four times too big and scaling it back down (NODE_SCALE) to keep the same
## footprint. Reading `size` alone therefore reports 256x316 where the glow
## covers 64x79 - which is exactly what this test used to fail on, by
## checking the number that stopped meaning anything rather than the one that
## still does.
## Run: godot --headless --quit-after 5 --script res://tests/test_selection_outline.gd

## What the patch actually covers on screen.
func _footprint(node: Control) -> Vector2:
	return node.size * node.scale

func _init() -> void:
	# 1. The high-res glow texture assets load
	var tex: Texture2D = load("res://assets/cards/card_sel_glow_ring.png")
	assert(tex != null, "failed to load the glow texture")
	var tex_board: Texture2D = load("res://assets/cards/card_sel_glow.png")
	assert(tex_board != null, "failed to load board hover glow texture")

	var pad: float = SelectionOutline.GLOW_PAD
	var total_pad: float = SelectionOutline.GLOW_PAD + SelectionOutline.OUTLINE_EXPAND

	# 2. Explicit target rect -> glow covers the target grown by total_pad (expand + pad)
	var o := SelectionOutline.new()
	o.set_target_rect(Rect2(3, 4, 44, 59))
	var rect_node: Control = o.get_child(0)
	assert(rect_node.position.is_equal_approx(Vector2(3 - total_pad, 4 - total_pad)), "rect node pos %s" % rect_node.position)
	assert(_footprint(rect_node).is_equal_approx(Vector2(44 + 2 * total_pad, 59 + 2 * total_pad)),
		"glow covers %s on screen" % _footprint(rect_node))
	assert(rect_node.material is ShaderMaterial, "selection glow must use procedural ShaderMaterial")
	assert(SelectionOutline.GLOW_COLOR.is_equal_approx(UIConstants.COLOR_SELECTION_GLOW), "glow color mismatch")

	# 3. Collection's type-row usage: full 204x47 row rect
	var row_outline := SelectionOutline.new()
	row_outline.set_target_rect(Rect2(total_pad, total_pad, 204 - total_pad * 2, 47 - total_pad * 2))
	var row_node: Control = row_outline.get_child(0)
	assert(row_node.position.is_equal_approx(Vector2.ZERO), "row glow pos %s" % row_node.position)
	assert(_footprint(row_node).is_equal_approx(Vector2(204, 47)),
		"row glow covers %s on screen, expected 204x47" % _footprint(row_node))

	o.free()
	row_outline.free()

	print("OK - all SelectionOutline + procedural shader checks passed")
	quit()
