extends Node
## Verifies two music bugs stay fixed:
##  1. ensure_menu_music() must not touch the track if a menu track is
##     already playing (MainMenu no longer force-picks menu1.mp3 on return
##     from Opponents).
##  2. A crossfade fired right before a scene change must not out-race the
##     next scene's own crossfade - starting a new crossfade/play_music call
##     has to cancel any crossfade still mid-fade, or the stale one's
##     delayed swap-and-play lands after and stomps the new track.
## Run: godot --headless --quit-after 300 res://tests/test_music_race.tscn
## (needs enough frames to cover the ~1.85s of waits below; the script calls
## get_tree().quit() itself once done, --quit-after is just a safety cap)

func _ready() -> void:
	# 1. ensure_menu_music is a no-op once a menu track is already playing.
	Game.play_music("res://assets/music/menu1.mp3")
	assert(Game._music_path == "res://assets/music/menu1.mp3")
	for i in 5:
		Game.ensure_menu_music()
	assert(Game._music_path == "res://assets/music/menu1.mp3", "ensure_menu_music switched an already-playing menu track")

	# 2. A later crossfade must win over an earlier one still fading out -
	# simulates leaving BattleScene (crossfade to a menu track, unawaited)
	# right before the next BattleScene starts its own crossfade to battle
	# music, which used to race and could let the stale menu swap land last.
	Game.crossfade_music("res://assets/music/menu2.mp3", 0.85)  # long fade, not awaited
	await get_tree().process_frame  # let the first tween actually start
	await Game.crossfade_music("res://assets/music/battle1.mp3", 0.05)  # short fade, awaited to completion
	assert(Game._music_path == "res://assets/music/battle1.mp3", "second crossfade did not win immediately")

	# Give the first (should-be-cancelled) crossfade's original 0.85s window
	# time to fully elapse - if it wasn't really cancelled, its delayed
	# swap-and-play fires here and stomps battle1.mp3 back to menu2.mp3.
	await get_tree().create_timer(1.0).timeout
	assert(Game._music_path == "res://assets/music/battle1.mp3", "stale crossfade fired late and stomped the track: now %s" % Game._music_path)

	print("OK - music race checks passed")
	get_tree().quit()
