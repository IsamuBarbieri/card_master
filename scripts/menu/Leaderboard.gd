extends Control
## Elo standings (960x544 design canvas). New screen, reached from Online.
##
## One request fetches the top 100 and the caller's own row; the table shows
## ten at a time and pages through them. No incremental loading: a hundred
## rows of six short strings is a few kilobytes, and paging through data
## already in hand beats a round trip per page.
##
## Chrome matches Opponents/Online (same background, same black title, same
## Back button at 42,463 hidden on a pad behind its B hint).

const SCREEN_W := 960
const SCREEN_H := 544
const ASSETS := "res://assets/"
const PAGE_SIZE := 10
const TOP_COUNT := 100
## The table used to stop at y=416 and leave the strip down to the Back button
## empty. Spread to land on that button's own row instead, which buys every
## row four more pixels of height.
const ROW_HEIGHT := 35.0
const ROWS_TOP := 106.0

## One column per number, each right-aligned in its own lane, so a rank of 1
## and a rank of 100 end on the same pixel. Only the name reads left to right.
## The rank lane is wide enough for its own heading - at 70px "Posizione" and
## "Rangliste" were clipped, which is what made the column look misaligned.
## [x, width, alignment]
const COLUMNS := [
	[24.0, 92.0, HORIZONTAL_ALIGNMENT_RIGHT],    # rank
	[126.0, 316.0, HORIZONTAL_ALIGNMENT_LEFT],   # name
	[452.0, 116.0, HORIZONTAL_ALIGNMENT_RIGHT],  # rating
	[578.0, 96.0, HORIZONTAL_ALIGNMENT_RIGHT],   # wins
	[684.0, 96.0, HORIZONTAL_ALIGNMENT_RIGHT],   # losses
	[790.0, 146.0, HORIZONTAL_ALIGNMENT_RIGHT],  # quits
]

## Headings sit over the parchment with no panel behind them, so they are
## white with a black rim. The values below have the highlight band or the
## plain background behind them and read better as flat black.
const HEADER_COLOR := Color.WHITE
const HEADER_OUTLINE := 2
const ROW_COLOR := Color.BLACK
## Band drawn behind the player's own row.
const SELF_BAND_COLOR := Color(1.0, 0.84, 0.32, 0.55)

var status_label: Label
var page_label: Label
var self_band: ColorRect
var rows: Array = []      # Array of Array[Label], one per visible row
var entries: Array = []   # every fetched standing, best first
## Index into `entries` of the caller's own row, -1 if they aren't in the top.
var self_index := -1
var page := 0
var nav: FocusNav

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := TextureRect.new()
	bg.texture = load(ASSETS + "common_bkg_clean.png")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	add_child(bg)

	# Same 46 as Online's and Options' headings.
	var title := FixedSizeLabel.new()
	title.position = Vector2(300, 9)
	title.size = Vector2(359, 47)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", Game.font_stylish)
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color.BLACK)
	title.text = StringTable.get_string(StringTable.ID_LEADERBOARD)
	add_child(title)
	UIButtonStyle.fit_button_text(title)

	# Behind the rows, so the row text draws over it.
	self_band = ColorRect.new()
	self_band.color = SELF_BAND_COLOR
	self_band.position = Vector2(COLUMNS[0][0] - 8.0, ROWS_TOP)
	self_band.size = Vector2(COLUMNS[5][0] + COLUMNS[5][1] + 8.0 - COLUMNS[0][0] + 8.0, ROW_HEIGHT)
	self_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	self_band.visible = false
	add_child(self_band)

	var header := _make_row(ROWS_TOP - ROW_HEIGHT - 2.0, HEADER_COLOR, 22, HEADER_OUTLINE)
	var header_text := [
		StringTable.get_string(StringTable.ID_RANK),
		"",
		StringTable.get_string(StringTable.ID_RATING),
		StringTable.get_string(StringTable.ID_WINS),
		StringTable.get_string(StringTable.ID_LOSSES),
		StringTable.get_string(StringTable.ID_FORFEIT),
	]
	for i in header.size():
		header[i].text = header_text[i]
		# Headings are single words in English and compounds elsewhere; each
		# shrinks into its own lane rather than clipping.
		UIButtonStyle.fit_button_text(header[i])

	for i in PAGE_SIZE:
		rows.append(_make_row(ROWS_TOP + i * ROW_HEIGHT, ROW_COLOR, 24, 0))

	page_label = Label.new()
	page_label.position = Vector2(SCREEN_W / 2.0 - 120.0, 465)
	page_label.size = Vector2(240, 34)
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	page_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_label.add_theme_font_override("font", Game.font_stylish)
	page_label.add_theme_font_size_override("font_size", 28)
	page_label.add_theme_color_override("font_color", Color.BLACK)
	add_child(page_label)

	var prev := _make_page_button("<", Vector2(SCREEN_W / 2.0 - 178.0, 463), _on_prev_pressed)
	var next := _make_page_button(">", Vector2(SCREEN_W / 2.0 + 122.0, 463), _on_next_pressed)

	status_label = Label.new()
	status_label.position = Vector2(0, ROWS_TOP + 4 * ROW_HEIGHT)
	status_label.size = Vector2(SCREEN_W, 34)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_override("font", Game.font_info)
	status_label.add_theme_font_size_override("font_size", 24)
	status_label.add_theme_color_override("font_color", Color(0.45, 0.18, 0.05))
	status_label.text = "..."
	add_child(status_label)

	var back := FixedSizeButton.new()
	UIButtonStyle.apply(back)
	back.text = StringTable.get_string(StringTable.ID_BACK)
	back.position = Vector2(42, 463)
	back.size = Vector2(115, 56)
	back.add_theme_font_override("font", Game.font_stylish)
	back.add_theme_font_size_override("font_size", 36)
	back.add_theme_color_override("font_color", Color.BLACK)
	back.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	back.add_theme_constant_override("shadow_offset_x", 1)
	back.add_theme_constant_override("shadow_offset_y", 1)
	back.pressed.connect(_on_back_pressed)
	add_child(back)
	UIButtonStyle.fit_button_text(back)

	# On a pad the page arrows are left/right rather than focus stops, so the
	# only thing to select here is nothing and B is the only real control -
	# routed through nav.cancelled like every other menu.
	nav = FocusNav.new()
	add_child(nav)
	ControllerUI.hide_in_gamepad(back)
	ControllerUI.hide_in_gamepad(prev)
	ControllerUI.hide_in_gamepad(next)
	ControllerUI.hide_hand()
	nav.cancelled.connect(_on_back_pressed)
	# The shoulder buttons are this project's own paging channel
	# (ControllerUI's nav_page_prev/next, LB/RB) - this is the first screen to
	# need them. Shown as the pair they are, with one shared label.
	add_child(ControllerUI.make_prompt_bar([
		[&"B", StringTable.get_string(StringTable.ID_BACK)],
		[&"LB", ""],
		[&"RB", StringTable.get_string(StringTable.ID_PAGE)],
	]))

	await _load()

