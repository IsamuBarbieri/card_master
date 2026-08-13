class_name FocusNav
extends Node
## Per-screen controller navigation. A screen does:
##
##     nav = FocusNav.new()
##     add_child(nav)
##     nav.add_control(my_button, "some_meta")
##     nav.add_virtual(&"wheel", func(): return some_rect, 1)
##     nav.activated.connect(_on_nav_activated)
##     nav.focus_first()
##
## Deliberately NOT built on Godot's own Control focus system. Only a
## minority of this game's targets are Controls at all - the carousel
## centres in DeckSelect/Shop, Collection's pixel-hit-tested list cells and
## BattleScene's end-of-match cards have no node to focus - so native focus
## would have to be mirrored by a second system anyway, leaving two sources
## of truth for "where is the hand". Registered Buttons get
## focus_mode = FOCUS_NONE so they can't also swallow ui_accept.

signal focus_changed(item: NavItem)
signal activated(item: NavItem)
signal alt_activated(item: NavItem)   # X
signal alt2_activated(item: NavItem)  # Y
signal cancelled()                    # B
signal page(dir: int)                 # LB = -1, RB = +1
signal menu_pressed()                 # Start

class NavItem:
	var id: StringName
	## Re-evaluated every frame rather than stored: carousel cards and
	## tweened slots move, and the hand has to keep pointing at them.
	var rect_fn: Callable
	var enabled_fn: Callable
	var layer := 0
	var scroll: ScrollContainer = null
	var meta: Variant = null
	var control: Control = null
	var links := {}  # Vector2i dir -> NavItem, explicit neighbour overrides
	## When set, left/right (dir.x != 0) call this with -1/+1 instead of
	## moving focus - for sliders. Vertical movement is unaffected, so
	## up/down still leaves the slider normally.
	var axis_fn: Callable

	func rect() -> Rect2:
		return rect_fn.call()

	func enabled() -> bool:
		return enabled_fn.call()

const DIR_UP := Vector2i(0, -1)
const DIR_DOWN := Vector2i(0, 1)
const DIR_LEFT := Vector2i(-1, 0)
const DIR_RIGHT := Vector2i(1, 0)

## How harshly to punish a candidate that is off to the side of the travel
## direction. High enough that a same-column neighbour always beats a nearer
## diagonal one, which is what makes a grid feel like a grid.
const CROSS_AXIS_PENALTY := 3.0

## When true, moving past the last item wraps to the first.
var wrap_h := true
var wrap_v := true
## Screens set this false while a native widget owns input (an OptionButton
## popup) or during a blocking animation.
var active := true

var items: Array[NavItem] = []
var current: NavItem = null

var _layer := 0
var _repeat_dir := Vector2i.ZERO
var _repeat_time := 0.0

# ------------------------------------------------------------- registration

func add_control(c: Control, meta: Variant = null, item_layer: int = 0) -> NavItem:
	# Buttons made from script default to FOCUS_ALL; left alone they would
	# also react to ui_accept and fire twice.
	c.focus_mode = Control.FOCUS_NONE
	var item := NavItem.new()
	item.id = c.name
	item.control = c
	item.rect_fn = func() -> Rect2: return c.get_global_rect()
	item.enabled_fn = func() -> bool:
		return c.is_visible_in_tree() and not (c is Button and (c as Button).disabled)
	item.meta = meta
	item.layer = item_layer
	items.append(item)
	return item

func add_virtual(id: StringName, rect_fn: Callable, meta: Variant = null, item_layer: int = 0, enabled_fn: Callable = Callable()) -> NavItem:
	var item := NavItem.new()
	item.id = id
	item.rect_fn = rect_fn
	item.enabled_fn = enabled_fn if enabled_fn.is_valid() else (func() -> bool: return true)
	item.meta = meta
	item.layer = item_layer
	items.append(item)
	return item

func link(a: NavItem, b: NavItem, dir: Vector2i, bidirectional: bool = true) -> void:
	a.links[dir] = b
	if bidirectional:
		b.links[-dir] = a

func set_scroll(item: NavItem, sc: ScrollContainer) -> void:
	item.scroll = sc

func clear() -> void:
	items.clear()
	current = null
	_repeat_dir = Vector2i.ZERO

## Dialogs and other modal layers: only items on the current layer are
## reachable. Screens with non-modal dialogs (StartMenu toggles plain
## Controls' visibility) get correct behaviour without touching that logic.
func push_layer(n: int) -> void:
	_layer = n
	current = null
	focus_first()

func pop_layer() -> void:
	push_layer(0)

func get_layer() -> int:
	return _layer

# -------------------------------------------------------------------- focus

func focus_first() -> void:
	for item in items:
		if item.layer == _layer and item.enabled():
			set_focus(item)
			return
	current = null

