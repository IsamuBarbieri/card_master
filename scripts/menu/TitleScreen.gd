extends Control
## Title/attract screen - shown after the studio splash, before the save
## slot select (StartMenu). Background is the game's own splash art; a
## pulsing "Tap/Click to Start" prompt (wording picked by platform) waits
## for any input before moving on. Music starts here, not on the silent
## studio splash - StartMenu.play_music() call is a no-op afterward since
## it's the same track (play_music is idempotent on an already-playing path).

const SCREEN_W := 960
const SCREEN_H := 544
const ASSETS := "res://assets/"

const SCREEN_FADE_IN_TIME := 0.5
const PROMPT_PULSE_TIME := 0.9
const PROMPT_MAX_SCALE := 1.08
## Sized for the widest "Tap/Click to Start" translation at font_size 60
## (Japanese "クリックしてスタート" measures ~593x69) plus padding - shorter
## languages (English "Click to Start" is ~317x68) just center with room to
## spare; fit_button_text below is still the real safety net if a future
## translation runs wider than this.
const PROMPT_BOX_SIZE := Vector2(650, 90)

var _advanced := false
var prompt_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	modulate.a = 0.0

	var bg := TextureRect.new()
	bg.texture = load(ASSETS + "app_splash_screen.png")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	prompt_label = FixedSizeLabel.new()
	prompt_label.position = (Vector2(SCREEN_W, SCREEN_H) - PROMPT_BOX_SIZE) / 2.0
	prompt_label.size = PROMPT_BOX_SIZE
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_override("font", Game.font_title)
	prompt_label.add_theme_font_size_override("font_size", 60)
	prompt_label.add_theme_color_override("font_color", Color.WHITE)
	prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt_label.add_theme_constant_override("outline_size", 3)
	prompt_label.pivot_offset = prompt_label.size / 2.0
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt_label)
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