## One row of Labels, one per column, filled later by _assign.
func _make_row(y: float, color: Color, font_size: int, outline: int) -> Array:
	var labels: Array = []
	for col in COLUMNS:
		var label := FixedSizeLabel.new()
		label.position = Vector2(col[0], y)
		label.size = Vector2(col[1], ROW_HEIGHT)
		label.horizontal_alignment = col[2]
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_override("font", Game.font_info)
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", color)
		if outline > 0:
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", outline)
		add_child(label)
		labels.append(label)
	return labels

func _make_page_button(text: String, pos: Vector2, on_pressed: Callable) -> Button:
	var btn := FixedSizeButton.new()
	UIButtonStyle.apply(btn)
	btn.text = text
	btn.position = pos
	btn.size = Vector2(56, 56)
	btn.add_theme_font_override("font", Game.font_stylish)
	btn.add_theme_font_size_override("font_size", 36)
	btn.add_theme_color_override("font_color", Color.BLACK)
	btn.pressed.connect(on_pressed)
	add_child(btn)
	UIButtonStyle.fit_button_text(btn)
	return btn

func _load() -> void:
	if not Net.is_signed_in():
		var signed := await Net.sign_in(Game.player.save_slot, Game.player.player_name)
		if not is_inside_tree():
			return
		if not signed["ok"]:
			status_label.text = StringTable.get_string(StringTable.ID_ONLINE_ERROR)
			return

	var res := await Net.call_rpc("mp_leaderboard", {"p_limit": TOP_COUNT})
	if not is_inside_tree():
		return
	if not res["ok"]:
		status_label.text = "%s: %s" % [StringTable.get_string(StringTable.ID_ONLINE_ERROR), res["error"]]
		return

	entries = res["data"]["top"]
	# Located by the row's own is_self flag, not by matching a rank number:
	# the standing the server reports separately is ranked over a different
	# population than this list, so the two disagree and the band ended up on
	# the wrong row. The player's own numbers aren't printed here either way -
	# the Online screen they just came from already shows them.
	self_index = -1
	for i in entries.size():
		if bool(entries[i].get("is_self", false)):
			self_index = i
			break

	status_label.text = ""
	# Open on the page the player is on, rather than always at the top.
	if self_index >= 0:
		page = self_index / PAGE_SIZE
	_show_page()

func _page_count() -> int:
	return maxi(1, ceili(float(entries.size()) / PAGE_SIZE))

func _show_page() -> void:
	page = clampi(page, 0, _page_count() - 1)
	for i in rows.size():
		var index := page * PAGE_SIZE + i
		_assign(rows[i], entries[index] if index < entries.size() else null)

	# The band follows the player's row and hides on every other page.
	var on_page := self_index >= page * PAGE_SIZE and self_index < (page + 1) * PAGE_SIZE
	self_band.visible = self_index >= 0 and on_page
	if self_band.visible:
		self_band.position.y = ROWS_TOP + (self_index - page * PAGE_SIZE) * ROW_HEIGHT

	page_label.text = "%s %d/%d" % [StringTable.get_string(StringTable.ID_PAGE), page + 1, _page_count()]

func _assign(labels: Array, row) -> void:
	if row == null:
		for label in labels:
			label.text = ""
		return
	var values := [
		str(int(row["rank"])),
		str(row["name"]),
		str(int(row["elo"])),
		str(int(row["wins"])),
		str(int(row["losses"])),
		str(int(row["quits"])),
	]
	for i in labels.size():
		labels[i].text = values[i]

func _on_prev_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	page -= 1
	_show_page()

func _on_next_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	page += 1
	_show_page()

## The shoulder buttons page the table on a pad, where the two arrow buttons
## are hidden. Read directly: nothing on this screen is a focus stop, so
## FocusNav only claims nav_cancel and never sees these.
func _unhandled_input(event: InputEvent) -> void:
	if not ControllerUI.is_gamepad():
		return
	if event.is_action_pressed(&"nav_page_prev"):
		_on_prev_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"nav_page_next"):
		_on_next_pressed()
		get_viewport().set_input_as_handled()

func _on_back_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_back_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/Online.tscn")