func set_focus(item: NavItem) -> void:
	if item == null or item == current:
		return
	current = item
	_scroll_into_view(item)
	focus_changed.emit(item)

func focus_by_meta(meta: Variant) -> void:
	for item in items:
		if item.layer == _layer and item.meta == meta and item.enabled():
			set_focus(item)
			return

func _scroll_into_view(item: NavItem) -> void:
	if item.scroll == null or item.control == null:
		return
	item.scroll.ensure_control_visible(item.control)

# --------------------------------------------------------------- navigation

## The neighbour scorer, kept static and pure so it can be asserted headlessly
## with synthetic rects (see tests/test_focus_nav.gd). Returns an index into
## `candidates`, or -1 when nothing lies that way.
##
## Scoring: distance along the travel axis, plus a heavy penalty for being
## off-axis, so a slightly-further item in the same column beats a nearer one
## a column over.
static func pick_neighbour(from: Rect2, candidates: Array, dir: Vector2i, wrap: bool) -> int:
	var from_c := from.position + from.size * 0.5
	var best := -1
	var best_score := INF
	for i in candidates.size():
		var r: Rect2 = candidates[i]
		var c := r.position + r.size * 0.5
		var delta := c - from_c
		var along := delta.x * dir.x + delta.y * dir.y
		if along <= 0.0:
			continue  # behind us or exactly level - not in this direction
		var cross := absf(delta.y) if dir.x != 0 else absf(delta.x)
		var score := along + CROSS_AXIS_PENALTY * cross
		if score < best_score:
			best_score = score
			best = i
	if best != -1 or not wrap:
		return best

	# Wrap: jump to the item furthest in the opposite direction, staying as
	# close to the current cross-axis position as possible (so wrapping off
	# the right edge of a grid lands on the same row's left end).
	best_score = INF
	for i in candidates.size():
		var r: Rect2 = candidates[i]
		var c := r.position + r.size * 0.5
		var delta := c - from_c
		var along := delta.x * dir.x + delta.y * dir.y
		if along >= 0.0:
			continue
		var cross := absf(delta.y) if dir.x != 0 else absf(delta.x)
		var score := along + CROSS_AXIS_PENALTY * cross
		if score < best_score:
			best_score = score
			best = i
	return best

func move(dir: Vector2i) -> void:
	if current == null:
		focus_first()
		return
	if dir.x != 0 and current.axis_fn.is_valid():
		current.axis_fn.call(dir.x)
		return
	if current.links.has(dir):
		var linked: NavItem = current.links[dir]
		if linked.enabled():
			set_focus(linked)
			return

	var pool: Array[NavItem] = []
	var rects: Array = []
	for item in items:
		if item == current or item.layer != _layer or not item.enabled():
			continue
		pool.append(item)
		rects.append(item.rect())
	if pool.is_empty():
		return

	var wrap := wrap_h if dir.x != 0 else wrap_v
	var idx := pick_neighbour(current.rect(), rects, dir, wrap)
	if idx != -1:
		set_focus(pool[idx])

# --------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not active or not ControllerUI.is_gamepad():
		return
	# Only swallow the event when something actually consumed it: a screen
	# with no registered items (Credits, Help) still needs A to reach its own
	# _unhandled_input, and FocusNav is a child so it sees input first.
	if event.is_action_pressed(&"nav_accept"):
		if current == null:
			return
		activated.emit(current)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"nav_cancel"):
		cancelled.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"nav_alt"):
		if current == null:
			return
		alt_activated.emit(current)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"nav_alt2"):
		if current == null:
			return
		alt2_activated.emit(current)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"nav_page_prev"):
		page.emit(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"nav_page_next"):
		page.emit(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"nav_menu"):
		menu_pressed.emit()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not active or not ControllerUI.is_gamepad():
		return

	var dir := Vector2i(
		int(Input.is_action_pressed(&"nav_right")) - int(Input.is_action_pressed(&"nav_left")),
		int(Input.is_action_pressed(&"nav_down")) - int(Input.is_action_pressed(&"nav_up")))
	# One axis at a time: diagonal stick input would otherwise pick an
	# unpredictable one of the two.
	if dir.x != 0 and dir.y != 0:
		dir.y = 0

	if dir == Vector2i.ZERO:
		_repeat_dir = Vector2i.ZERO
		_repeat_time = 0.0
	elif dir != _repeat_dir:
		_repeat_dir = dir
		_repeat_time = ControllerUI.NAV_REPEAT_DELAY
		move(dir)
	else:
		_repeat_time -= delta
		if _repeat_time <= 0.0:
			_repeat_time = ControllerUI.NAV_REPEAT_RATE
			move(dir)

	if current != null:
		ControllerUI.point_at(current.rect())
