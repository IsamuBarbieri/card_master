class_name BlackBox
extends RefCounted
## 1:1 port of DeckSelector/BlackBox.cs - the carousel rotation math shared
## by both wheel axes (horizontal cycle-within-type, vertical cycle-between-
## types) in DeckSelectorWheel.gd. Pure math, no rendering.
##
## Positions 4 "slots" around a circle of the given radius (in card-size
## units) at 90-degree intervals; as curAngle changes, each slot's X/Z
## offset and Scale (depth-based) update, and the slot currently furthest
## back (highest Z) gets recycled to the next/previous value as it wraps
## around - giving the illusion of an endless card wheel from only 4 nodes.

class Obj:
	var x: float = 0.0       # x offset (in pixels once scaled by caller)
	var y: float = 0.0       # unused (kept for 1:1 field parity with reference)
	var z: float = 0.0       # depth
	var scale: float = 1.0
	var new_value: bool = false  # true if val changed this Update()
	var val: int = 0
	var array_index: int = 0

var radius: float = 0.0
var cur_angle: float = 0.0
var min_angle: float = 0.0
var max_angle: float = 0.0
var scale_mul: float = 0.0
var count: int = 0
var first_update: bool = false

var sorted_list: Array = []  # Array[Obj], sorted by Z each Update()
var objects: Array = []      # Array[Obj], fixed order (array_index)

func _init() -> void:
	for i in 4:
		var obj := Obj.new()
		obj.array_index = i
		objects.append(obj)
		sorted_list.append(obj)

func setup(num_objects: int, front_object_index: int, p_radius: float, p_scale_mul: float) -> void:
	count = num_objects
	if count <= 0:
		return

	cur_angle = 0.0
	first_update = true
	radius = p_radius
	scale_mul = p_scale_mul

	objects[0].val = (0 + front_object_index) % count
	objects[1].val = (1 + front_object_index) % count
	objects[2].val = (2 + front_object_index) % count
	objects[3].val = objects[0].val - 1
	if objects[3].val < 0:
		objects[3].val += count

	if count == 1:
		min_angle = 0.0
		max_angle = 0.0
	elif count == 2:
		# Deliberately NOT wrapped, unlike count >= 3: with only 2 items,
		# looping past the far one straight back to the near one reads as an
		# ugly snap rather than a spin (confirmed by feel, not a bug) - the
		# clamp caps rotation to a quarter turn so it just stops there.
		min_angle = -90.0
		max_angle = 0.0
	else:
		min_angle = -INF
		max_angle = INF

func update(new_angle: float) -> bool:
	if count == 0:
		return false

	var cur_dir := new_angle - cur_angle

	if absf(cur_dir) < 0.01 and not first_update:
		return false

	cur_angle = new_angle

	if cur_angle < min_angle:
		cur_angle = min_angle
	elif cur_angle > max_angle:
		cur_angle = max_angle

	const ANGLE_STEP := 360.0 / 4.0

	for i in 4:
		var angle: float = cur_angle + ANGLE_STEP * float(i)
		var rad := deg_to_rad(angle)

		var x: float = radius * sin(rad)
		var y: float = -(radius * cos(rad) - radius)

		objects[i].x = x
		objects[i].y = 0.0
		objects[i].z = y
		objects[i].new_value = first_update
		objects[i].scale = 1.0 - scale_mul * (y / radius)

	sorted_list.sort_custom(func(a: Obj, b: Obj) -> bool: return a.z < b.z)

	var test_index: int = sorted_list[3].array_index
	var new_value: int = 0

	if cur_dir < 0.0:
		var prev := test_index - 1
		if prev < 0:
			prev += 4
		new_value = objects[prev].val + 1
	else:
		var next := (test_index + 1) % 4
		new_value = objects[next].val - 1

	if new_value < 0:
		new_value += count
	new_value %= count

	if objects[test_index].val != new_value:
		objects[test_index].val = new_value
		objects[test_index].new_value = true

	first_update = false

	return true
