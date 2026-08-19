class_name BattleRng
extends RefCounted
## Seeded xorshift32 shared by every random decision a match outcome depends
## on (block layout, coin toss, combat rolls). Online matches are lockstep:
## both clients simulate the same battle from a seed the server hands out and
## compare state hashes each turn, so those rolls have to produce the exact
## same sequence on both machines. Godot's global randi()/randi_range() can't
## promise that across engine versions or architectures - this can, because
## the algorithm is right here and it's plain 32-bit integer math.
##
## Static state rather than an instance threaded through Board/GsBattle: only
## one match runs at a time, and passing an rng object down through every
## call site would be a much bigger diff for no gain. BattleScene seeds it
## once per match (from randi() offline, from the server seed online), so
## offline play stays exactly as random as it was.

const _MASK := 0xFFFFFFFF

static var _state: int = 0x9E3779B9

static func set_seed(seed_value: int) -> void:
	_state = seed_value & _MASK
	# xorshift is stuck forever on a zero state, so a zero seed (a plausible
	# thing for a server to hand out) gets swapped for the golden-ratio
	# constant instead of producing a constant stream.
	if _state == 0:
		_state = 0x9E3779B9
	# xorshift32's very first output after a fresh seed is weakly mixed -
	# confirmed empirically: with shifts (13,17,5), the new low bit is just
	# old_bit0 XOR old_bit17, so a caller drawing immediately after set_seed
	# (below(2) for a coin toss, say) gets a result that leans hard on two
	# bits of the raw seed instead of the whole state. Every real call site
	# in this game happens to draw several times first (board.place_random_
	# blocks before the coin toss), which already dilutes this - but nothing
	# should have to know that to get an unbiased first draw. Three warm-up
	# rounds here, discarded, mix the state before anything else can see it;
	# deterministic and seed-only; the online lockstep property (same seed,
	# same sequence on both clients) is unaffected.
	for i in 3:
		next_u32()

## Raw next value, 0 .. 2^32-1. Masked back to 32 bits after every shift
## because GDScript ints are 64-bit - without the mask the left shifts would
## keep growing and the sequence would stop matching a real xorshift32.
static func next_u32() -> int:
	var x := _state
	x ^= (x << 13) & _MASK
	x ^= x >> 17
	x ^= (x << 5) & _MASK
	_state = x
	return x

## 0 .. n-1 (0 if n <= 0). Plain modulo: the bias for the tiny ranges this
## game asks for (board cells, stat rolls up to 255) is far below anything a
## player could notice or exploit.
static func below(n: int) -> int:
	if n <= 0:
		return 0
	return next_u32() % n

## Inclusive range, matching randi_range's contract so call sites read the
## same as the code they replaced.
static func range_incl(from: int, to: int) -> int:
	if to <= from:
		return from
	return from + below(to - from + 1)
