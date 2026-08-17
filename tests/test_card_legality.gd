extends Node
## Every card the game can put in a collection must satisfy the rules the
## online deck check enforces (server/schema.sql, mp_validate_deck), or a
## player ends up holding a card the server calls tampered and their whole
## deck is refused - with nothing they can do about it.
##
## This caught a real one: the rage-quit reroll rolled 3-12 into any species,
## and Slime caps at 10 attack and 8 magic defence, so beating the Rage Quit
## opponent to win back a Slime you had lost to it produced a Slime stronger
## than the game can otherwise make, and locked that save out of online play.
## Run: godot --headless --quit-after 400 res://tests/test_card_legality.tscn

const SAMPLES_PER_SPECIES := 200

func _why_illegal(card: Card) -> Array:
	var def: CardManager.CardDef = CardManager.defs[card.def_id]
	var why := []
	if card.attack_power > def.max_attack_power:
		why.append("attack %d over the %d cap" % [card.attack_power, def.max_attack_power])
	if card.physical_defense > def.max_physical_defense:
		why.append("p.def %d over the %d cap" % [card.physical_defense, def.max_physical_defense])
	if card.magical_defense > def.max_magical_defense:
		why.append("m.def %d over the %d cap" % [card.magical_defense, def.max_magical_defense])
	if card.attack_power < 0 or card.physical_defense < 0 or card.magical_defense < 0:
		why.append("a negative stat")
	# Either the species' own type, or a level-up along P/M -> X -> A.
	if card.attack_type != def.attack_type \
			and (card.attack_type < Card.AttackType.FLEXIBLE or card.attack_type > def.max_attack_type):
		why.append("attack type %d, which this species can never have" % card.attack_type)
	var mask := MatchState.arrow_mask(card)
	if mask < 1 or mask > 255:
		why.append("an arrow mask of %d" % mask)
	return why

func _check(card: Card, how: String) -> void:
	var why := _why_illegal(card)
	assert(why.is_empty(), "%s produced a %s with %s - online would refuse the deck holding it" % [
		how, CardManager.defs[card.def_id].name, ", ".join(why)])

func _ready() -> void:
	var player := Player.new("Legality", 0, AIManager.count())

	for def_id in CardManager.defs.size():
		for i in SAMPLES_PER_SPECIES:
			# 1. freshly generated, as the shop and the AI pools make them
			var fresh := CardManager.generate_card(def_id)
			_check(fresh, "card generation")

			# 2. after the rage-quit reroll, which rewrites all three stats
			var rerolled := CardManager.generate_card(def_id)
			var before := player.cards.size()
			player.add_captured_rage_quit_card(rerolled)
			assert(player.cards.size() == before + 1, "the rage-quit capture did not add the card")
			_check(rerolled, "the rage-quit reroll")

			# 3. fully levelled up, the other end of a card's life
			var maxed := CardManager.generate_card(def_id)
			var def: CardManager.CardDef = CardManager.defs[def_id]
			maxed.attack_power = def.max_attack_power
			maxed.physical_defense = def.max_physical_defense
			maxed.magical_defense = def.max_magical_defense
			maxed.attack_type = def.max_attack_type
			_check(maxed, "a fully levelled card")

	# The reroll must still bite: capping it at the species ceiling should not
	# have turned it into a way of IMPROVING a strong card.
	var dragon := CardManager.generate_card(18)
	var was := dragon.attack_power
	player.add_captured_rage_quit_card(dragon)
	assert(dragon.attack_power <= Player.RAGE_QUIT_MAX and dragon.attack_power < was,
		"the rage-quit reroll no longer punishes a strong card (%d -> %d)" % [was, dragon.attack_power])

	print("OK - every card the game can make passes the online deck rules")
	get_tree().quit()
