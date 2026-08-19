extends Control
## Port of UICredits.cs / UICredits.composer.cs (960x544 design canvas).
## Tap anywhere goes back to Options (Credits_Bkg's TouchEventReceived).
## Static layout (background, credit labels) now lives in Credits.tscn -
## edit positions/text/colors there. Only what's genuinely dynamic (the
## gamepad prompt bar, shared across every screen) is still built here.

const ASSETS := "res://assets/"

@onready var bg: TextureButton = $Bg

func _ready() -> void:
	bg.pressed.connect(_on_back_pressed)

	# Whole screen is one button, so there's nothing to navigate between and
	# nothing meaningful for the hand to point at - A/B are handled directly
	# in _unhandled_input below rather than through a FocusNav item.
	ControllerUI.hide_hand()
	add_child(ControllerUI.make_prompt_bar([
		[&"B", StringTable.get_string(StringTable.ID_BACK)],
	]))

func _unhandled_input(event: InputEvent) -> void:
	if not ControllerUI.is_gamepad():
		return
	if event.is_action_pressed(&"nav_accept") or event.is_action_pressed(&"nav_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()

func _on_back_pressed() -> void:
	Game.play_sfx(ASSETS + "sfx/button_back_sound.wav")
	get_tree().change_scene_to_file("res://scenes/menu/Options.tscn")
