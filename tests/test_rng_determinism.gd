extends Node
## BattleRng must produce byte-identical sequences from the same seed - the
## whole online lockstep design rests on it. If this test ever fails, every
## online match will end up voided for "cheating" that never happened.
## Run: godot --headless --quit-after 20 res://tests/test_rng_determinism.tscn

const DRAWS := 10000

func _draw(seed_value: int, count: int) -> Array:
	BattleRng.set_seed(seed_value)
	var out := []
	for i in count:
		out.append(BattleRng.next_u32())
	return out

func _ready() -> void:
	# Same seed, same sequence - the property the referee depends on.
	var a := _draw(123456789, DRAWS)
	var b := _draw(123456789, DRAWS)
	assert(a == b, "same seed produced different sequences")

	# Different seeds must not silently collapse onto the same stream.
	var c := _draw(987654321, DRAWS)
	assert(a != c, "different seeds produced identical sequences")

	# Every value stays inside 32 bits: GDScript ints are 64-bit, so a missing
	# mask in the shifts would let the state grow without the sequence ever
	# looking obviously wrong locally - and diverge on another build.
	for v in a:
		assert(v >= 0 and v <= 0xFFFFFFFF, "value escaped the 32-bit range: %d" % v)

	# A zero seed must not lock the generator on a constant stream (xorshift's
	# one fixed point) - the server is free to hand out any bigint.
	var zero := _draw(0, 64)
	var distinct := {}
	for v in zero:
		distinct[v] = true
	assert(distinct.size() > 32, "zero seed produced a degenerate sequence")

	# below()/range_incl() bounds.
	BattleRng.set_seed(42)
	for i in DRAWS:
		var below: int = BattleRng.below(4)
		assert(below >= 0 and below < 4, "below(4) out of range: %d" % below)
		var incl: int = BattleRng.range_incl(3, 7)
		assert(incl >= 3 and incl <= 7, "range_incl(3,7) out of range: %d" % incl)
	assert(BattleRng.below(0) == 0, "below(0) must be 0, not a crash or a negative")
	assert(BattleRng.range_incl(5, 5) == 5, "a one-value range must return that value")

	# Rough uniformity - not a statistics exam, just enough to catch a stuck
	# low bit or a broken modulo.
	BattleRng.set_seed(7)
	var buckets := [0, 0, 0, 0]
	for i in DRAWS:
		buckets[BattleRng.below(4)] += 1
	for n in buckets:
		assert(absf(float(n) / DRAWS - 0.25) < 0.02, "below(4) looks skewed: %s" % str(buckets))

	print("OK - BattleRng is deterministic, bounded and unbiased")
	get_tree().quit()
