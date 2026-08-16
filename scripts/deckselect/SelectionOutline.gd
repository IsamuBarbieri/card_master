class_name SelectionOutline
extends Control
## Marks whichever card/row is the current input target with a small
## light-blue glow radiating outward from its edge.
##
## Drawn as a 9-patch rather than a stretched texture or per-frame draw_rect
## layers: callers target wildly different aspect ratios (96x128 cards,
## 44x59 collection cells, ~200x47 list rows), and only 9-slicing keeps the
## falloff identical on every edge instead of smearing it on the long axis.
## The texture (assets/cards/card_sel_glow_ring.png, generated supersampled
## + box-downsampled by scratchpad/gen_tex.py) is authored white and tinted
## here via modulate, bakes a GLOW_PAD-wide falloff into its border, so the
## patch rect is always the target grown by GLOW_PAD and the bright edge
## lands exactly on the target's outline.

const GLOW_TEXTURE := preload("res://assets/cards/card_sel_glow_ring.png")
const GLOW_COLOR := Color(0.45, 0.78, 1.0)
const GLOW_PAD := 10.0
## Texture is 256x256 (4x-upscaled from an authored 64x64 with a 10px glow
## border); 88 (4x the original 22) keeps the whole falloff (pad + inner
## edge line) inside the fixed corners, leaving only fully transparent
## pixels in the stretched middle.
const PATCH_MARGIN := 88
## NinePatchRect always draws its corners at native texel size (1:1, no
## stretch), so slicing the full 4x-upscaled corner and expecting it to
## land at the original on-screen footprint doesn't work by patch_margin
## alone. _patch is built oversized at 4x and then scaled back down by this
## factor, so the corners sample the extra texture detail but still cover
## the same screen area as before the upscale.
const NODE_SCALE := 0.25

var rect: Rect2 = Rect2()
var _patch: NinePatchRect

func _init() -> void:
	_patch = NinePatchRect.new()
	_patch.texture = GLOW_TEXTURE
	_patch.modulate = GLOW_COLOR
	_patch.patch_margin_left = PATCH_MARGIN
	_patch.patch_margin_right = PATCH_MARGIN
	_patch.patch_margin_top = PATCH_MARGIN
	_patch.patch_margin_bottom = PATCH_MARGIN
	_patch.scale = Vector2(NODE_SCALE, NODE_SCALE)
	_patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_patch)

func set_target_rect(r: Rect2) -> void:
	rect = r
	var grown := r.grow(GLOW_PAD)
	_patch.position = grown.position
	_patch.size = grown.size / NODE_SCALE
