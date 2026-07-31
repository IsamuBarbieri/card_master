class_name GsBattle
extends RefCounted
## Ported from Scenes/Battle/gsBattle.cs. resolve_battle() is the pure
## combat-resolution math (gsBattle_Set's value calculation); the animated
## rumble/countdown/blink/capture sequence lives in BattleScene.gd's
## gsBattle_* methods since it needs scene-tree access for Tweens.

# Resolves a fight between the attacker (card0, the just-placed/attacking
# card) and the defender (card1). Returns a dictionary with the values used
# and the winner (null on draw).
static func resolve_battle(card0: Card, card1: Card) -> Dictionary:
	var attack_stat := 0
	var defense_stat := 0
	# Index into stat_text() (0=attack,1=type,2=pdef,3=mdef) of the stat that
	# gets compared - used to pick which character blinks during the fight.
	var letter0 := 0
	var letter1 := 0

	match card0.attack_type:
		Card.AttackType.PHYSICAL:
			attack_stat = card0.attack_power
			defense_stat = card1.physical_defense
			letter0 = 0; letter1 = 2
		Card.AttackType.MAGICAL:
			attack_stat = card0.attack_power
			defense_stat = card1.magical_defense
			letter0 = 0; letter1 = 3
		Card.AttackType.FLEXIBLE:
			attack_stat = card0.attack_power
			letter0 = 0
			if card1.magical_defense < card1.physical_defense:
				defense_stat = card1.magical_defense; letter1 = 3
			else:
				defense_stat = card1.physical_defense; letter1 = 2
		Card.AttackType.ASSAULT:
			if card0.attack_power >= card0.physical_defense and card0.attack_power >= card0.magical_defense:
				attack_stat = card0.attack_power; letter0 = 0
			elif card0.physical_defense >= card0.magical_defense:
				attack_stat = card0.physical_defense; letter0 = 2
			else:
				attack_stat = card0.magical_defense; letter0 = 3

			if card1.attack_power <= card1.physical_defense and card1.attack_power <= card1.magical_defense:
				defense_stat = card1.attack_power; letter1 = 0
			elif card1.physical_defense <= card1.magical_defense:
				defense_stat = card1.physical_defense; letter1 = 2
			else:
				defense_stat = card1.magical_defense; letter1 = 3

	var attack_rand := randi_range(0, attack_stat) if attack_stat > 0 else 0
	var defense_rand := randi_range(0, defense_stat) if defense_stat > 0 else 0
	var attack_value := attack_stat - attack_rand
	var defense_value := defense_stat - defense_rand

	var winner: Card = null
	var loser: Card = null
	if attack_value > defense_value:
		winner = card0
		loser = card1
	elif defense_value > attack_value:
		winner = card1
		loser = card0

	return {
		"attack_stat": attack_stat,
		"defense_stat": defense_stat,
		"attack_value": attack_value,
		"defense_value": defense_value,
		"winner": winner,
		"loser": loser,
		"letter0": letter0,
		"letter1": letter1,
	}
