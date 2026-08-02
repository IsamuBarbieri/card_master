extends Node
## Autoload. Port of Game.cs's static state, plus a persistent Music/SFX
## setup the original had via its static Music/Globals.soundPlayers - one
## music track survives scene changes instead of restarting per-scene, and
## one-shot sfx (button clicks, the cat meow) are reparented here so they
## finish playing even if the scene that triggered them is gone a frame
## later. Both route through dedicated audio buses so Options's sliders
## affect everything live.

var player: Player = null
var opponent_index: int = -1
var rage_quit_mode: bool = false
## Port of UIMainMenu.cs's autoplayMusic: set true right before returning to
## MainMenu from a battle, so it crossfades into a randomly chosen menu
## track (Music.ChooseMenuMusic()) instead of just continuing whatever was
## already playing.
var autoplay_menu_music: bool = false

# Port of Game.cs's Options struct. These are app-level preferences (not
# part of any player's save data - see SaveSystem.save_settings/
# load_settings), so every setter persists immediately rather than relying
# on some other save point to catch the change.
var sfx_volume: float = 1.0:
	set(value):
		sfx_volume = value
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(value))
		SaveSystem.save_settings()
var music_volume: float = 1.0:
	set(value):
		music_volume = value
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(value))
		SaveSystem.save_settings()
var language: int = 0:
	set(value):
		language = value
		SaveSystem.save_settings()

var _music_player: AudioStreamPlayer
var _music_path := ""

# Kept alive here (not just a local in _ready()) - Godot's load() cache is
# reference-counted, so a FontFile only a local variable mutates would get
# freed once _ready() returns and a later load() elsewhere would silently
# hand back a fresh, unmodified instance (fallbacks lost). See _ready()'s
# fallback setup below.
var _font_stylish: FontFile
var _font_info: FontFile

func _ready() -> void:
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)

	# New QoL fix (not in the reference): font_stylish.ttf/font_info.ttf only
	# cover Latin glyphs, and relying on allow_system_fallback for the rest
	# (as Japanese already did) turned out to render Cyrillic as completely
	# blank. Bundling an explicit OFL-licensed fallback (Latin+Cyrillic+Greek)
	# was the first attempt at fixing this - confirmed NOT sufficient on its
	# own (Cyrillic is still blank even with this in place), so the root
	# cause is still open - likely something deeper in the GL Compatibility
	# renderer's glyph rendering rather than font/glyph availability. Left
	# in place since it's harmless and may still be part of the eventual
	# fix. Set once here, on the same resource instance every
	# load(".../font_stylish.ttf") elsewhere in the codebase returns
	# (Godot caches resources by path), so this single
	# assignment covers every screen without touching each call site.
	var fallback_font: FontFile = load("res://assets/fonts/NotoSans-Regular.ttf")
	_font_stylish = load("res://assets/fonts/font_stylish.ttf")
	_font_info = load("res://assets/fonts/font_info.ttf")
	_font_stylish.fallbacks = [fallback_font]
	_font_info.fallbacks = [fallback_font]

	var settings := SaveSystem.load_settings()
	language = settings.get("language", _detect_default_language())
	sfx_volume = settings.get("sfx_volume", 1.0)
	music_volume = settings.get("music_volume", 1.0)

## First-launch default (before any language has ever been explicitly saved):
## match the OS/device language (Windows now, Android once that release
## happens - OS.get_locale_language() covers both the same way), falling
## back to English if the system language isn't one of the ones this game
## supports.
func _detect_default_language() -> int:
	var code := OS.get_locale_language()
	return StringTable.LANGUAGE_BY_LOCALE.get(code, StringTable.DEFAULT_LANGUAGE)

## Keeps a single track playing across scene changes - calling this again
## with the same path while it's already playing is a no-op.
func play_music(path: String) -> void:
	if _music_path == path and _music_player.playing:
		return
	_music_path = path
	var stream: AudioStream = load(path)
	stream.loop = true
	_music_player.stream = stream
	_music_player.play()

## Port of Events.MusicPlayWithFade: fades the current track out then swaps
## and fades the new one in, instead of an abrupt cut. target_volume_db is a
## per-track mixing tweak (not in the reference, which just uses the
## slider-controlled volume) - battle1.mp3/ragequit_battle.mp3 are louder
## raw files than the menu tracks, so BattleScene passes -8.0 to balance.
func crossfade_music(path: String, fade_time: float, target_volume_db: float = 0.0) -> void:
	var tw := create_tween()
	tw.tween_property(_music_player, "volume_db", -80.0, fade_time)
	await tw.finished
	_music_path = path
	var stream: AudioStream = load(path)
	stream.loop = true
	_music_player.stream = stream
	_music_player.volume_db = target_volume_db
	_music_player.play()

## One-shot sfx, parented to this autoload (not the calling scene) so it
## keeps playing even if the scene changes right after triggering it.
func play_sfx(path: String) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.bus = "SFX"
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
