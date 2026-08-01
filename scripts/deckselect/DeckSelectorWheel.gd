class_name DeckSelectorWheel
extends RefCounted
## 1:1 port of DeckSelector/DeckSelector.cs - one card-selection "wheel":
## a horizontal carousel (bbh, cycles within the current card type) layered
## on a vertical carousel (bbv, cycles between card types), sharing one
## Control (ui_panel) as their shared origin. Used twice by DeckSelect.gd -
## once for "Cards" (favourites=false) and once for "Favorite Cards"
## (favourites=true).
##
## Deviation from the reference: the original bakes each card to a texture
## once (Card.Setup -> a rendered ImageAsset) so it can cheaply clone/dispose
## that texture when handing a card off to the drag-ghost or the lower deck.
## Godot's CardView renders live from a Card reference instead of a baked
## texture, so there's nothing to clone/dispose - callers that need to show
## a removed card elsewhere just build a fresh CardView from the Card this
## class hands back.

const RADIUS := 0.67
const SCALE_MUL := 0.21
const Z_BASE := 10  # keeps every card's z_index positive, above the scene background

var card_width: float = CardView.CARD_W
var card_height: float = CardView.CARD_H

var ui_panel: Control
var ui_box_h: Array = []  # Array[CardView], 4
var ui_box_v: Array = []  # Array[CardView], 4
var bbh := BlackBox.new()
var bbv := BlackBox.new()
var card_matrix := CardMatrix.new()
var cur_index_v: int = 0
var cur_angle_h: float = 0.0
var cur_angle_v: float = 0.0
var moving_vert: bool = false
var force_redraw: bool = false
var shop_mode: bool = false
var input_last_x: int = 0
var input_last_y: int = 0

func central_card_x() -> float:
	if bbh.count == 0:
		return 0.0
	return ui_box_h[bbh.sorted_list[0].array_index].global_position.x

func central_card_y() -> float:
	if bbh.count == 0:
		return 0.0
	return ui_box_h[bbh.sorted_list[0].array_index].global_position.y

func central_card_stats() -> Card:
	if bbh.count == 0:
		return null
	return card_matrix.card_stats_at_index(cur_index_v, bbh.sorted_list[0].val)

func init(panel: Control, cards: Array, use_favourite: bool, use_all: bool, p_shop_mode: bool) -> void:
	ui_panel = panel
	shop_mode = p_shop_mode

	card_matrix.init(cards, use_favourite, use_all)

	for i in 4:
		var cv := CardView.new()
		cv.visible = false
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.pivot_offset = Vector2(card_width, card_height) * 0.5
		ui_panel.add_child(cv)
		ui_box_h.append(cv)

	for i in 4:
		var cv := CardView.new()
		cv.visible = false
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.pivot_offset = Vector2(card_width, card_height) * 0.5
		ui_panel.add_child(cv)
		ui_box_v.append(cv)

	_first_setup()

func update() -> void:
	_update_boxes()

func on_input_setup(x: int, y: int, horz: bool) -> void:
	moving_vert = not horz
	force_redraw = true
	input_last_x = x
	input_last_y = y

func on_input_click(x: int, y: int) -> void:
	var diff: float
	if moving_vert:
		diff = float(y - input_last_y)
	else:
		diff = float(x - input_last_x)
	_add_to_angle(diff)
	input_last_x = x
	input_last_y = y

## Returns {start_angle, angle_diff} (out params in the reference).
func on_input_unclick() -> Dictionary:
	var start_angle: float = cur_angle_v if moving_vert else cur_angle_h

	var angle360: int = int(start_angle) % 360
	if angle360 < 0:
		angle360 += 360

	var final_angle := 0
	if angle360 <= 45 or angle360 >= (360 - 45):
		final_angle = 0
	elif angle360 <= (45 + 90):
		final_angle = 90
	elif angle360 <= (45 + 180):
		final_angle = 180
	elif angle360 <= (45 + 270):
		final_angle = 270

	var angle_diff: float = float(final_angle) - start_angle
	if angle_diff >= 90.0:
		angle_diff -= 360.0
	elif angle_diff <= -90.0:
		angle_diff += 360.0

	return {"start_angle": start_angle, "angle_diff": angle_diff}

func on_input_close() -> void:
	if moving_vert:
		moving_vert = false
		force_redraw = true
		if cur_index_v != bbv.sorted_list[0].val:
			_on_change_type(bbv.sorted_list[0].val)

func central_card_hit_test(x: int, y: int) -> bool:
	if bbh.count == 0:
		return false
	var cv: CardView = ui_box_h[bbh.sorted_list[0].array_index]
	if not cv.visible:
		return false
	return Rect2(cv.global_position, cv.size * cv.scale).has_point(Vector2(x, y))

## Returns the removed Card (reference also hands back a cloned texture -
## see the class-level deviation note).
func remove_current_card() -> Card:
	var result := card_matrix.remove_card_at_index(cur_index_v, bbh.sorted_list[0].val)
	var card_stats: Card = result.card

	if result.type_was_removed:
		if card_matrix.card_types.size() > 0:
			cur_index_v = cur_index_v % card_matrix.card_types.size()
		else:
			cur_index_v = 0
		cur_angle_v = 0.0
		bbv.setup(card_matrix.card_types.size(), cur_index_v, RADIUS, SCALE_MUL)
		_on_change_type(cur_index_v)
	else:
		cur_angle_h = 0.0
		force_redraw = true
		var sc = card_matrix.card_types[cur_index_v]
		bbh.setup(sc.cards.size(), bbh.sorted_list[0].val, RADIUS, SCALE_MUL)
		_update_boxes()

	return card_stats

