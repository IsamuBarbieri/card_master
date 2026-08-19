extends Control
## Title/attract screen - shown after the studio splash, before the save
## slot select (StartMenu). Background is the game's own splash art; a
## pulsing "Tap/Click to Start" prompt (wording picked by platform) waits
## for any input before moving on. Music starts here, not on the silent
## studio splash - StartMenu.play_music() call is a no-op afterward since
## it's the same track (play_music is idempotent on an already-playing path).
## Static layout (background, prompt box position/size/outline) lives in
## TitleScreen.tscn now. font_title and text stay script-assigned: font_title
## swaps per language (Cyrillic fallback, see Game.gd), and the prompt text
## itself depends on live input mode/platform.

const ASSETS := "res://assets/"

const SCREEN_FADE_IN_TIME := 0.5
const PROMPT_PULSE_TIME := 0.9
const PROMPT_MAX_SCALE := 1.08

var _advanced := false
@onready var prompt_label: Label = $PromptLabel

func _ready() -> void:
	modulate.a = 0.0

	prompt_label.add_theme_font_override("font", Game.font_title)
	_update_prompt_text()
	ControllerUI.mode_changed.connect(func(_m: int) -> void: _update_prompt_text())

	Game.play_music(ASSETS + "music/menu1.mp3")

	var tw_in := create_tween()
	tw_in.tween_property(self, "modulate:a", 1.0, SCREEN_FADE_IN_TIME)

	var tw_pulse := create_tween()
	tw_pulse.set_loops()
	tw_pulse.tween_property(prompt_label, "scale", Vector2.ONE * PROMPT_MAX_SCALE, PROMPT_PULSE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw_pulse.tween_property(prompt_label, "scale", Vector2.ONE, PROMPT_PULSE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch \
			or event is InputEventKey or event is InputEventJoypadButton) and event.pressed:
		_advance()

func _advance() -> void:
	if _advanced:
		return
	_advanced = true
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/StartMenu.tscn")

## Re-picked live (not just once at _ready) since a player can plug in a pad
## - or let go of the stick and touch the screen - while this prompt is
## still pulsing on screen.
func _update_prompt_text() -> void:
	var string_id: int
	if ControllerUI.is_gamepad():
		string_id = StringTable.ID_PAD_TO_START
	elif OS.has_feature("mobile"):
		string_id = StringTable.ID_TAP_TO_START
	else:
		string_id = StringTable.ID_CLICK_TO_START
	prompt_label.text = StringTable.get_string(string_id)
	UIButtonStyle.fit_button_text(prompt_label)
