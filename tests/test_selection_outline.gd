extends SceneTree
## Geometry checks for SelectionOutline's 9-patch glow, plus a load check on
## the generated glow/FX textures.
## Run: godot --headless --quit-after 5 --script res://tests/test_selection_outline.gd

func _init() -> void:
	# 1. new assets all load
	for path in [
		"res://assets/cards/card_sel_glow_ring.png",
		"res://assets/battle/fx_shockwave.png",
		"res://assets/battle/fx_burst.png",
	]:
		assert(load(path) != null, "failed to load " + path)

	var pad: float = SelectionOutline.GLOW_PAD

	# 2. explicit target rect -> patch is the target grown by GLOW_PAD, tinted blue
	var o := SelectionOutline.new()
	o.set_target_rect(Rect2(3, 4, 44, 59))
	var patch: NinePatchRect = o.get_child(0)
	assert(patch.position.is_equal_approx(Vector2(3 - pad, 4 - pad)), "patch pos %s" % patch.position)
	assert(patch.size.is_equal_approx(Vector2(44 + 2 * pad, 59 + 2 * pad)), "patch size %s" % patch.size)
	assert(not patch.modulate.is_equal_approx(Color.WHITE), "glow must be tinted, not left white")
	assert(patch.modulate.is_equal_approx(SelectionOutline.GLOW_COLOR), "glow tint %s" % patch.modulate)
	# 9-patch corners must fit inside the smallest rect we ask for
	assert(patch.size.x >= SelectionOutline.PATCH_MARGIN * 2, "card cell too small for 9-patch")
	assert(patch.size.y >= SelectionOutline.PATCH_MARGIN * 2, "card cell too small for 9-patch")

	# 3. Collection's type-row usage: full 204x47 row rect, not just the label
	var row_outline := SelectionOutline.new()
	row_outline.set_target_rect(Rect2(pad, pad, 204 - pad * 2, 47 - pad * 2))
	var row_patch: NinePatchRect = row_outline.get_child(0)
	assert(row_patch.position.is_equal_approx(Vector2.ZERO), "row patch pos %s" % row_patch.position)
	assert(row_patch.size.is_equal_approx(Vector2(204, 47)), "row patch size %s" % row_patch.size)

	print("OK - all SelectionOutline + asset checks passed")
	quit()
