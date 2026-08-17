extends Node
## Autoload. Port of Game.cs's static state, plus a persistent Music/SFX
## setup the original had via its static Music/Globals.soundPlayers - one
## music track survives scene changes instead of restarting per-scene, and
## one-shot sfx (button clicks, the cat meow) are reparented here so they
## finish playing even if the scene that triggered them is gone a frame
## later. Both route through dedicated audio buses so Options's sliders
## affect everything live.

## Setting this claims the slot's lock and drops the previous one, so no
## caller has to remember to do it: whoever loads a save holds it, and going
## back to the slot list (which clears this) releases it. See SaveSystem's
## locking section for why a second copy of the game must not open the same
## save.
var player: Player = null:
	set(value):
		if player != null and (value == null or value.save_slot != player.save_slot):
			SaveSystem.release_lock(player.save_slot)
		player = value
		if player != null:
			SaveSystem.refresh_lock(player.save_slot)

var opponent_index: int = -1
var rage_quit_mode: bool = false

## Online match state, set by the matchmaking screen and read by BattleScene
## (empty/false for every offline battle, so the AI path is untouched). Keys:
## id, seed, first_player, my_slot, opponent_deck, opponent_name.
var online_mode: bool = false
var online_match: Dictionary = {}

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
		_update_fonts_for_language()
		SaveSystem.save_settings()

var _music_player: AudioStreamPlayer
var _music_path := ""

## Every screen reads Game.font_stylish/font_info instead of load()-ing the
## .ttf path itself (used to be ~15 separate load() calls, one per screen -
## centralized here so there's a single point to swap fonts per language).
## Both start out pointing at the game's own decorative fonts; _update_fonts
## _for_language() below swaps them for languages those fonts can't render.
var font_stylish: Font
var font_info: Font

var _font_stylish_default: FontFile
var _font_info_default: FontFile
## font_stylish.ttf/font_info.ttf's own fallback mechanism turned out to be
## broken (confirmed via every mechanism Godot offers - .fallbacks,
## FontVariation, forcing a fresh non-cached load - Cyrillic still measures/
## renders as blank even with a verified-working fallback font attached).
## Extended Latin (the accents ES/DE/FR/PT need) IS natively covered by
## font_stylish.ttf itself, so this only matters for scripts it has zero
## native coverage for - Russian confirmed broken, swapped to this OFL
## font instead of fighting the broken fallback. Chinese would need the
## same treatment but with a CJK-capable font, not yet sourced (Noto Sans
## here is Latin/Greek/Cyrillic only) - still broken for now.
var _fallback_font: FontFile

func _ready() -> void:
	# Explicit rather than relying on the project default staying 0/uncapped
	# - guarantees animations (Title Screen's pulse, etc) aren't throttled by
	# any stray fps cap regardless of platform/export settings.
	Engine.max_fps = 0

	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)

	_font_stylish_default = load("res://assets/fonts/font_stylish.ttf")
	_font_info_default = load("res://assets/fonts/font_info.ttf")
	_fallback_font = load("res://assets/fonts/NotoSans-Regular.ttf")

	_setup_mouse_cursor()

	var settings := SaveSystem.load_settings()
	language = settings.get("language", _detect_default_language())
	sfx_volume = settings.get("sfx_volume", 1.0)
	music_volume = settings.get("music_volume", 1.0)

	# Keeps this copy's claim on the loaded slot alive. Without the heartbeat
	# the lock would look abandoned after LOCK_STALE_SECONDS and a second copy
	# would happily open the same save on top of it.
	var lock_timer := Timer.new()
	lock_timer.wait_time = LOCK_HEARTBEAT_SECONDS
	lock_timer.timeout.connect(_heartbeat_slot_lock)
	add_child(lock_timer)
	lock_timer.start()

const LOCK_HEARTBEAT_SECONDS := 5.0

func _heartbeat_slot_lock() -> void:
	if player != null:
		SaveSystem.refresh_lock(player.save_slot)

