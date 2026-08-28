extends Node
## Autoload: fire-and-forget sound effects with positional audio and pitch jitter.

const SOUNDS := {
	"shoot": preload("res://assets/sfx/shoot.wav"),
	"hit": preload("res://assets/sfx/hit.wav"),
	"enemy_die": preload("res://assets/sfx/enemy_die.wav"),
	"explosion": preload("res://assets/sfx/explosion.wav"),
	"player_hurt": preload("res://assets/sfx/player_hurt.wav"),
	"place": preload("res://assets/sfx/place.wav"),
	"levelup": preload("res://assets/sfx/levelup.wav"),
	"zap": preload("res://assets/sfx/zap.wav"),
	"flame": preload("res://assets/sfx/flame.wav"),
	"flak": preload("res://assets/sfx/flak.wav"),
}

## Play a sound. Pass a Vector2 for positional 2D audio, null for UI/global.
func play(sound: String, at = null, volume_db: float = 0.0, pitch_jitter: float = 0.08) -> void:
	if not SOUNDS.has(sound):
		return
	var player
	if at == null:
		player = AudioStreamPlayer.new()
	else:
		player = AudioStreamPlayer2D.new()
		player.max_distance = 1400.0
		player.attenuation = 1.2
	player.stream = SOUNDS[sound]
	player.bus = "SFX"
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	add_child(player)
	if at != null:
		player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()
