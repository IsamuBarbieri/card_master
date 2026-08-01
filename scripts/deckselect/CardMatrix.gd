class_name CardMatrix
extends RefCounted
## 1:1 port of DeckSelector/CardMatrix.cs - groups a flat card list into
## "same type" buckets (by definitionId) for DeckSelectorWheel.gd: the
## vertical wheel cycles between cardTypes, the horizontal wheel cycles
## within cardTypes[curIndexV].cards.

class SameTypeCards:
	var original_id: int
	var cards: Array = []  # Array[Card]

var card_types: Array = []  # Array[SameTypeCards]
var _is_favourite: bool = false

func init(src: Array, use_favourite: bool, use_all: bool) -> void:
	_is_favourite = use_favourite

	for src_card in src:
		if src_card.is_on_deck or (src_card.is_favourite != use_favourite and not use_all):
			continue
		add_card(src_card, -1, -1)

func add_card(src_card: Card, type_insert_at_index: int, card_insert_at_index: int) -> void:
	src_card.is_on_deck = false
	src_card.is_favourite = _is_favourite

	var found := false

	for sc in card_types:
		if sc.original_id == src_card.def_id:
			if card_insert_at_index < 0:
				sc.cards.append(src_card)
			else:
				sc.cards.insert(card_insert_at_index, src_card)
			found = true
			break

	if not found:
		var sc := SameTypeCards.new()
		sc.original_id = src_card.def_id
		sc.cards = [src_card]
		if type_insert_at_index < 0:
			card_types.append(sc)
		else:
			card_types.insert(type_insert_at_index, sc)

func remove_card_at_index(type_index: int, card_index: int) -> Dictionary:
	var card: Card = card_types[type_index].cards[card_index]
	card_types[type_index].cards.remove_at(card_index)

	var type_was_removed := false
	if card_types[type_index].cards.is_empty():
		card_types.remove_at(type_index)
		type_was_removed = true

	return {"card": card, "type_was_removed": type_was_removed}

func card_stats_at_index(type_index: int, card_index: int) -> Card:
	return card_types[type_index].cards[card_index]

func card_type_exists(cstats: Card) -> bool:
	for sc in card_types:
		if sc.original_id == cstats.def_id:
			return true
	return false

func card_type_index(cstats: Card) -> int:
	var counter := 0
	for sc in card_types:
		if sc.original_id == cstats.def_id:
			return counter
		counter += 1
	push_error("CardMatrix: could not find card's list")
	return -1
