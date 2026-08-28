extends Node
## Autoload: fire-and-forget sound effects with positional audio and pitch jitter.

## Shared variant pool for tower and player shots; one preload, two cap keys.
const SHOOT_VARIANTS := [
	preload("res://assets/sfx/shoot.wav"),
	preload("res://assets/sfx/shoot_2.wav"),
	preload("res://assets/sfx/shoot_3.wav"),
]

const SOUNDS := {
	## Arrays are variant pools: play() picks one at random to break up spam.
	"shoot": SHOOT_VARIANTS,
	## Own key so MG tower bursts can't starve the player's shot feedback.
	"shoot_player": SHOOT_VARIANTS,
	"shoot_heavy": preload("res://assets/sfx/shoot_heavy.wav"),
	"mg_tail": preload("res://assets/sfx/mg_tail.wav"),
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

## Max simultaneous players per sound name; unlisted names are uncapped.
## Several MG towers firing at once would stack 20+ identical voices into mud.
const VOICE_CAP := {
	"shoot": 6,
	"shoot_player": 3,
	"mg_tail": 4,
}

var _voices := {}

func _ready() -> void:
	# UI sounds fire while the tree is paused (research purchases); without
	# this, players queue up frozen and burst all at once on unpause.
	process_mode = Node.PROCESS_MODE_ALWAYS

## Play a sound. Pass a Vector2 for positional 2D audio, null for UI/global.
func play(sound: String, at = null, volume_db: float = 0.0, pitch_jitter: float = 0.08) -> void:
	if not SOUNDS.has(sound):
		return
	# Voice cap: at the limit the extra copy adds nothing but clutter — skip it.
	if VOICE_CAP.has(sound) and _voices.get(sound, 0) >= VOICE_CAP[sound]:
		return
	var player
	if at == null:
		player = AudioStreamPlayer.new()
	else:
		player = AudioStreamPlayer2D.new()
		player.max_distance = 1400.0
		player.attenuation = 1.2
	var stream = SOUNDS[sound]
	if stream is Array:
		stream = stream.pick_random()
	player.stream = stream
	player.bus = "SFX"
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	add_child(player)
	if at != null:
		player.global_position = at
	_voices[sound] = _voices.get(sound, 0) + 1
	player.finished.connect(_on_finished.bind(player, sound))
	player.play()

func _on_finished(player: Node, sound: String) -> void:
	_voices[sound] = maxi(_voices.get(sound, 1) - 1, 0)
	player.queue_free()
