class_name CardView
extends Control
## Visual representation of a Card, built entirely from code (no .tscn)
## by stacking the original card-art layers, ported from Card.cs's
## render-to-texture compositing.

const CARD_W := 96
const CARD_H := 128
const ASSETS_DIR := "res://assets/cards/"

# Normalized (0..1) rects, in arrow order N,NE,E,SE,S,SW,W,NW - matches
# CardManager.cs's dirsVertices/dirsTexcoords (same rect used for position
# and for the UV lookup into card_arrows.png).
const ARROW_RECTS := [
	Rect2(0.4, 0.0, 0.2, 0.2), Rect2(0.8, 0.0, 0.2, 0.2),
	Rect2(0.8, 0.4, 0.2, 0.2), Rect2(0.8, 0.8, 0.2, 0.2),
	Rect2(0.4, 0.8, 0.2, 0.2), Rect2(0.0, 0.8, 0.2, 0.2),
	Rect2(0.0, 0.4, 0.2, 0.2), Rect2(0.0, 0.0, 0.2, 0.2),
]

# Card.cs's minColor/medColor/maxColor gradient for the stat digits.
const STAT_COLOR_MIN := Color(0.0, 1.0, 0.0)
const STAT_COLOR_MED := Color(1.0, 1.0, 0.0)
const STAT_COLOR_MAX := Color(1.0, 100.0 / 255.0, 0.0)

static var _stylish_font: Font = load("res://assets/fonts/font_stylish.ttf")

var card: Card

var _bkg: TextureRect
var _art: TextureRect
var _border: TextureRect
var _arrows_box: Control
var _stat_label: RichTextLabel

func _init() -> void:
	custom_minimum_size = Vector2(CARD_W, CARD_H)
	size = Vector2(CARD_W, CARD_H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_bkg = _make_layer()
	_art = _make_layer()
	_border = _make_layer()
	_arrows_box = Control.new()
	_arrows_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arrows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_arrows_box)

	_stat_label = RichTextLabel.new()
	_stat_label.bbcode_enabled = true
	_stat_label.fit_content = true
	_stat_label.scroll_active = false
	_stat_label.position = Vector2(0, CARD_H - 20)
	_stat_label.size = Vector2(CARD_W, 20)
	_stat_label.add_theme_font_override("normal_font", _stylish_font)
	_stat_label.add_theme_font_size_override("normal_font_size", 15)
	_stat_label.add_theme_constant_override("outline_size", 3)
	_stat_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_stat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stat_label)

static func stat_color(delta: float) -> Color:
	if delta <= 0.5:
		return STAT_COLOR_MIN.lerp(STAT_COLOR_MED, 2.0 * delta)
	return STAT_COLOR_MED.lerp(STAT_COLOR_MAX, (delta - 0.5) / 0.5)

func _make_layer() -> TextureRect:
	var t := TextureRect.new()
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)
	return t

func setup(new_card: Card) -> void:
	card = new_card
	var def: CardManager.CardDef = CardManager.defs[card.def_id]
	var color_name := "blue" if card.owner == 0 else "red"

	_bkg.texture = load(ASSETS_DIR + "card_bkg_%s.png" % color_name)
	_art.texture = load(ASSETS_DIR + def.image)
	_border.texture = load(ASSETS_DIR + "card_border.png")

	var text := card.stat_text()
	var bbcode := "[center]"
	for i in text.length():
		var color := stat_color(CardManager.stat_delta(card, i))
		bbcode += "[color=#%s]%s[/color]" % [color.to_html(false), text[i]]
	bbcode += "[/center]"
	_stat_label.text = bbcode

	for c in _arrows_box.get_children():
		c.queue_free()

	var arrows_tex: Texture2D = load(ASSETS_DIR + "card_arrows.png")
	for i in 8:
		if not card.arrows[i]:
			continue
		var rect: Rect2 = ARROW_RECTS[i]
		var atlas := AtlasTexture.new()
		atlas.atlas = arrows_tex
		atlas.region = Rect2(
			rect.position.x * arrows_tex.get_width(),
			rect.position.y * arrows_tex.get_height(),
			rect.size.x * arrows_tex.get_width(),
			rect.size.y * arrows_tex.get_height()
		)
		var arrow_rect := TextureRect.new()
		arrow_rect.texture = atlas
		arrow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arrow_rect.position = Vector2(rect.position.x * CARD_W, rect.position.y * CARD_H)
		arrow_rect.size = Vector2(rect.size.x * CARD_W, rect.size.y * CARD_H)
		_arrows_box.add_child(arrow_rect)
