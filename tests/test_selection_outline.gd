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
func _footprint(patch: NinePatchRect) -> Vector2:
	return patch.size * patch.scale

func _init() -> void:
	# 1. the generated glow texture loads, and is big enough for the corners
	var tex: Texture2D = load("res://assets/cards/card_sel_glow_ring.png")
	assert(tex != null, "failed to load the glow texture")
	assert(SelectionOutline.PATCH_MARGIN * 2 <= tex.get_width(),
		"the 9-patch corners (2 x %d) do not fit the %dpx texture" % [SelectionOutline.PATCH_MARGIN, tex.get_width()])

	var pad: float = SelectionOutline.GLOW_PAD
	## Smallest rect the glow can cover before its own corners overlap: the
	## corners are drawn at native size, shrunk by the node scale.
	var min_side: float = 2.0 * SelectionOutline.PATCH_MARGIN * SelectionOutline.NODE_SCALE

	# 2. explicit target rect -> glow covers the target grown by GLOW_PAD, tinted blue
	var o := SelectionOutline.new()
	o.set_target_rect(Rect2(3, 4, 44, 59))
	var patch: NinePatchRect = o.get_child(0)
	assert(patch.position.is_equal_approx(Vector2(3 - pad, 4 - pad)), "patch pos %s" % patch.position)
	assert(_footprint(patch).is_equal_approx(Vector2(44 + 2 * pad, 59 + 2 * pad)),
		"patch covers %s on screen (raw size %s at scale %s)" % [_footprint(patch), patch.size, patch.scale])
	assert(not patch.modulate.is_equal_approx(Color.WHITE), "glow must be tinted, not left white")
	assert(patch.modulate.is_equal_approx(SelectionOutline.GLOW_COLOR), "glow tint %s" % patch.modulate)

	# 9-patch corners must fit inside the smallest rect we ask for, or opposite
	# corners overlap and the falloff doubles up along the short edge.
	assert(_footprint(patch).x >= min_side, "card cell too narrow for the 9-patch corners")
	assert(_footprint(patch).y >= min_side, "card cell too short for the 9-patch corners")

	# 3. Collection's type-row usage: full 204x47 row rect, not just the label
	var row_outline := SelectionOutline.new()
	row_outline.set_target_rect(Rect2(pad, pad, 204 - pad * 2, 47 - pad * 2))
	var row_patch: NinePatchRect = row_outline.get_child(0)
	assert(row_patch.position.is_equal_approx(Vector2.ZERO), "row patch pos %s" % row_patch.position)
	assert(_footprint(row_patch).is_equal_approx(Vector2(204, 47)),
		"row glow covers %s on screen, expected 204x47" % _footprint(row_patch))
	assert(_footprint(row_patch).y >= min_side, "list row too short for the 9-patch corners")

	print("OK - all SelectionOutline + asset checks passed")
	quit()
