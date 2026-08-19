extends Control
## Online lobby (960x544 design canvas). Not in the reference - this whole
## screen is new, reached from MainMenu's central circle.
##
## Signs the current save slot into Supabase on entry (anonymous, one account
## per slot - see Net.gd) and shows the player's standing, then hands off to
## the existing DeckSelect screen in online mode.
##
## Chrome deliberately copies Opponents.gd rather than inventing its own: same
## background, same black stylish title at the same y, same Back button at
## (42,463) hidden in gamepad mode behind a B hint. A menu that looks like the
## others is one the player doesn't have to re-learn.

const ASSETS := "res://assets/"

## button_online.png is two globes with a clear span between them; at the
## icon's 265px on-screen width that span is about 125px, which is what the
## heading has to fit inside.
const TITLE_ICON_GAP_WIDTH := 125.0

@onready var title: Label = $Title
@onready var play_button: Button = $PlayButton
@onready var leaderboard_button: Button = $LeaderboardButton
@onready var back_button: Button = $BackButton
@onready var rank_label: Label = $RankLabel
@onready var record_label: Label = $RecordLabel
@onready var status_label: Label = $StatusLabel
@onready var note_label: Label = $NoteLabel
var nav: FocusNav

func _ready() -> void:
	# Same treatment Options gives its own title: the button art laid behind
	# the heading, with the text showing through the transparent gap between
	# the two icon halves. White here rather than black - both halves of this
	# icon are dark globes.
	# Black at MainMenu's own button size (46), not this screen's smaller body
	# size, so the heading matches "Shop"/"Options" wherever they appear.
	title.add_theme_font_override("font", Game.font_title)
	title.text = StringTable.get_string(StringTable.ID_ONLINE)
	# Measured clear gap between the two globes at the icon's on-screen width.
	UIButtonStyle.fit_menu_button_text(title, TITLE_ICON_GAP_WIDTH)

	_setup_button(play_button, StringTable.get_string(StringTable.ID_CHALLENGE))
	play_button.pressed.connect(_on_play_pressed)

	_setup_button(leaderboard_button, StringTable.get_string(StringTable.ID_LEADERBOARD))
	leaderboard_button.pressed.connect(_on_leaderboard_pressed)

	_setup_button(back_button, StringTable.get_string(StringTable.ID_BACK))
	back_button.pressed.connect(_on_back_pressed)

	# Online battles pay nothing on purpose (the AI ladder is where coins come
	# from) - said up front so a player doesn't grind here expecting money.
	note_label.text = StringTable.get_string(StringTable.ID_ONLINE_NO_REWARD)

	Game.ensure_menu_music()
	_setup_nav()

	# Nothing is playable until the sign-in lands.
	play_button.disabled = true
	leaderboard_button.disabled = true
	await _connect()

func _connect() -> void:
	status_label.text = "..."
	var res := await Net.sign_in(Game.player.save_slot, Game.player.player_name)
	if not is_inside_tree():
		return
	if not res["ok"]:
		status_label.text = "%s: %s" % [StringTable.get_string(StringTable.ID_ONLINE_ERROR), res["error"]]
		return

	# A match still marked active means this client vanished mid-game (crash,
	# alt-F4, dead wifi). The board state was never persisted, so there is
	# nothing to resume into - concede it, which both hands the win to an
	# opponent who may still be sitting there and, crucially, CLOSES the match:
	# an open one blocks this account from ever queueing again.
	# ponytail: replaying the match from the moves table would let a
	# disconnected player rejoin - worth it only if this turns out to happen
	# often to honest players.
	var current := await Net.call_rpc("mp_current_match")
	if current["ok"] and current["data"]["status"] == "matched":
		var stale: String = current["data"]["match"]["id"]
		# If BOTH players walked out, the one who gets back first used to be
		# the one who conceded - which rewarded taking longer to return. Try
		# the clock first: it only succeeds if we were the side registered as
		# waiting for a move, so a genuine walk-out by the opponent is a win
		# here rather than a loss.
		var claimed := await Net.call_rpc("mp_claim_timeout", {"p_match": stale})
		var won: bool = claimed["ok"] and str(claimed["data"].get("status", "")) == "done"
		if not won:
			await Net.call_rpc("mp_abandon", {"p_match": stale})
		# Whichever way it went, the match is closed and the result recorded
		# server-side, so the offline rage-quit punishment (which reads this
		# same flag on next launch) must not fire for it as well.
		Game.player.match_started = false
		SaveSystem.save_player(Game.player)
		status_label.text = StringTable.get_string(
			StringTable.ID_OPPONENT_QUIT if won else StringTable.ID_LOST_BY_QUIT)
	else:
		status_label.text = ""
		await Net.call_rpc("mp_dequeue")

	if not is_inside_tree():
		return

	# Hand back anything the server says has been won off this account since
	# we were last here. Done before the player can queue, because a deck
	# still holding one of those cards is refused outright.
	var handed_over := await Net.reconcile_lost_cards(Game.player)
	if not is_inside_tree():
		return
	if handed_over > 0 and status_label.text == "":
		status_label.text = StringTable.get_string(StringTable.ID_CARDS_LOST) % handed_over

	play_button.disabled = false
	leaderboard_button.disabled = false
	_refresh_standing()

