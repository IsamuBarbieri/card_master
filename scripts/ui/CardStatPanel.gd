class_name CardStatPanel
extends Control
## The card readout - name, then Attack / Type / P.Def / M.Def - as one
## control shared by every screen that shows it: Shop, DeckSelect, Collection,
## and both of BattleScene's (the one beside the board and the one on the end
## screen).
##
## There used to be five hand-laid copies of this, each with its own column
## widths, its own row step and its own _set_stat_value. They had drifted:
## DeckSelect spelled the captions out in full and so had only 108px left for
## the value, which cut "Physical" to "Physic"; Shop fitted every label to its
## own text, so a row reading "255" was drawn half again as large as the row
## reading "Magical" right under it; and both fell back to a floor size and
## overflowed rather than clip when nothing fit. All three are the same bug -
## per-label decisions in a panel that has to read as one block.
##
## So the size is decided ONCE per panel, not once per label: the largest size
## at which every caption AND every value the panel can ever show still fits
## its column, in the current language. Rows therefore always match each
## other, and nothing can overflow, because the string that would have
## overflowed is one of the strings the size was chosen to fit.

## Abbreviated captions everywhere. The full words ("Physical Defense",
## "Phys. Verteidigung") are what forced DeckSelect's value column narrow;
## with one shared size they would also drag every other row down to the size
## the longest translation needs.
const CAPTION_IDS := [
	StringTable.ID_CARD_ATTACK_SHORT, StringTable.ID_CARD_TYPE_SHORT,
	StringTable.ID_CARD_PDEF_SHORT, StringTable.ID_CARD_MDEF_SHORT,
]
const ATTACK_TYPE_IDS := [
	StringTable.ID_ATTACK_TYPE_PHYSICAL, StringTable.ID_ATTACK_TYPE_MAGICAL,
	StringTable.ID_ATTACK_TYPE_FLEXIBLE, StringTable.ID_ATTACK_TYPE_ASSAULT,
]

const ROW_COUNT := 4
## Share of the panel height the name heading takes. The four stat rows split
## what is left.
const HEADING_SHARE := 0.21
## Share of the width for the caption column. The value column takes the rest,
## which is the wider of the two because it carries the spelled-out attack
## type while the caption is abbreviated.
const CAPTION_SHARE := 0.36
## Gap between the heading and the first row, as a share of the height.
const HEADING_GAP_SHARE := 0.04

const MAX_FONT_SIZE := 40
## Below this the readout stops being readable on a phone; a panel that cannot
## fit its own strings at this size is a layout bug, not something to silently
## shrink past. Matches BattleScene.MIN_READABLE_FONT_SIZE's reasoning.
const MIN_FONT_SIZE := 18

const NAME_COLOR := Color.BLACK
const TEXT_COLOR := Color.BLACK
## A one-pixel soft drop shadow. The readouts sit on a pale panel and read
## flat without it; this is the same offset the menu labels already use.
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)
const SHADOW_OFFSET := 1

var name_label: Label
var caption_labels: Array[Label] = []
var value_labels: Array[Label] = []

var _row_font_size := MAX_FONT_SIZE

## `box` is the space the readout may use, already inset from whatever frame
## it sits in - this control draws nothing itself.
static func make(box: Vector2) -> CardStatPanel:
	var panel := CardStatPanel.new()
	panel.size = box
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel._build()
	return panel

func _label(pos: Vector2, label_size: Vector2, align: int) -> Label:
	var l := FixedSizeLabel.new()
	l.position = pos
	l.size = label_size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# The backstop: the size below is chosen so nothing needs clipping, but a
	# card name added later should not be able to run over the frame.
	l.clip_text = true
	l.add_theme_font_override("font", Game.font_stylish)
	l.add_theme_color_override("font_color", TEXT_COLOR)
	l.add_theme_color_override("font_shadow_color", SHADOW_COLOR)
	l.add_theme_constant_override("shadow_offset_x", SHADOW_OFFSET)
	l.add_theme_constant_override("shadow_offset_y", SHADOW_OFFSET)
	add_child(l)
	return l

## The row geometry a given box produces. Static so the layout can be
## measured without building a panel - the tests check every screen's box in
## every language, which is 45 panels' worth of controls otherwise.
static func heading_height(box: Vector2) -> float:
	return box.y * HEADING_SHARE

static func row_height(box: Vector2) -> float:
	return (box.y - heading_height(box) - box.y * HEADING_GAP_SHARE) / float(ROW_COUNT)