## Releases the lock on a clean exit. A kill or a crash leaves it behind, but
## it goes stale on its own - that's the point of the timestamp.
func _exit_tree() -> void:
	if player != null:
		SaveSystem.release_lock(player.save_slot)

## assets/cursor.png as the OS mouse pointer. Input.set_custom_mouse_cursor
## draws at the texture's real screen-pixel size - unlike everything else
## in the game, it isn't scaled by the canvas_items window stretch - so the
## source art (authored at 4x for crisp in-game use elsewhere) is resized
## down to an actual on-screen pointer size here.
const CURSOR_SIZE := 48

func _setup_mouse_cursor() -> void:
	var img: Image = load("res://assets/cursor.png").get_image()
	img.resize(CURSOR_SIZE, CURSOR_SIZE, Image.INTERPOLATE_LANCZOS)
	Input.set_custom_mouse_cursor(ImageTexture.create_from_image(img))

## Picks which actual font backs the public font_stylish/font_info for the
## current language - see _fallback_font's docstring above for why this
## swap exists instead of just attaching a fallback to the default fonts.
func _update_fonts_for_language() -> void:
	if language == StringTable.LANGUAGE_BY_LOCALE["ru"]:
		font_stylish = _fallback_font
		font_info = _fallback_font
	else:
		font_stylish = _font_stylish_default
		font_info = _font_info_default

## First-launch default (before any language has ever been explicitly saved):
## match the OS/device language (Windows now, Android once that release
## happens - OS.get_locale_language() covers both the same way), falling
## back to English if the system language isn't one of the ones this game
## supports.
func _detect_default_language() -> int:
	var code := OS.get_locale_language()
	return StringTable.LANGUAGE_BY_LOCALE.get(code, StringTable.DEFAULT_LANGUAGE)

const MENU_TRACKS := ["res://assets/music/menu1.mp3", "res://assets/music/menu2.mp3"]

var _music_tween: Tween

## Keeps a single track playing across scene changes - calling this again
## with the same path while it's already playing is a no-op. Also cancels
## any crossfade still in flight: without this, a crossfade fired from a
## scene that's about to change (e.g. BattleScene returning to menu music
## right before change_scene_to_file) could still be mid-fade when the next
## scene calls play_music/crossfade_music of its own - the earlier one's
## delayed swap-and-play would then land after the later one and stomp it,
## audible as the previous track suddenly cutting back in.
func play_music(path: String) -> void:
	_cancel_music_tween()
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
	_cancel_music_tween()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", -80.0, fade_time)
	await _music_tween.finished
	_music_path = path
	var stream: AudioStream = load(path)
	stream.loop = true
	_music_player.stream = stream
	_music_player.volume_db = target_volume_db
	_music_player.play()

## A killed tween never fires `finished`, so the coroutine still parked at
## `await _music_tween.finished` above simply never resumes - its swap-and-
## play half is skipped entirely instead of racing the new call.
func _cancel_music_tween() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()

## For screens that just want "some menu track playing" without caring
## which - a no-op if one of MENU_TRACKS is already playing (returning to
## MainMenu from Opponents, which never stops the menu music itself), so it
## doesn't restart or switch the track under the player.
func ensure_menu_music() -> void:
	if _music_path in MENU_TRACKS:
		return
	play_music(MENU_TRACKS[randi() % MENU_TRACKS.size()])

## Crossfades into a random menu track - for transitions actually coming
## FROM a different track (battle music) that need the fade, unlike
## ensure_menu_music's plain no-op/instant-start.
func crossfade_to_menu_music(fade_time: float) -> void:
	crossfade_music(MENU_TRACKS[randi() % MENU_TRACKS.size()], fade_time)

## One-shot sfx, parented to this autoload (not the calling scene) so it
## keeps playing even if the scene changes right after triggering it.
func play_sfx(path: String, pitch_scale: float = 1.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.bus = "SFX"
	p.pitch_scale = pitch_scale
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
