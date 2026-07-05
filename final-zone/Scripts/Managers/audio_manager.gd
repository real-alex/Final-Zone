extends Node
## Central sound playback with pooled players and a named sound library.
## Sounds are looked up by name so real SFX can replace placeholders drop-in.
## Autoload: AudioManager

const POOL_SIZE_2D := 8
const POOL_SIZE_3D := 12

## Named sound library. Missing files are skipped silently so the game
## runs fine before audio has been added.
const SOUND_PATHS := {
	"gunshot": "res://Assets/Audio/gunshot.mp3",
	"silenced": "res://Assets/Audio/silenced.mp3",
	"grenade_explosion": "res://Assets/Audio/grenade_explosion.wav",
	"grenade_bounce": "res://Assets/Audio/grenade_bounce.wav",
	"flashbang": "res://Assets/Audio/flashbang.wav",
	"reload": "res://Assets/Audio/reload.wav",
	"dry_fire": "res://Assets/Audio/dry_fire.wav",
	"hit_marker": "res://Assets/Audio/hit_marker.wav",
	"headshot": "res://Assets/Audio/headshot.wav",
	"footstep": "res://Assets/Audio/footstep.wav",
	"death": "res://Assets/Audio/death.wav",
	"ui_hover": "res://Assets/Audio/ui_hover.wav",
	"ui_click": "res://Assets/Audio/ui_click.wav",
	"respawn": "res://Assets/Audio/respawn.wav",
	"victory": "res://Assets/Audio/victory.wav",
	"defeat": "res://Assets/Audio/defeat.wav",
	"menu_music": "res://Assets/Audio/menu_music.ogg",
}

var _cache: Dictionary = {}
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _music_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)
	for i in POOL_SIZE_2D:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_pool_2d.append(player)
	for i in POOL_SIZE_3D:
		var player := AudioStreamPlayer3D.new()
		player.bus = "SFX"
		player.max_distance = 60.0
		add_child(player)
		_pool_3d.append(player)


func play_sfx(sound_name: String, volume_db: float = 0.0, pitch_variance: float = 0.0) -> void:
	var stream := _get_stream(sound_name)
	if stream == null:
		return
	var player := _free_player_2d()
	if player == null:
		return
	player.bus = "SFX"
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	player.play()


func play_ui(sound_name: String, volume_db: float = 0.0) -> void:
	var stream := _get_stream(sound_name)
	if stream == null:
		return
	var player := _free_player_2d()
	if player == null:
		return
	player.bus = "UI"
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0
	player.play()


func play_music(sound_name: String, volume_db: float = -8.0) -> void:
	if _music_player == null:
		return
	var stream := _get_stream(sound_name)
	if stream == null:
		return
	# Loop via the stream's own property (robust across scene changes).
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = true
	elif stream.has_method("set_loop_mode"):
		stream.set_loop_mode(1)
	_music_player.stop()
	_music_player.stream = stream
	_music_player.volume_db = volume_db
	_music_player.pitch_scale = 1.0
	_music_player.play()


func stop_music() -> void:
	if _music_player != null:
		_music_player.stop()


func play_sfx_3d(sound_name: String, position: Vector3, volume_db: float = 0.0, pitch_variance: float = 0.0) -> void:
	var stream := _get_stream(sound_name)
	if stream == null:
		return
	var player := _free_player_3d()
	if player == null:
		return
	player.global_position = position
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	player.play()


func _get_stream(sound_name: String) -> AudioStream:
	if _cache.has(sound_name):
		return _cache[sound_name]
	if not SOUND_PATHS.has(sound_name):
		push_warning("AudioManager: unknown sound '%s'" % sound_name)
		return null
	var path: String = SOUND_PATHS[sound_name]
	if not ResourceLoader.exists(path):
		_cache[sound_name] = null
		return null
	var stream: AudioStream = load(path)
	_cache[sound_name] = stream
	return stream


func _free_player_2d() -> AudioStreamPlayer:
	for player in _pool_2d:
		if not player.playing:
			return player
	return _pool_2d[0]


func _free_player_3d() -> AudioStreamPlayer3D:
	for player in _pool_3d:
		if not player.playing:
			return player
	return _pool_3d[0]
