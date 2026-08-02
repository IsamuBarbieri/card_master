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

## Widens/heightens a Control to at least min_size, growing outward from its
## current center in both directions rather than from a fixed corner.
static func grow_control_symmetric(ctrl: Control, min_size: Vector2) -> void:
	var old_center := ctrl.position + ctrl.size / 2.0
	var new_size := Vector2(maxf(ctrl.size.x, min_size.x), maxf(ctrl.size.y, min_size.y))
	ctrl.size = new_size
	ctrl.position = old_center - new_size / 2.0

## General entry point for ordinary buttons/labels (anything without
## flanking icon art to collide with): shrink font to fit first; if even
## MIN_FONT_SIZE doesn't fit, grow the control symmetrically instead. Caches
## the control's original design font size as metadata so repeated calls
## (e.g. on a language switch) always shrink from the true baseline instead
## of compounding shrinkage from whatever a previous language left behind.
static func fit_button_text(ctrl: Control) -> void:
	var text: String = ctrl.text
	if text.is_empty():
		return
	var font: Font = ctrl.get_theme_font("font")
	if not ctrl.has_meta("base_font_size"):
		ctrl.set_meta("base_font_size", ctrl.get_theme_font_size("font_size"))
	var base_size: int = ctrl.get_meta("base_font_size")
	var available_width: float = ctrl.size.x - 2 * CONTENT_MARGIN

	var fitted := fit_text_to_width(text, font, available_width, base_size)
	ctrl.add_theme_font_size_override("font_size", fitted)

	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x
	if w > available_width:
		grow_control_symmetric(ctrl, Vector2(w + 2 * CONTENT_MARGIN, ctrl.size.y))

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
	var base_size: int = btn.get_meta("base_font_size")

	var fitted := fit_text_to_width(text, font, safe_width, base_size)
	var fits_in_gap := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x <= safe_width
	if fits_in_gap:
		btn.add_theme_font_size_override("font_size", fitted)
		btn.remove_theme_color_override("font_outline_color")
		btn.remove_theme_constant_override("outline_size")
		return

	btn.add_theme_font_size_override("font_size", MIN_FONT_SIZE)
	btn.add_theme_color_override("font_outline_color", Color.BLACK)
	btn.add_theme_constant_override("outline_size", 4)
