extends Node
## Dev-only tool: takes a raw screenshot from help_capture.gd and draws
## callout boxes + arrows over it (reusing assets/help_arrow.png, the same
## curved arrow the original hand-made diagrams used) so the result can
## replace the stale assets/help/help_*.png backgrounds. Composed with real
## Godot nodes and screenshotted, rather than hand-rolled pixel math.
## Run:
##   godot --path "d:\Dropbox\Card Master Godot" --resolution 960x544 --position 100,100 res://tools/help_compose.tscn -- --page=shop --in=<raw.png dir> --out=<dir>

const BOX_COLOR := Color(1.0, 0.82, 0.1)
const BOX_OUTLINE := Color(0, 0, 0)
const ARROW_COLOR := Color(0.9, 0.25, 0.15)
const ARROW_WIDTH := 7.0

## rects: Array[Rect2] to outline. arrows: Array of {from, to} straight callouts.
const PAGES := {
	"mainmenu": {
		"rects": [
			Rect2(343, 26, 274, 71),   # Battle
			Rect2(131, 236, 274, 71),  # Shop
			Rect2(556, 236, 274, 71),  # Collection
			Rect2(343, 442, 274, 71),  # Options
			Rect2(407, 199, 146, 146), # Online
		],
		"arrows": [],
	},
	"shop": {
		"rects": [
			Rect2(18, 88, 312, 302),    # wheel
			Rect2(364, 117, 260, 252),  # stats panel
			Rect2(300, 408, 365, 118),  # sell/buy buttons + values
			Rect2(700, 456, 230, 68),   # coin count
			Rect2(634, 113, 310, 270),  # buyable offers list
		],
		"arrows": [
			{"from": Vector2(260, 300), "to": Vector2(380, 415)},
		],
	},
	"deckselect": {
		"rects": [
			Rect2(0, 72, 348, 348),     # Cards wheel
			Rect2(612, 72, 348, 348),   # Favorite Cards wheel
			Rect2(361, 118, 242, 232),  # stats panel
			Rect2(233, 387, 492, 136),  # 5-slot deck row
			Rect2(42, 463, 115, 56),    # Back
			Rect2(798, 463, 115, 56),   # Play
		],
		"arrows": [
			{"from": Vector2(174, 340), "to": Vector2(270, 420)},
			{"from": Vector2(786, 340), "to": Vector2(690, 420)},
		],
	},
	"battle": {
		"rects": [
			Rect2(0, 4, 280, 198),      # scoreboard
			Rect2(38, 218, 195, 60),    # opponent's hidden hand
			Rect2(24, 292, 228, 236),   # stats panel
			Rect2(710, 55, 220, 425),   # player hand column
		],
		"arrows": [
			# You drag FROM your hand INTO the grid, not the other way round -
			# points from the hand column toward an open board cell, routed
			# below the "drag the cards..." caption box (which ends y=260)
			# instead of starting from underneath it.
			{"from": Vector2(742, 270), "to": Vector2(430, 270)},
		],
	},
}

func _ready() -> void:
	var page := "mainmenu"
	var in_dir := "."
	var out_dir := "."
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--page="):
			page = a.substr("--page=".length())
		elif a.begins_with("--in="):
			in_dir = a.substr("--in=".length())
		elif a.begins_with("--out="):
			out_dir = a.substr("--out=".length())

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child.call_deferred(root)
	await get_tree().process_frame

	var bg := TextureRect.new()
	bg.texture = ImageTexture.create_from_image(Image.load_from_file(in_dir + "/" + page + ".png"))
	bg.size = Vector2(960, 544)
	root.add_child(bg)

	var cfg: Dictionary = PAGES[page]
	for r in cfg["rects"]:
		root.add_child(_make_box(r))
	for a in cfg["arrows"]:
		root.add_child(_make_arrow(a["from"], a["to"]))

	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path := out_dir + "/" + page + ".png"
	img.save_png(path)
	print("saved " + path)
	get_tree().quit()

func _make_box(r: Rect2) -> Control:
	var outer := Panel.new()
	outer.position = r.position - Vector2(3, 3)
	outer.size = r.size + Vector2(6, 6)
	var outer_sb := StyleBoxFlat.new()
	outer_sb.bg_color = Color(0, 0, 0, 0)
	outer_sb.border_color = BOX_OUTLINE
	outer_sb.set_border_width_all(6)
	outer.add_theme_stylebox_override("panel", outer_sb)

	var inner := Panel.new()
	inner.position = Vector2(3, 3)  # local to outer, which is already inset by 3px
	inner.size = r.size
	var inner_sb := StyleBoxFlat.new()
	inner_sb.bg_color = Color(0, 0, 0, 0)
	inner_sb.border_color = BOX_COLOR
	inner_sb.set_border_width_all(3)
	inner.add_theme_stylebox_override("panel", inner_sb)
	outer.add_child(inner)

	return outer

## A straight shaft (with a thin black outline for contrast) plus a triangular
## head, pointing from `from` to `to` - simpler and crisper than trying to
## reuse help_arrow.png, which turned out to be a faint decorative asset, not
## the bold curved arrow the old hand-painted diagrams used.
func _make_arrow(from: Vector2, to: Vector2) -> Node2D:
	var node := Node2D.new()
	var dir := (to - from).normalized()
	var head_len := 22.0
	var head_w := 16.0
	var shaft_end := to - dir * head_len * 0.7

	for shaft in [
		{"width": ARROW_WIDTH + 4.0, "color": Color(0, 0, 0)},
		{"width": ARROW_WIDTH, "color": ARROW_COLOR},
	]:
		var line := Line2D.new()
		line.add_point(from)
		line.add_point(shaft_end)
		line.width = shaft["width"]
		line.default_color = shaft["color"]
		node.add_child(line)

	var perp := Vector2(-dir.y, dir.x)
	for head in [
		{"scale": 1.3, "color": Color(0, 0, 0)},
		{"scale": 1.0, "color": ARROW_COLOR},
	]:
		var poly := Polygon2D.new()
		var s: float = head["scale"]
		poly.polygon = PackedVector2Array([
			to,
			to - dir * head_len * s + perp * head_w * 0.5 * s,
			to - dir * head_len * s - perp * head_w * 0.5 * s,
		])
		poly.color = head["color"]
		node.add_child(poly)

	return node
