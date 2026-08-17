extends Node
## CardManager.deck_power drives online matchmaking. It must weigh the three
## numeric stats and nothing else - arrows are explicitly excluded, so two
## decks with identical stats but wildly different arrow counts have to land
## in the same matchmaking bracket.
## Run: godot --headless --quit-after 20 res://tests/test_deck_power.tscn

func _card(atk: int, pdef: int, mdef: int, arrow_count: int, type: int = Card.AttackType.PHYSICAL) -> Card:
	var c := Card.new()
	c.attack_power = atk
	c.physical_defense = pdef
	c.magical_defense = mdef
	c.attack_type = type
	for i in arrow_count:
		c.arrows[i] = true
	return c

func _ready() -> void:
	var deck_a := [
		_card(100, 50, 30, 1),
		_card(80, 60, 40, 1),
		_card(20, 20, 20, 1),
		_card(200, 10, 10, 1),
		_card(5, 250, 5, 1),
	]
	# Same stats, maximum arrows, premium attack types.
	var deck_b := [
		_card(100, 50, 30, 8, Card.AttackType.ASSAULT),
		_card(80, 60, 40, 8, Card.AttackType.ASSAULT),
		_card(20, 20, 20, 8, Card.AttackType.FLEXIBLE),
		_card(200, 10, 10, 8, Card.AttackType.FLEXIBLE),
		_card(5, 250, 5, 8, Card.AttackType.ASSAULT),
	]

	var expected := 100 + 50 + 30 + 80 + 60 + 40 + 20 + 20 + 20 + 200 + 10 + 10 + 5 + 250 + 5
	assert(CardManager.deck_power(deck_a) == expected,
		"deck_power should be the plain stat sum, got %d expected %d" % [CardManager.deck_power(deck_a), expected])
	assert(CardManager.deck_power(deck_a) == CardManager.deck_power(deck_b),
		"arrows or attack type leaked into deck_power")

	# card_price DOES weigh arrows/type - the contrast is the reason
	# deck_power exists as a separate function instead of reusing it.
	var price_a := 0
	var price_b := 0
	for c in deck_a:
		price_a += CardManager.card_price(c)
	for c in deck_b:
		price_b += CardManager.card_price(c)
	assert(price_b > price_a, "sanity check failed: card_price should still favour arrows/type")

	# A stronger deck must actually outweigh a weaker one, and nulls (empty
	# deck slots) must not crash the matchmaking path.
	var weak := [_card(1, 1, 1, 1), _card(1, 1, 1, 1), null, null, null]
	assert(CardManager.deck_power(weak) == 6, "nulls must be skipped, not counted")
	assert(CardManager.deck_power(weak) < CardManager.deck_power(deck_a), "stat sum is not ordering decks")

	print("OK - deck_power sums stats only, ignoring arrows and attack type")
	get_tree().quit()
