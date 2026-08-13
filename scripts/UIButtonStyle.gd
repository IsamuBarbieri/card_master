class_name UIButtonStyle
extends RefCounted
## PSM's default Button style (BackgroundType="Default" in CardMaster.uic,
## used whenever a composer Button has no explicit CustomImage) renders with
## system_assets/button_9patch_normal/press/disable.png as a 9-slice
## background - NinePatchMargin(21,21,21,21) everywhere it's used explicitly
## (see UIStartMenu/UIHelp composer). Not flat/transparent as assumed
## earlier. StyleBoxTexture's texture_margin already gives the correct
## 9-slice behavior (corners drawn at native resolution, only the middle
## stretches) with no extra config needed.
## content_margin is left at -1 by default, which falls back to
## texture_margin (21px/side) - Godot then clamps the button's actual size
## up to fit content_margin + font line height, inflating every button well
## past its explicit composer size (e.g. a 56px-tall button ballooning past
## 90px). Pinned small here so buttons render at their real composer size.

const MARGIN := 21
const CONTENT_MARGIN := 6
const ASSETS := "res://assets/"

static func apply(btn: Button) -> void:
	var normal := _make_stylebox("button_9patch_normal.png")
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", normal)
	btn.add_theme_stylebox_override("pressed", _make_stylebox("button_9patch_press.png"))
	btn.add_theme_stylebox_override("disabled", _make_stylebox("button_9patch_disable.png"))
	# Controller focus: the hand cursor is the primary indicator, but a
	# brightened pressed-skin underneath makes it unambiguous which button
	# would fire. Not used by mouse input - FocusNav sets focus_mode = NONE
	# on everything it registers, so nothing gets a focus ring by accident.
	btn.add_theme_stylebox_override("focus", _make_stylebox("button_9patch_press.png"))

static func _make_stylebox(texture_name: String) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(ASSETS + texture_name)
	sb.texture_margin_left = MARGIN
	sb.texture_margin_right = MARGIN
	sb.texture_margin_top = MARGIN
	sb.texture_margin_bottom = MARGIN
	sb.content_margin_left = CONTENT_MARGIN
	sb.content_margin_right = CONTENT_MARGIN
	sb.content_margin_top = CONTENT_MARGIN
	sb.content_margin_bottom = CONTENT_MARGIN
	return sb

## New QoL addition (not in the reference, which never localized past a
## fixed-width composer layout): shared text-fit helpers so translated
## strings longer than English/Italian don't clip or spill onto neighboring
## UI. Smallest size still legible on the 960x544 canvas at the game's
## existing smallest in-use body text (Collection/Help dialogs already sit
## at 20-24px).
const MIN_FONT_SIZE := 18
const FONT_SHRINK_STEP := 1
## Hard last-resort floor for fit_button_text: below MIN_FONT_SIZE isn't
## great, but resizing the control is worse (breaks the hand-tuned layout
## other elements were positioned around), so ordinary buttons/labels always
## solve overflow by shrinking the font, never by growing the box - this is
## how far that shrink is allowed to go.
const ABSOLUTE_MIN_FONT_SIZE := 10

## Largest font size <= max_font_size (down to floor_size) at which `font`
## renders `text` no wider than max_width. Never returns below floor_size
## even if text still doesn't fit there - caller decides what to do then.
static func fit_text_to_width(text: String, font: Font, max_width: float, max_font_size: int, floor_size: int = MIN_FONT_SIZE) -> int:
	var size := max_font_size
	while size > floor_size:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if w <= max_width:
			return size
		size -= FONT_SHRINK_STEP
	return floor_size

## Sets ctrl's size and, if it's a FixedSizeButton/FixedSizeLabel (every
## control this module's fit_* functions manage should be), locks it there
## against Godot's own layout re-inflating it again on a later pass - a
## one-time assignment isn't reliable here, see FixedSizeButton's docstring.
static func _pin_size(ctrl: Control, target_size: Vector2) -> void:
	if ctrl.has_method("lock_size"):
		ctrl.lock_size(target_size)
	else:
		ctrl.size = target_size

## Same as fit_text_to_width but also checks font.get_height(size) against
## box.y - a single-line control's minimum size is clamped by BOTH the
## text's rendered width AND the font's line height, and for scripts not in
## font_stylish.ttf/font_info.ttf at all (CJK, rendered through Godot's
## system-fallback font) the line height can be the taller constraint, not
## the width. Checking width alone (as every caller here did until this was
## added) still let e.g. Chinese grow Options' title vertically even though
## the width fit fine.
static func _fit_font_to_box(text: String, font: Font, box: Vector2, max_font_size: int, floor_size: int) -> int:
	var size := max_font_size
	while size > floor_size:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var h := font.get_height(size)
		if w <= box.x and h <= box.y:
			return size
		size -= FONT_SHRINK_STEP
	return floor_size

