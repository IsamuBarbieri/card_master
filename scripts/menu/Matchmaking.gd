extends Control
## Waiting room between DeckSelect and an online BattleScene.
##
## Uploads the chosen deck (which is also where the server validates it and
## computes the matchmaking weight), then polls until an opponent of similar
## deck power turns up. Polling rather than a realtime socket: the wait is
## measured in seconds and a poll is a tenth of the code.
##
## Static layout (background, label positions/colors, cancel button
## position) lives in Matchmaking.tscn. All text stays script-assigned - it's
## either StringTable-sourced or live search/timer state.

const ASSETS := "res://assets/"
const POLL_SECONDS := 1.5
## Three dots cycling, at the same unhurried pace as the rest of the UI.
const DOT_SECONDS := 0.4

@onready var status_label: Label = $StatusLabel
@onready var power_label: Label = $PowerLabel
@onready var elapsed_label: Label = $ElapsedLabel
@onready var cancel: FixedSizeButton = $CancelButton

var deck: Array = []
var searching := false
var _elapsed := 0.0
var _dot_timer := 0.0
var _dots := 0

func _ready() -> void:
	UIButtonStyle.apply(cancel)
	cancel.text = StringTable.get_string(StringTable.ID_CANCEL)
	cancel.add_theme_color_override("font_shadow_color", UIConstants.COLOR_SHADOW_DIM)
	cancel.add_theme_constant_override("shadow_offset_x", 1)
	cancel.add_theme_constant_override("shadow_offset_y", 1)
	cancel.pressed.connect(_on_cancel_pressed)
	UIButtonStyle.fit_button_text(cancel)

	# Cancel sits where Back sits everywhere else and answers to B the same
	# way, through nav.cancelled rather than an _unhandled_input handler that
	# FocusNav would swallow first.
	var nav := FocusNav.new()
	add_child(nav)
	ControllerUI.hide_in_gamepad(cancel)
	ControllerUI.hide_hand()
	nav.cancelled.connect(_on_cancel_pressed)
	add_child(ControllerUI.make_button_hint(&"B", StringTable.get_string(StringTable.ID_CANCEL),
		Vector2(cancel.position.x, ControllerUI.PROMPT_BAR_Y),
		Vector2(cancel.size.x, ControllerUI.HINT_ROW_HEIGHT)))

	deck = _current_deck()
	power_label.text = "%s: %d" % [
		StringTable.get_string(StringTable.ID_DECK_POWER),
		CardManager.deck_power(deck)]
	status_label.text = StringTable.get_string(StringTable.ID_SEARCHING_OPPONENT)

	await _search()

## The five cards DeckSelect flagged, in the same way BattleScene reads them
## (BattleScene._get_player_deck) - is_on_deck on the persistent collection.
func _current_deck() -> Array:
	var out: Array = []
	for card in Game.player.cards:
		if card.is_on_deck:
			out.append(card)
	return out

func _search() -> void:
	if deck.size() != 5:
		_bail("deck must hold exactly 5 cards")
		return

	searching = true
	var res := await Net.call_rpc("mp_enqueue", {"p_deck": Net.deck_payload(deck)})
	if not is_inside_tree() or not searching:
		return
	if not res["ok"]:
		_bail(res["error"])
		return

	if res["data"]["status"] == "matched":
		_start_match(res["data"]["match"])
		return

	# Queued: wait for someone to pair with us. mp_current_match is also how a
	# client recovers a match created by the OTHER player's enqueue, which is
	# the normal case for whoever waited.
	while searching and is_inside_tree():
		await get_tree().create_timer(POLL_SECONDS).timeout
		if not searching or not is_inside_tree():
			return
		var poll := await Net.call_rpc("mp_current_match")
		if not is_inside_tree() or not searching:
			return
		if not poll["ok"]:
			_bail(poll["error"])
			return
		if poll["data"]["status"] == "matched":
			_start_match(poll["data"]["match"])
			return

## Seconds between "opponent found" and the board opening. The screen would
## otherwise cut straight from a spinner to a live match with a clock already
## running, giving the player no moment to register that a game had started.
const START_COUNTDOWN := 3

func _start_match(m: Dictionary) -> void:
	searching = false
	# JSON numbers arrive as floats; every downstream consumer (BattleRng's
	# seed, the turn indices) needs real ints.
	var my_slot := 0 if str(m["p0"]) == Net.user_id else 1
	var opponent_deck: Array = m["deck1"] if my_slot == 0 else m["deck0"]

	Game.online_mode = true
	Game.online_match = {
		"id": str(m["id"]),
		"seed": int(m["seed"]),
		"my_slot": my_slot,
		# Rebased into the local frame: BattleScene always calls the local
		# player 0, so "who starts" has to be answered from this client's side.
		"first_player": 0 if int(m["first_player"]) == my_slot else 1,
		"opponent_deck": Net.deck_from_payload(opponent_deck),
		"opponent_name": str(m.get("p1_name", "") if my_slot == 0 else m.get("p0_name", "")),
	}

	Game.player.match_started = true
	SaveSystem.save_player(Game.player)

	# The two clients are matched a moment apart (one of them found out by
	# polling), so their countdowns aren't in step - which doesn't matter:
	# whoever arrives first simply waits for a move, as it would anyway.
	elapsed_label.text = ""
	power_label.text = Game.online_match.get("opponent_name", "")
	for remaining in range(START_COUNTDOWN, 0, -1):
		status_label.text = "%s %d" % [StringTable.get_string(StringTable.ID_MATCH_STARTS_IN), remaining]
		await get_tree().create_timer(1.0).timeout
		if not is_inside_tree():
			return
	get_tree().change_scene_to_file("res://scenes/battle/BattleScene.tscn")

func _bail(message: String) -> void:
	searching = false
	status_label.text = "%s: %s" % [StringTable.get_string(StringTable.ID_ONLINE_ERROR), message]

func _process(delta: float) -> void:
	if not searching:
		return
	_elapsed += delta
	elapsed_label.text = "%d s" % int(_elapsed)
	_dot_timer += delta
	if _dot_timer >= DOT_SECONDS:
		_dot_timer = 0.0
		_dots = (_dots + 1) % 4
		status_label.text = StringTable.get_string(StringTable.ID_SEARCHING_OPPONENT).trim_suffix("...") \
			+ ".".repeat(_dots)

func _on_cancel_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_back_sound.wav")
	searching = false
	await Net.call_rpc("mp_dequeue")
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/deckselect/DeckSelect.tscn")
