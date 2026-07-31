class_name Board
extends RefCounted
## 4x4 board of card slots + capture/battle adjacency rules (ported from
## the original Board.cs, stripped of pixel-rect/rendering concerns).

const NUM_ROWS := 4
const NUM_COLS := 4

# Offsets in arrow order: N, NE, E, SE, S, SW, W, NW
const SLOT_OFFSETS := [
	[-1, 0], [-1, 1], [0, 1], [1, 1],
	[1, 0], [1, -1], [0, -1], [-1, -1],
]

var slots: Array = []    # [row][col] -> Card or null
var blocked: Array = []  # [row][col] -> bool

func _init() -> void:
	reset()

func reset() -> void:
	slots = []
	blocked = []
	for r in NUM_ROWS:
		var row := []
		var brow := []
		for c in NUM_COLS:
			row.append(null)
			brow.append(false)
		slots.append(row)
		blocked.append(brow)

# Randomly blocks up to `max_blocks` empty cells (ported from
# BattleScene.generateBlocks - the original rolls 0..(16-10) blocks since
# 10 cells are needed for the two 5-card hands).
func place_random_blocks(max_blocks: int) -> void:
	var count := randi() % (max_blocks + 1)
	var placed := 0
	while placed < count:
		var row := randi() % NUM_ROWS
		var col := randi() % NUM_COLS
		if slots[row][col] == null and not blocked[row][col]:
			blocked[row][col] = true
			placed += 1

func is_valid(row: int, col: int) -> bool:
	return row >= 0 and row < NUM_ROWS and col >= 0 and col < NUM_COLS

func has_card(row: int, col: int) -> bool:
	return is_valid(row, col) and slots[row][col] != null

func is_blocked(row: int, col: int) -> bool:
	return is_valid(row, col) and blocked[row][col]

func is_playable(row: int, col: int) -> bool:
	return is_valid(row, col) and slots[row][col] == null and not blocked[row][col]

func place_card(card: Card, row: int, col: int) -> void:
	slots[row][col] = card
	card.row = row
	card.col = col

func capture(card: Card, new_owner: int) -> void:
	card.owner = new_owner

func arrow_opposite_index(index: int) -> int:
	return (index + 4) % 8

# Adjacent enemy cards that CAN fight back (their opposite-facing arrow is up).
func get_adjacent_battle_cards(card: Card) -> Array:
	var result := []
	for i in 8:
		if not card.arrows[i]:
			continue
		var row: int = card.row + SLOT_OFFSETS[i][0]
		var col: int = card.col + SLOT_OFFSETS[i][1]
		if not has_card(row, col):
			continue
		var other: Card = slots[row][col]
		if other.owner == card.owner:
			continue
		if other.arrows[arrow_opposite_index(i)]:
			result.append(other)
	return result

# Adjacent enemy cards that CANNOT fight back -> captured instantly.
func get_capturable_cards(card: Card) -> Array:
	var result := []
	for i in 8:
		if not card.arrows[i]:
			continue
		var row: int = card.row + SLOT_OFFSETS[i][0]
		var col: int = card.col + SLOT_OFFSETS[i][1]
		if not has_card(row, col):
			continue
		var other: Card = slots[row][col]
		if other.owner == card.owner:
			continue
		if not other.arrows[arrow_opposite_index(i)]:
			result.append(other)
	return result

# Adjacent cards owned by the same owner as a just-defeated card -> combo capture.
func get_combo_cards(defeated_card: Card) -> Array:
	var result := []
	for i in 8:
		if not defeated_card.arrows[i]:
			continue
		var row: int = defeated_card.row + SLOT_OFFSETS[i][0]
		var col: int = defeated_card.col + SLOT_OFFSETS[i][1]
		if not has_card(row, col):
			continue
		var other: Card = slots[row][col]
		if other.owner != defeated_card.owner:
			continue
		result.append(other)
	return result

func count_cards(owner: int) -> int:
	var count := 0
	for r in NUM_ROWS:
		for c in NUM_COLS:
			var card: Card = slots[r][c]
			if card != null and card.owner == owner:
				count += 1
	return count

func empty_slots() -> Array:
	var result := []
	for r in NUM_ROWS:
		for c in NUM_COLS:
			if is_playable(r, c):
				result.append([r, c])
	return result