## General entry point for ordinary buttons/labels (anything without
## flanking icon art to collide with): shrinks font to fit, down to
## ABSOLUTE_MIN_FONT_SIZE if it has to - never grows the control (a resized
## control can overlap whatever it was laid out next to; a smaller font
## can't). Caches the control's original design font size as metadata so
## repeated calls (e.g. on a language switch) always shrink from the true
## baseline instead of compounding shrinkage from a previous language.
##
## Checks height as well as width, not just fit_text_to_width's line width:
## CJK glyphs aren't in font_stylish.ttf/font_info.ttf at all, so they render
## through Godot's system-fallback font, which has a noticeably taller line
## height than either of those two fonts' own metric. A Control's minimum
## size is clamped to fit its current font's line height regardless of box
## height set in code (same class of auto-expand this codebase has already
## hit with Buttons/Labels/TextureRects), so on e.g. Chinese, Options' Back
## button was quietly growing taller than its authored 56px - fixed the same
## way as the width case, by shrinking the font until the taller metric
## fits too, rather than letting the control grow.
static func fit_button_text(ctrl: Control) -> void:
	var text: String = ctrl.text
	if text.is_empty():
		return
	var font: Font = ctrl.get_theme_font("font")
	if not ctrl.has_meta("base_font_size"):
		ctrl.set_meta("base_font_size", ctrl.get_theme_font_size("font_size"))
		# Cached alongside base_font_size, same reasoning: for controls whose
		# text is set repeatedly (language switches, not just once at
		# construction - Options.gd's _update_language_texts, StartMenu's
		# _refresh_slots), ctrl.size can no longer be trusted by the time
		# this runs on a later call. Setting .text already triggers Godot's
		# own minimum-size auto-expand (Control.size is clamped to
		# combined_minimum_size, which includes the CURRENT - not yet
		# shrunk - font's line height) BEFORE this function gets a chance to
		# shrink the font in response, so a second/third call could read an
		# already-inflated ctrl.size and wrongly conclude everything fits.
		# The first call (construction time, before repeated re-localization
		# has had a chance to inflate anything) is the only reliably correct
		# read of the true authored box size.
		ctrl.set_meta("base_size", ctrl.size)
	var base_font: int = ctrl.get_meta("base_font_size")
	var base_size: Vector2 = ctrl.get_meta("base_size")
	var available := base_size - Vector2.ONE * (2 * CONTENT_MARGIN)

	var size := _fit_font_to_box(text, font, available, base_font, ABSOLUTE_MIN_FONT_SIZE)
	ctrl.add_theme_font_size_override("font_size", size)
	_pin_size(ctrl, base_size)

## For a Button or Label whose text sits in the transparent gap between two
## icon halves baked into flanking artwork (MainMenu's 4 buttons, and
## Options' title which reuses button_option.png the same way), so the safe
## width is narrower than the control itself. Prefers shrinking to fit that
## gap; only if that fails even at MIN_FONT_SIZE does it fall back to
## rendering across the control's full width with a black outline so it
## stays legible sitting on top of the icon art either side.
static func fit_menu_button_text(btn: Control, safe_width: float) -> void:
	var text: String = btn.text
	if text.is_empty():
		return
	var font: Font = btn.get_theme_font("font")
	if not btn.has_meta("base_font_size"):
		btn.set_meta("base_font_size", btn.get_theme_font_size("font_size"))
		btn.set_meta("base_size", btn.size)  # see fit_button_text's docstring
	var base_font: int = btn.get_meta("base_font_size")
	var base_size: Vector2 = btn.get_meta("base_size")
	var available_height: float = base_size.y - 2 * CONTENT_MARGIN

	var fitted := _fit_font_to_box(text, font, Vector2(safe_width, available_height), base_font, MIN_FONT_SIZE)
	var fits_in_gap := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x <= safe_width \
		and font.get_height(fitted) <= available_height
	if fits_in_gap:
		btn.add_theme_font_size_override("font_size", fitted)
		btn.remove_theme_color_override("font_outline_color")
		btn.remove_theme_constant_override("outline_size")
	else:
		# Still doesn't fit the gap even at MIN_FONT_SIZE - fall back to
		# outline-on-icon, but MIN_FONT_SIZE's own line height might still
		# exceed the box for a tall fallback script, so shrink further if so
		# (same "never let the control itself grow" guarantee as everywhere else).
		var fallback_size := MIN_FONT_SIZE
		while fallback_size > ABSOLUTE_MIN_FONT_SIZE and font.get_height(fallback_size) > available_height:
			fallback_size -= FONT_SHRINK_STEP
		btn.add_theme_font_size_override("font_size", fallback_size)
		btn.add_theme_color_override("font_outline_color", Color.BLACK)
		btn.add_theme_constant_override("outline_size", 4)
	_pin_size(btn, base_size)

## For word-wrapped paragraph Labels (autowrap_mode WORD, multi-line box) -
## fit_text_to_width's single-line measurement doesn't apply here, since the
## text is meant to wrap across several lines; the real overflow risk is
## vertical (a longer translation wraps to more lines than the box is tall,
## and gets clipped since Help's pages set clip_contents = true). Shrinks
## font size until the wrapped paragraph's total height fits box_size.y at
## box_size.x wrap width. Same base-size caching as fit_button_text so
## repeated calls (language switches) stay correct.
static func fit_paragraph_to_box(ctrl: Control, box_size: Vector2, floor_size: int = MIN_FONT_SIZE) -> void:
	var text: String = ctrl.text
	if text.is_empty():
		return
	var font: Font = ctrl.get_theme_font("font")
	if not ctrl.has_meta("base_font_size"):
		ctrl.set_meta("base_font_size", ctrl.get_theme_font_size("font_size"))
	var base_size: int = ctrl.get_meta("base_font_size")

	var size := base_size
	while size > floor_size:
		var h := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, box_size.x, size).y
		if h <= box_size.y:
			break
		size -= FONT_SHRINK_STEP
	ctrl.add_theme_font_size_override("font_size", size)
	_pin_size(ctrl, box_size)
