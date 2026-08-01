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
