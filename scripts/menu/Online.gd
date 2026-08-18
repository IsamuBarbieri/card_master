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

const SCREEN_W := 960
const SCREEN_H := 544
const ASSETS := "res://assets/"
const LABEL_FONT_SIZE := 36

## The three lobby buttons, evenly spaced down the middle of the screen.
const BUTTON_SIZE := Vector2(274, 62)
const BUTTON_X := (SCREEN_W - 274) / 2.0
const BUTTON_TOP := 170.0
const BUTTON_STEP := 82.0
## button_online.png is two globes with a clear span between them; at the
## icon's 265px on-screen width that span is about 125px, which is what the
## heading has to fit inside.
const TITLE_ICON_GAP_WIDTH := 125.0
## Matches MainMenu's own button labels and Options' title.
const TITLE_FONT_SIZE := 46

var play_button: Button
var leaderboard_button: Button
var back_button: Button
var status_label: Label
var rank_label: Label
var record_label: Label
var nav: FocusNav

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var font_stylish: Font = Game.font_stylish

	var bg := TextureRect.new()
	bg.texture = load(ASSETS + "common_bkg_clean.png")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	add_child(bg)

	# Same treatment Options gives its own title: the button art laid behind
	# the heading, with the text showing through the transparent gap between
	# the two icon halves. White here rather than black - both halves of this
	# icon are dark globes.
	var icon := TextureRect.new()
	icon.texture = load(ASSETS + "button_online.png")
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.position = UIConstants.SCREEN_TITLE_ICON_POS
	icon.size = Vector2(265, 68)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)

	# Black at MainMenu's own button size (46), not this screen's smaller body
	# size, so the heading matches "Shop"/"Options" wherever they appear.
	var title := _make_label(UIConstants.SCREEN_TITLE_LABEL_POS, Vector2(264, 60), Game.font_title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.text = StringTable.get_string(StringTable.ID_ONLINE)
	add_child(title)
	# Measured clear gap between the two globes at the icon's on-screen width.
	UIButtonStyle.fit_menu_button_text(title, TITLE_ICON_GAP_WIDTH)

	play_button = _make_text_button(StringTable.get_string(StringTable.ID_CHALLENGE),
		Vector2(BUTTON_X, BUTTON_TOP), BUTTON_SIZE, font_stylish)
	play_button.pressed.connect(_on_play_pressed)

	leaderboard_button = _make_text_button(StringTable.get_string(StringTable.ID_LEADERBOARD),
		Vector2(BUTTON_X, BUTTON_TOP + BUTTON_STEP), BUTTON_SIZE, font_stylish)
	leaderboard_button.pressed.connect(_on_leaderboard_pressed)

	back_button = _make_text_button(StringTable.get_string(StringTable.ID_BACK),
		UIConstants.BACK_BUTTON_POS, UIConstants.BACK_BUTTON_SIZE, font_stylish)
	back_button.pressed.connect(_on_back_pressed)

	# Standing, split across two lines instead of one run-on row. Each half is
	# "caption: value" on its own line so a four-digit rating or a three-digit
	# win count just makes the number longer - nothing has to be re-measured,
	# and nothing can collide with the line next to it.
	rank_label = _make_info_label(BUTTON_TOP + 2 * BUTTON_STEP + 18.0, 28)
	record_label = _make_info_label(BUTTON_TOP + 2 * BUTTON_STEP + 52.0, 24)

	status_label = _make_info_label(UIConstants.ONLINE_STATUS_LABEL_Y, 22)
	status_label.add_theme_color_override("font_color", UIConstants.COLOR_STATUS_BROWN)

	# Online battles pay nothing on purpose (the AI ladder is where coins come
	# from) - said up front so a player doesn't grind here expecting money.
	# Down on the gamepad hint row, level with the A/B prompts and the Back
	# button beside them. Centred, so it clears the prompts, which run left to
	# right from x=42.
	var note := _make_info_label(ControllerUI.PROMPT_BAR_Y, 20)
	note.add_theme_color_override("font_color", UIConstants.ONLINE_NOTE_COLOR)
	note.text = StringTable.get_string(StringTable.ID_ONLINE_NO_REWARD)

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

func _make_label(pos: Vector2, size: Vector2, font: Font) -> Label:
	var label := FixedSizeLabel.new()
	label.position = pos
	label.size = size
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", Color.BLACK)
	label.add_theme_color_override("font_shadow_color", UIConstants.COLOR_SHADOW_DIM)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

## Full-width and centered, so however long the numbers get the line simply
## grows outward from the middle instead of running into anything.
func _make_info_label(y: float, font_size: int) -> Label:
	var label := Label.new()
	label.position = Vector2(0, y)
	label.size = Vector2(SCREEN_W, font_size + 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", Game.font_info)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.BLACK)
	add_child(label)
	return label

func _make_text_button(label: String, pos: Vector2, size: Vector2, font: Font) -> Button:
	var btn := FixedSizeButton.new()
	UIButtonStyle.apply(btn)
	btn.text = label
	btn.position = pos
	btn.size = size
	btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	btn.add_theme_color_override("font_color", Color.BLACK)
	btn.add_theme_color_override("font_shadow_color", UIConstants.COLOR_SHADOW_DIM)
	btn.add_theme_constant_override("shadow_offset_x", 1)
	btn.add_theme_constant_override("shadow_offset_y", 1)
	add_child(btn)
	UIButtonStyle.fit_button_text(btn)
	return btn

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
