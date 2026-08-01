extends Control
## Port of UIStartMenu.cs / UIStartMenu.composer.cs (960x544 design canvas).
## Save-slot select screen with no SaveSystem behind it yet (comes later) -
## every slot is always "New". A tap creates a fresh in-memory Player
## (Game.player), same starting state SaveSystem.CreateNewPlayer would give
## a brand-new slot, and goes straight to MainMenu (skips UINewPlayer's name
## entry, matching GotoNextMenu()'s SetScene(UIMainMenu)).

const SCREEN_W := 960
const SCREEN_H := 544
const ASSETS := "res://assets/"

const SLOT_POSITIONS := [Vector2(344, 115), Vector2(344, 240), Vector2(344, 362)]
const SLOT_SIZE := Vector2(271, 71)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := TextureRect.new()
	bg.texture = load(ASSETS + "common_bkg_dark_clean.png")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = Vector2(SCREEN_W, SCREEN_H)
	add_child(bg)

	var font_stylish: Font = load(ASSETS + "fonts/font_stylish.ttf")
	for i in SLOT_POSITIONS.size():
		var slot := Button.new()
		slot.position = SLOT_POSITIONS[i]
		slot.size = SLOT_SIZE
		slot.text = StringTable.get_string(StringTable.ID_NEW)
		slot.add_theme_font_override("font", font_stylish)
		slot.add_theme_font_size_override("font_size", 36)
		slot.add_theme_color_override("font_color", Color.BLACK)
		slot.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
		slot.add_theme_constant_override("shadow_offset_x", 1)
		slot.add_theme_constant_override("shadow_offset_y", 1)
		slot.pressed.connect(_on_slot_pressed.bind(i))
		add_child(slot)

	Game.play_music(ASSETS + "music/menu1.mp3")

func _on_slot_pressed(slot_index: int) -> void:
	Game.play_sfx(ASSETS + "sfx/button_sound.wav")
	Game.player = Player.new("Player", slot_index, AIManager.count())
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
