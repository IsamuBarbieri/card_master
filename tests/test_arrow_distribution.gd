extends Node
## Statistical check on CardManager.generate_arrows: the decaying-chain
## algorithm should produce a monotonically decreasing arrow-count
## distribution (1 arrow most common, 8 rarest) averaging ~2.2 arrows -
## see the balance discussion this replaced (average was ~4.5 under the old
## independent-50/50-per-direction system).
## Run: godot --headless --quit-after 20 res://tests/test_arrow_distribution.tscn

const SAMPLES := 200000
const EXPECTED_AVG := 2.2227  # BASE=0.65, DECAY=0.82, computed analytically
const TOLERANCE := 0.05  # generous - this is a random sample, not exact

func _ready() -> void:
	var counts := {}
	for k in range(1, 9):
		counts[k] = 0

	var total := 0
	var first_dir_counts := {}
	for i in range(8):
		first_dir_counts[i] = 0
	for i in SAMPLES:
		var arrows: Array = CardManager.generate_arrows()
		var n := 0
		for a in arrows:
			if a:
				n += 1
		assert(n >= 1, "every card must have at least 1 arrow")
		assert(n <= 8, "arrow count can't exceed 8")
		counts[n] += 1
		total += n
		for dir in range(8):
			if arrows[dir]:
				first_dir_counts[dir] += 1

	var avg := float(total) / SAMPLES
	print("sampled average arrows: ", avg, " (expected ~", EXPECTED_AVG, ")")
	assert(absf(avg - EXPECTED_AVG) < TOLERANCE, "sampled average %.4f too far from expected %.4f" % [avg, EXPECTED_AVG])

	# Monotonically decreasing: P(k) >= P(k+1) for every k. Checked as raw
	# counts (same sample size per bucket) rather than converting to
	# probabilities first.
	for k in range(1, 8):
		assert(counts[k] >= counts[k + 1], "not monotonic: count(%d)=%d < count(%d)=%d" % [k, counts[k], k + 1, counts[k + 1]])

	var dist_str := ""
	for k in range(1, 9):
		dist_str += "%d:%.2f%% " % [k, 100.0 * counts[k] / SAMPLES]
	print("distribution: ", dist_str)

	# The guaranteed arrow's direction must NOT be fixed/predictable - every
	# one of the 8 directions should appear in roughly the same share of
	# cards (expected each direction present in ~1 - (1 - 1/8)*(the rest of
	# the count distribution)... simplest robust check: no direction should
	# be wildly over/under-represented relative to the others).
	var dir_min: int = SAMPLES
	var dir_max: int = 0
	for dir in range(8):
		dir_min = mini(dir_min, first_dir_counts[dir])
		dir_max = maxi(dir_max, first_dir_counts[dir])
	print("per-direction presence range: ", dir_min, " - ", dir_max, " (of ", SAMPLES, " samples)")
	assert(float(dir_max - dir_min) / SAMPLES < 0.02, "a direction looks favored/fixed instead of random: min=%d max=%d" % [dir_min, dir_max])

	print("OK - arrow distribution checks passed")
	get_tree().quit()
