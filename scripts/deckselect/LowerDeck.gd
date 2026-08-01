class_name LowerDeck
extends RefCounted
## 1:1 port of DeckSelectScene.LowerDeck (Scenes/DeckSelect/LowerDeck.cs) -
## the 5 chosen-deck slots at the bottom of the screen.
## Deviation: no baked-texture SetupDragImage - the drag ghost in
## DeckSelect.gd builds its own CardView straight from the Card returned by
## remove_card(), same simplification noted in DeckSelectorWheel.gd.

var cards: Array = [null, null, null, null, null]
var ui_placeholders: Array = []  # Array[Control], 5
var ui_cards: Array = []         # Array[CardView], 5

func init(placeholders: Array) -> void:
	ui_placeholders = placeholders
	for i in 5:
		var cv := CardView.new()
		cv.visible = false
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui_placeholders[i].add_child(cv)
		ui_cards.append(cv)

## Returns {index, was_empty}; index -1 if no placeholder is under the cursor.
func get_card_index_under_cursor(x: int, y: int) -> Dictionary:
	for i in 5:
		if _hit_test(ui_placeholders[i], x, y):
			return {"index": i, "was_empty": cards[i] == null}
	return {"index": -1, "was_empty": false}

## -1 if no placeholder under the cursor holds a card.
func get_valid_card_index_under_cursor(x: int, y: int) -> int:
	for i in 5:
		if _hit_test(ui_placeholders[i], x, y):
			if cards[i] == null:
				continue
			return i
	return -1

func get_unused_index() -> int:
	for i in 5:
		if cards[i] == null:
			return i
	return -1

func add_card(index: int, card: Card) -> void:
	cards[index] = card
	card.is_on_deck = true
	ui_cards[index].visible = true
	ui_cards[index].setup(card, true, true)

func remove_card(index: int) -> Card:
	var card: Card = cards[index]
	card.is_on_deck = false
	cards[index] = null
	ui_cards[index].visible = false
	return card

func swap_cards(i0: int, i1: int) -> void:
	var tmp: Card = cards[i0]
	cards[i0] = cards[i1]
	cards[i1] = tmp

	ui_cards[i0].visible = cards[i0] != null
	if cards[i0] != null:
		ui_cards[i0].setup(cards[i0], true, true)

	ui_cards[i1].visible = cards[i1] != null
	if cards[i1] != null:
		ui_cards[i1].setup(cards[i1], true, true)

func card_stats(index: int) -> Card:
	return cards[index]

func card_x(index: int) -> float:
	return ui_placeholders[index].global_position.x

func card_y(index: int) -> float:
	return ui_placeholders[index].global_position.y

func card_width(index: int) -> float:
	return ui_placeholders[index].size.x

func card_height(index: int) -> float:
	return ui_placeholders[index].size.y

func _hit_test(placeholder: Control, x: int, y: int) -> bool:
	return Rect2(placeholder.global_position, placeholder.size).has_point(Vector2(x, y))
