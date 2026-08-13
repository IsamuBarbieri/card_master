extends Node
## Confirms card_price()'s rescaled constant (15.4, was 10.0) actually
## restores the pre-rewrite average price level instead of just being a
## plausible-looking number - samples real generated cards (real stat rolls,
## real arrow counts) across every species and checks the average lands
## close to what the OLD formula (10.0, ~4.5 avg arrows) would have given
## for the SAME stat rolls, isolating the arrow-rescale from stat variance.
## Run: godot --headless --quit-after 20 res://tests/test_card_price_scale.tscn

const SAMPLES_PER_SPECIES := 500

func _ready() -> void:
	var old_total := 0.0
	var new_total := 0.0
	var n := 0

	for species_id in CardManager.defs.size():
		for i in SAMPLES_PER_SPECIES:
			var card: Card = CardManager.generate_card(species_id)
			var new_price := CardManager.card_price(card)

			# Recompute what the OLD formula (10.0 * (2+f)) would have
			# priced this exact card at, arrow count aside - same stats,
			# same type, just the old constant and the old ~4.5-average
			# arrow assumption instead of this card's own (now ~2.2-avg)
			# arrow count, so the comparison isolates the rescale.
			var t := 1.0
			if card.attack_type == Card.AttackType.FLEXIBLE:
				t = 1.1
			elif card.attack_type == Card.AttackType.ASSAULT:
				t = 1.3
			var val := float(card.attack_power + card.physical_defense + card.magical_defense) / 3.0
			var old_price := 10.0 * (2.0 + 4.5) * pow(val, t)

			old_total += old_price
			new_total += new_price
			n += 1

	var ratio := new_total / old_total
	print("avg new/old price ratio across %d samples: %.4f (target 1.0)" % [n, ratio])
	assert(absf(ratio - 1.0) < 0.05, "rescaled price formula drifted >5%% from the pre-rewrite average: ratio=%.4f" % ratio)

	print("OK - card price rescale checks passed")
	get_tree().quit()
