class_name Ease
extends RefCounted
## 1:1 port of Ease.cs. Godot's Tween has its own easing, but keeping the
## original functions lets animation code match the PSVita timings/curves
## exactly where it matters (battle number countdown, etc).

enum Mode { LINEAR, IN_QUADRATIC, IN_CUBIC, OUT_QUADRATIC, OUT_CUBIC, IN_OUT_QUADRATIC, IN_OUT_CUBIC }

static func linear(start: float, end: float, t: float) -> float:
	return start + (end - start) * t

static func in_quadratic(start: float, end: float, t: float) -> float:
	return start + (end - start) * (t * t)

static func in_cubic(start: float, end: float, t: float) -> float:
	return start + (end - start) * (t * t * t)

static func out_quadratic(start: float, end: float, t: float) -> float:
	return start - (end - start) * (t * (t - 2.0))

static func out_cubic(start: float, end: float, t: float) -> float:
	var tt := t - 1.0
	return start + (end - start) * (tt * tt * tt + 1.0)

static func in_out_quadratic(start: float, end: float, t: float) -> float:
	var tt := t * 2.0
	if tt < 1.0:
		return start + ((end - start) / 2.0) * (tt * tt)
	tt -= 1.0
	return start - ((end - start) / 2.0) * (tt * (tt - 2.0) - 1.0)

static func in_out_cubic(start: float, end: float, t: float) -> float:
	var tt := t * 2.0
	if tt < 1.0:
		return start + ((end - start) / 2.0) * (tt * tt * tt)
	tt -= 2.0
	return start - ((end - start) / 2.0) * (tt * tt * tt + 2.0)

static func apply(mode: Mode, start: float, end: float, t: float) -> float:
	match mode:
		Mode.LINEAR: return linear(start, end, t)
		Mode.IN_QUADRATIC: return in_quadratic(start, end, t)
		Mode.IN_CUBIC: return in_cubic(start, end, t)
		Mode.OUT_QUADRATIC: return out_quadratic(start, end, t)
		Mode.OUT_CUBIC: return out_cubic(start, end, t)
		Mode.IN_OUT_QUADRATIC: return in_out_quadratic(start, end, t)
		Mode.IN_OUT_CUBIC: return in_out_cubic(start, end, t)
	return linear(start, end, t)

# Maps to the closest Godot Tween.TransitionType/EaseType pair, so Tweens can
# use the engine's own interpolation for movement (cheaper, same shape) while
# `apply()` above is reserved for per-frame value ramps like the battle
# number countdown, which the original drives manually every frame.
static func tween_params(mode: Mode) -> Array:
	match mode:
		Mode.LINEAR: return [Tween.TRANS_LINEAR, Tween.EASE_IN_OUT]
		Mode.IN_QUADRATIC: return [Tween.TRANS_QUAD, Tween.EASE_IN]
		Mode.IN_CUBIC: return [Tween.TRANS_CUBIC, Tween.EASE_IN]
		Mode.OUT_QUADRATIC: return [Tween.TRANS_QUAD, Tween.EASE_OUT]
		Mode.OUT_CUBIC: return [Tween.TRANS_CUBIC, Tween.EASE_OUT]
		Mode.IN_OUT_QUADRATIC: return [Tween.TRANS_QUAD, Tween.EASE_IN_OUT]
		Mode.IN_OUT_CUBIC: return [Tween.TRANS_CUBIC, Tween.EASE_IN_OUT]
	return [Tween.TRANS_LINEAR, Tween.EASE_IN_OUT]
