extends Node
## Every button in the game should answer the mouse. That was silently untrue
## for a long time: each screen overrode font_color (nearly always to black)
## and none of them overrode font_hover_color, so labels never changed under
## the cursor. The fix lives in UIButtonStyle.apply(), which means the rule is
## really "every button goes through apply()" - and that is what this checks,
## by reading the source rather than by building every screen.
## Run: godot --headless --quit-after 200 res://tests/test_button_hover.tscn

const SCRIPT_ROOT := "res://scripts"
## How far after a `Button.new()` to look for the call that styles it. Roomy
## enough to cover a button whose whole theme is set inline before its hover
## colour (StartMenu's and Help's X are ~12 lines long).
const LOOKAHEAD := 18

## A button may skip apply() for exactly two reasons, both of which have to be
## visible right there in the source:
##   flat = true          - an invisible hotspot or a portrait cell; it has no
##                          label to recolour and shows its state some other way
##   font_hover_color     - it deliberately does something else (StartMenu's and
##                          Help's red X, MainMenu's gold Online circle)
const EXEMPTIONS := ["flat = true", "font_hover_color"]

func _gd_files(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path + "/" + entry
		if dir.current_is_dir():
			_gd_files(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()

func _ready() -> void:
	# The rule itself: apply() is what puts the hover on.
	var btn := Button.new()
	UIButtonStyle.apply(btn)
	assert(btn.has_theme_color_override("font_hover_color"),
		"UIButtonStyle.apply no longer sets a hover colour - every button in the game just lost its pointer feedback")
	assert(btn.get_theme_color("font_hover_color") == Color.WHITE,
		"the shared hover colour is no longer white")
	btn.free()

	# ...and the rule has to survive FixedSizeButton, which is what nearly
	# every text button in the game actually is. It draws its label in a child
	# Label rather than as native Button text, and a Label has no hover state -
	# so setting font_hover_color on the button did nothing at all until the
	# button learned to push the right state colour down onto that label.
	var fixed := FixedSizeButton.new()
	UIButtonStyle.apply(fixed)
	fixed.add_theme_color_override("font_color", Color.BLACK)
	fixed.text = "Back"
	add_child(fixed)

	var label: Label = fixed.get_child(0)
	assert(label != null and label.text == "Back", "FixedSizeButton no longer renders through a child Label")
	assert(label.get_theme_color("font_color") == Color.BLACK, "resting colour is not the one that was set")

	fixed.mouse_entered.emit()
	assert(label.get_theme_color("font_color") == Color.WHITE,
		"a hovered FixedSizeButton still draws its label in the resting colour - pointer feedback is dead again")

	fixed.mouse_exited.emit()
	assert(label.get_theme_color("font_color") == Color.BLACK,
		"the label kept the hover colour after the pointer left")

	# Pressing must return to the resting colour, not to Godot's own default
	# pressed grey - a plain Button and a FixedSizeButton used to disagree here.
	fixed.button_down.emit()
	assert(label.get_theme_color("font_color") == Color.BLACK,
		"a pressed button no longer draws its resting colour")
	fixed.button_up.emit()

	# Buttons whose content is child labels (the save slots) light up too.
	var extra := Label.new()
	extra.add_theme_color_override("font_color", Color(0.2, 0.1, 0.0))
	fixed.add_child(extra)
	fixed.add_state_label(extra)
	assert(extra.get_theme_color("font_color") == Color(0.2, 0.1, 0.0), "a registered label lost its own colour at rest")
	fixed.mouse_entered.emit()
	assert(extra.get_theme_color("font_color") == Color.WHITE, "a registered label does not follow the button's hover")
	fixed.mouse_exited.emit()
	assert(extra.get_theme_color("font_color") == Color(0.2, 0.1, 0.0), "a registered label did not go back to its own colour")
	fixed.queue_free()

	var files: Array = []
	_gd_files(SCRIPT_ROOT, files)
	assert(files.size() > 10, "found only %d scripts - the scan is not reaching the source" % files.size())

	var offenders: Array = []
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		var lines := text.split("\n")
		for i in lines.size():
			if not ("Button.new()" in lines[i]):
				continue
			# OptionButton/TextureButton are different widgets with their own
			# skins, and InputEventJoypadButton is not a widget at all - this
			# rule is about plain Buttons.
			if "OptionButton.new()" in lines[i] or "TextureButton.new()" in lines[i] \
					or "InputEvent" in lines[i]:
				continue

			var window := ""
			for j in range(i, mini(i + LOOKAHEAD, lines.size())):
				window += lines[j] + "\n"

			if "UIButtonStyle.apply" in window:
				continue
			var exempt := false
			for marker in EXEMPTIONS:
				if marker in window:
					exempt = true
					break
			if not exempt:
				offenders.append("%s:%d" % [path, i + 1])

	assert(offenders.is_empty(),
		"these buttons neither go through UIButtonStyle.apply nor declare their own hover:\n  " + "\n  ".join(offenders))

	print("OK - every plain Button in %d scripts is styled or explicitly exempt" % files.size())
	get_tree().quit()