func add_card(card: Card) -> void:
	if card_matrix.card_types.is_empty():
		cur_index_v = 0
		card_matrix.add_card(card, 0, 0)
		cur_angle_v = 0.0
		bbv.setup(card_matrix.card_types.size(), cur_index_v, RADIUS, SCALE_MUL)
		_on_change_type(cur_index_v)
		return

	var top_card_stats: Card = card_matrix.card_stats_at_index(cur_index_v, bbh.sorted_list[0].val)

	if top_card_stats.def_id == card.def_id:
		card_matrix.add_card(card, -1, bbh.sorted_list[0].val)
		cur_angle_h = 0.0
		force_redraw = true
		var sc = card_matrix.card_types[cur_index_v]
		bbh.setup(sc.cards.size(), bbh.sorted_list[0].val, RADIUS, SCALE_MUL)
		_update_boxes()
	elif card_matrix.card_type_exists(card):
		card_matrix.add_card(card, -1, 0)
		cur_index_v = card_matrix.card_type_index(card)
		cur_angle_v = 0.0
		bbv.setup(card_matrix.card_types.size(), cur_index_v, RADIUS, SCALE_MUL)
		_on_change_type(cur_index_v)
	else:
		card_matrix.add_card(card, cur_index_v, 0)
		cur_angle_v = 0.0
		bbv.setup(card_matrix.card_types.size(), cur_index_v, RADIUS, SCALE_MUL)
		_on_change_type(cur_index_v)

func _update_boxes() -> void:
	var start_x: float = 0.5 * ui_panel.size.x
	var start_y: float = 0.5 * ui_panel.size.y

	if bbv.update(cur_angle_v) or force_redraw:
		var bb := bbv
		for i in 4:
			var cv: CardView = ui_box_v[i]
			if bb.count > 2 or bb.count > i:
				var target_center := Vector2(start_x, start_y + bb.objects[i].x * card_height)
				var s: float = bb.objects[i].scale
				cv.scale = Vector2(s, s)
				cv.position = target_center - cv.pivot_offset
				cv.visible = true

				if bb.objects[i].new_value:
					var val: int = bb.objects[i].val
					cv.setup(card_matrix.card_types[val].cards[0], false, false)
			else:
				cv.visible = false

		var offs := 0.1
		if not moving_vert:
			offs += 0.5
		for obj in bb.sorted_list:
			# sorted_list is Z-ascending (front/closest first) - front must be
			# drawn ON TOP, and Godot's z_index does the opposite of the
			# reference's ZSortOffset (higher = on top here, higher = further
			# back there), so invert around a positive base (Z_BASE) rather
			# than negate outright - negating alone pushed cards below 0,
			# behind the scene's background (default z_index).
			ui_box_v[obj.array_index].z_index = Z_BASE - int(offs * 10)
			offs += 0.1

		ui_box_v[bb.sorted_list[3].array_index].visible = false

	if bbh.update(cur_angle_h) or force_redraw:
		var bb := bbh
		for i in 4:
			var cv: CardView = ui_box_h[i]
			if bb.count > 2 or bb.count > i:
				var target_center := Vector2(start_x + bb.objects[i].x * card_width, start_y)
				var s: float = bb.objects[i].scale
				cv.scale = Vector2(s, s)
				cv.position = target_center - cv.pivot_offset
				cv.visible = true

				if bb.objects[i].new_value:
					var val: int = bb.objects[i].val
					# Card.ShopRenderFlags (Arrows|Stats|Coins) in Shop mode.
					cv.setup(card_matrix.card_types[cur_index_v].cards[val], true, true, shop_mode)
			else:
				cv.visible = false

		var offs := 0.1
		if moving_vert:
			offs += 0.5
		for obj in bb.sorted_list:
			# Same inversion as the V loop above - front card on top.
			ui_box_h[obj.array_index].z_index = Z_BASE - int(offs * 10)
			offs += 0.1

		ui_box_h[bb.sorted_list[3].array_index].visible = false

	if moving_vert:
		ui_box_h[bbh.sorted_list[0].array_index].visible = false
	else:
		ui_box_v[bbv.sorted_list[0].array_index].visible = false

	force_redraw = false

func _first_setup() -> void:
	bbv.setup(card_matrix.card_types.size(), 0, RADIUS, SCALE_MUL)
	_on_change_type(0)

func _on_change_type(index: int) -> void:
	cur_index_v = index
	cur_angle_h = 0.0
	force_redraw = true

	if card_matrix.card_types.size() > 0:
		var sc = card_matrix.card_types[index]
		bbh.setup(sc.cards.size(), 0, RADIUS, SCALE_MUL)
	else:
		bbh.setup(0, 0, RADIUS, SCALE_MUL)

	_update_boxes()

func _add_to_angle(diff: float) -> void:
	diff = clampf(diff, -20.0, 20.0)
	if moving_vert:
		cur_angle_v += diff
		if cur_angle_v >= 360.0:
			cur_angle_v -= 360.0
		elif cur_angle_v <= -360.0:
			cur_angle_v += 360.0
	else:
		cur_angle_h += diff
		if cur_angle_h >= 360.0:
			cur_angle_h -= 360.0
		elif cur_angle_h <= -360.0:
			cur_angle_h += 360.0