static func caption_box(box: Vector2) -> Vector2:
	return Vector2(box.x * CAPTION_SHARE, row_height(box))

static func value_box(box: Vector2) -> Vector2:
	return Vector2(box.x - box.x * CAPTION_SHARE, row_height(box))

## The one size every caption and every value in the panel is drawn at: the
## largest at which the worst case still fits. `lang` picks a language table
## directly, for tests that need to check all nine without touching
## Game.language (which persists to disk); -1 means the current one.
static func row_size_for(box: Vector2, lang: int = -1) -> int:
	var font: Font = Game.font_stylish
	var cap := caption_box(box)
	var val := value_box(box)
	var best := MAX_FONT_SIZE
	for id in CAPTION_IDS:
		best = mini(best, UIButtonStyle.fit_text_to_box(_text(id, lang), font, cap, MAX_FONT_SIZE, MIN_FONT_SIZE))
	for id in ATTACK_TYPE_IDS:
		best = mini(best, UIButtonStyle.fit_text_to_box(_text(id, lang), font, val, MAX_FONT_SIZE, MIN_FONT_SIZE))
	# The widest a stat can get, and the placeholder shown with nothing
	# selected - neither is translated, both have to fit the value column.
	for text in ["255", "- - -"]:
		best = mini(best, UIButtonStyle.fit_text_to_box(text, font, val, MAX_FONT_SIZE, MIN_FONT_SIZE))
	return best

static func _text(id: int, lang: int) -> String:
	return StringTable.get_string(id) if lang < 0 else StringTable.TABLE[lang][id]

func _build() -> void:
	var heading_h := heading_height(size)
	var rows_top := heading_h + size.y * HEADING_GAP_SHARE
	var row_h := row_height(size)
	var caption_w := size.x * CAPTION_SHARE
	var value_w := size.x - caption_w

	name_label = _label(Vector2.ZERO, Vector2(size.x, heading_h), HORIZONTAL_ALIGNMENT_CENTER)
	name_label.add_theme_color_override("font_color", NAME_COLOR)

	for i in ROW_COUNT:
		var y := rows_top + i * row_h
		caption_labels.append(_label(Vector2(0, y), Vector2(caption_w, row_h), HORIZONTAL_ALIGNMENT_LEFT))
		# Right-aligned against the panel's inner edge so one- and
		# three-digit values line up in a column instead of drifting.
		value_labels.append(_label(Vector2(caption_w, y), Vector2(value_w, row_h), HORIZONTAL_ALIGNMENT_RIGHT))

	refresh_language()

## Recomputes the shared size and re-fills the captions. Called at build time
## and again whenever the language changes, since every string this measures
## is a translated one.
func refresh_language() -> void:
	var font: Font = Game.font_stylish
	_row_font_size = row_size_for(size)
	for i in ROW_COUNT:
		caption_labels[i].add_theme_font_override("font", font)
		caption_labels[i].text = StringTable.get_string(CAPTION_IDS[i])
		caption_labels[i].add_theme_font_size_override("font_size", _row_font_size)
		value_labels[i].add_theme_font_override("font", font)
		value_labels[i].add_theme_font_size_override("font_size", _row_font_size)
	name_label.add_theme_font_override("font", font)
	_fit_name()

## The heading is fitted on its own: card names are proper nouns that do not
## grow with the language the way the captions do, and holding the whole panel
## down to the longest one would waste the row space for every other card.
func _fit_name() -> void:
	name_label.add_theme_font_size_override("font_size", UIButtonStyle.fit_text_to_box(
		name_label.text, Game.font_stylish, name_label.size, MAX_FONT_SIZE, MIN_FONT_SIZE))

## Largest size the four stat rows settled on - what the tests measure.
func row_font_size() -> int:
	return _row_font_size

func show_card(card: Card, owned: bool = false) -> void:
	if card == null:
		clear()
		return
	name_label.text = CardManager.defs[card.def_id].name
	name_label.add_theme_color_override("font_color", NAME_COLOR)
	_fit_name()
	value_labels[0].text = str(card.attack_power)
	value_labels[1].text = CardManager.attack_type_to_string(card.attack_type)
	value_labels[2].text = str(card.physical_defense)
	value_labels[3].text = str(card.magical_defense)

## Nothing selected: the heading falls back to the panel's own title.
func clear() -> void:
	name_label.text = StringTable.get_string(StringTable.ID_CARD_STATS)
	name_label.add_theme_color_override("font_color", NAME_COLOR)
	_fit_name()
	for v in value_labels:
		v.text = "- - -"
