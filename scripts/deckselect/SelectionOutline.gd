class_name SelectionOutline
extends Control
## Marks whichever card/row is the current input target with a warm amber & gold
## glow radiating outward from its edge.
##
## Powered by a procedural 2D SDF canvas shader at native screen resolution
## for 4K crispness, zero raster blur, and adaptive corner rounding.

const SHADER := preload("res://shaders/selection_glow.gdshader")

const GLOW_COLOR := UIConstants.COLOR_SELECTION_GLOW
const CORE_COLOR := UIConstants.COLOR_SELECTION_GLOW_CORE
const GLOW_PAD := UIConstants.SELECTION_GLOW_PAD
const OUTLINE_EXPAND := UIConstants.SELECTION_OUTLINE_EXPAND
const CORNER_RADIUS := 1.0
const BORDER_WIDTH := 2.0

var rect: Rect2 = Rect2()
var _rect_node: ColorRect
var _material: ShaderMaterial

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect_node = ColorRect.new()
	_rect_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("glow_color", GLOW_COLOR)
	_material.set_shader_parameter("core_color", CORE_COLOR)
	_material.set_shader_parameter("corner_radius", CORNER_RADIUS)
	_material.set_shader_parameter("border_width", BORDER_WIDTH)
	_material.set_shader_parameter("glow_width", GLOW_PAD)
	_rect_node.material = _material
	add_child(_rect_node)

func set_target_rect(r: Rect2) -> void:
	rect = r
	_material.set_shader_parameter("rect_size", r.size)
	_material.set_shader_parameter("corner_radius", CORNER_RADIUS)
	var grown := r.grow(GLOW_PAD)
	_rect_node.position = grown.position
	_rect_node.size = grown.size
