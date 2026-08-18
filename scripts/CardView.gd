class_name CardView
extends Control
## Visual representation of a Card, built entirely from code (no .tscn)
## by stacking the original card-art layers, ported from Card.cs's
## render-to-texture compositing.

const CARD_W := 96
const CARD_H := 128
const ASSETS_DIR := "res://assets/cards/"

# card_border.png's inner clear area, measured by walking the asset's own
# alpha rather than by eye. Down to y=112 the frame leaves x=7.5..88 clear;
# below that the bottom corner ornaments close in to about 68px. The band used
# to run to y=119, so its lowest rows were printed straight over those
# ornaments - which is what made the stats look like they were spilling onto
# the frame.
const STAT_AREA_LEFT := 8
const STAT_AREA_RIGHT := 88
const STAT_AREA_BOTTOM := 112
## Two rather than three: the stroke grows the glyphs outward on both sides, so
## every pixel of it is a pixel the digits don't get, and at this size the
## third one buys very little contrast.
const STAT_OUTLINE := 2

# Every card in the game - battle, shop, collection - is this same 96x128
# CardView scaled as a whole, so the stat digits are only ever as legible as
# this one number makes them. It was 22, which left roughly a fifth of the
# available width unused and read as tiny on a phone; it is now the largest
# size whose widest possible stat_text() ("F"-class digits plus the widest
# attack-type letter, plus the outline stroke on both sides) still fits
# STAT_AREA_LEFT..RIGHT. tests/test_card_stat_fit.gd measures that against the
# real font and fails if a font or asset change ever makes it overflow, so
# this is a checked number rather than an eyeballed one.
const STAT_FONT_SIZE := 28
const STAT_FONT_SIZE_HEIGHT := 35

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

var card: Card

var _bkg: TextureRect
var _art: TextureRect
var _border: TextureRect
var _arrows_box: Control
var _stat_label: RichTextLabel
var _price_label: RichTextLabel

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
	# card_border.png's inner (non-frame) area at the bottom-center only
	# starts clearing up at y=119 of the 96x128 card (measured against the
	# actual asset), so the stat text must sit fully above that line - not
	# flush with the card's bottom edge - or the frame's bottom trim covers it.
	_stat_label.position = Vector2(0, STAT_AREA_BOTTOM - STAT_FONT_SIZE_HEIGHT)
	_stat_label.size = Vector2(CARD_W, STAT_FONT_SIZE_HEIGHT)
	# Medium, not Regular: four characters over busy card art at the
	# smallest size in the game - the extra weight is what keeps them
	# readable rather than merely present.
	_stat_label.add_theme_font_override("normal_font", Game.font_emphasis)
	_stat_label.add_theme_font_size_override("normal_font_size", STAT_FONT_SIZE)
	_stat_label.add_theme_constant_override("outline_size", STAT_OUTLINE)
	_stat_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_stat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stat_label)

	# Card.cs's drawCoins() - price text + a small coin icon, centered as one
	# group on the card. RichTextLabel's inline [img] BBCode does the "text
	# then icon side by side" layout for free instead of measuring text
	# width by hand like the reference does.
	_price_label = RichTextLabel.new()
	_price_label.bbcode_enabled = true
	_price_label.fit_content = true
	_price_label.scroll_active = false
	_price_label.position = Vector2(0, CARD_H / 2.0 - 15)
	_price_label.size = Vector2(CARD_W, 30)
	_price_label.add_theme_font_override("normal_font", Game.font_stylish)
	_price_label.add_theme_font_size_override("normal_font_size", UIConstants.CARDVIEW_PRICE_FONT_SIZE)
	_price_label.add_theme_color_override("default_color", Color.WHITE)
	_price_label.add_theme_constant_override("outline_size", 3)
	_price_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_price_label.visible = false
	_price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_price_label)

static func stat_color(delta: float) -> Color:
	if delta <= 0.5:
		return STAT_COLOR_MIN.lerp(STAT_COLOR_MED, 2.0 * delta)
	return STAT_COLOR_MED.lerp(STAT_COLOR_MAX, (delta - 0.5) / 0.5)

func _make_layer() -> TextureRect:
	var t := TextureRect.new()
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)
	return t

## show_stats/show_arrows/show_price port Card.cs's RenderFlag.Stats/Arrows/
## Coins - e.g. UIOpponents.cs sets renderFlags=0 for its AI portraits, so
## those show plain art with no stat text or arrows. show_price is Shop's
## ShopRenderFlags (Arrows|Stats|Coins).
func setup(new_card: Card, show_stats := true, show_arrows := true, show_price := false) -> void:
	card = new_card
	var def: CardManager.CardDef = CardManager.defs[card.def_id]
	var color_name := "blue" if card.owner == 0 else "red"

	# Port of Card.cs's isVoid special case: "The Void" has its own unique
	# owner-tinted art (background baked in) instead of the generic
	# card_bkg_%s.png + monster-art layering every other card uses, drawn
	# over a plain black backdrop rather than the blue/red gradient bkg.
	if def.name == "The Void":
		_bkg.texture = load(UIConstants.ICON_BLACK_PIXEL)
		_art.texture = load(ASSETS_DIR + "the_void_%s.png" % color_name)
	else:
		_bkg.texture = load(ASSETS_DIR + "card_bkg_%s.png" % color_name)
		_art.texture = load(ASSETS_DIR + def.image)
	_border.texture = load(ASSETS_DIR + "card_border.png")

	_stat_label.visible = show_stats
	if show_stats:
		var text := card.stat_text()
		var bbcode := "[center]"
		for i in text.length():
			var color := stat_color(CardManager.stat_delta(card, i))
			bbcode += "[color=#%s]%s[/color]" % [color.to_html(false), text[i]]
		bbcode += "[/center]"
		_stat_label.text = bbcode

	_price_label.visible = show_price
	if show_price:
		_price_label.text = "[center]%d [img=18x18]%s[/img][/center]" % [CardManager.card_price(card), UIConstants.ICON_COIN]

	for c in _arrows_box.get_children():
		c.queue_free()
	if not show_arrows:
		return

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
		arrow_rect.stretch_mode = TextureRect.STRETCH_SCALE
		arrow_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		arrow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arrow_rect.position = Vector2(rect.position.x * CARD_W, rect.position.y * CARD_H)
		arrow_rect.size = Vector2(rect.size.x * CARD_W, rect.size.y * CARD_H)
		_arrows_box.add_child(arrow_rect)