func _refresh_standing() -> void:
	var lb := await Net.call_rpc("mp_leaderboard", {"p_limit": 1})
	if not is_inside_tree() or not lb["ok"]:
		return
	var self_row = lb["data"].get("self")
	if not (self_row is Dictionary):
		return
	# "Rank" on its own meant nothing next to a bare number - spelled out as
	# position-out-of-total, with the rating named rather than abbreviated.
	rank_label.text = "%s %d   %s %d" % [
		StringTable.get_string(StringTable.ID_RANK), int(self_row["rank"]),
		StringTable.get_string(StringTable.ID_RATING), int(self_row["elo"])]
	record_label.text = "%s %d   %s %d   %s %d" % [
		StringTable.get_string(StringTable.ID_WINS), int(self_row["wins"]),
		StringTable.get_string(StringTable.ID_LOSSES), int(self_row["losses"]),
		StringTable.get_string(StringTable.ID_FORFEIT), int(self_row["quits"])]

# ------------------------------------------------------------------- widgets

func _setup_button(btn: Button, label: String) -> void:
	UIButtonStyle.apply(btn)
	btn.text = label
	UIButtonStyle.fit_button_text(btn)

## B is wired through nav.cancelled, the same channel Options and Opponents
## use. An _unhandled_input handler (what this screen had) never sees the
## press: FocusNav consumes nav_cancel first, so B did nothing here at all.
func _setup_nav() -> void:
	nav = FocusNav.new()
	add_child(nav)
	nav.add_control(play_button, 0)
	nav.add_control(leaderboard_button, 1)
	# Back is not a focus stop - it's the B button, and it disappears with the
	# pointer, exactly as on Options.
	ControllerUI.hide_in_gamepad(back_button)

	nav.activated.connect(func(item: FocusNav.NavItem) -> void:
		(item.control as Button).pressed.emit())
	nav.cancelled.connect(_on_back_pressed)
	nav.focus_by_meta(0)
	# One bar carrying both hints, laid out left to right. Previously B was a
	# separate make_button_hint pinned to the Back button's x - which is the
	# same x=42 the prompt bar itself starts at, so the two drew on top of each
	# other and Back was hidden behind Select.
	add_child(ControllerUI.make_prompt_bar([
		[&"A", StringTable.get_string(StringTable.ID_SELECT)],
		[&"B", StringTable.get_string(StringTable.ID_BACK)],
	]))

# ------------------------------------------------------------------ handlers

func _on_play_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	# The AI flow's own deck picker, reused as-is: it communicates the chosen
	# deck through Card.is_on_deck / Player.last_deck, which BattleScene and
	# the matchmaking upload both already read.
	Game.online_mode = true
	Game.online_match = {}
	Game.opponent_index = -1
	Game.rage_quit_mode = false
	get_tree().change_scene_to_file("res://scenes/deckselect/DeckSelect.tscn")

func _on_leaderboard_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/Leaderboard.tscn")

func _on_back_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_back_sound.wav")
	Game.online_mode = false
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
