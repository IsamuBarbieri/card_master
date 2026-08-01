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

# Port of Game.cs's Options struct.
var sfx_volume: float = 1.0:
	set(value):
		sfx_volume = value
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(value))
var music_volume: float = 1.0:
	set(value):
		music_volume = value
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(value))
var language: int = 0

var _music_player: AudioStreamPlayer
var _music_path := ""

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

	sfx_volume = sfx_volume
	music_volume = music_volume

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

## One-shot sfx, parented to this autoload (not the calling scene) so it
## keeps playing even if the scene changes right after triggering it.
func play_sfx(path: String) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.bus = "SFX"
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
