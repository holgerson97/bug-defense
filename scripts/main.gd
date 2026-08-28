extends Node2D

const CHUNK_SIZE := 1024.0
const MIN_DEPOSITS_PER_CHUNK := 1
const MAX_DEPOSITS_PER_CHUNK := 2
const DEPOSIT_PLAYER_CLEARANCE := 200.0

const GOLD_CHUNK_CHANCE := 0.35

var score: int = 0
var deposit_scene: PackedScene = preload("res://scenes/crystal_deposit.tscn")
var gold_deposit_scene: PackedScene = preload("res://scenes/gold_deposit.tscn")

var _seeded_chunks: Dictionary = {}

@onready var _player = $Player
@onready var _wave_manager = $WaveManager
@onready var _hud = $HUD

func _ready() -> void:
	GameState.reset()
	_player.died.connect(_on_player_died)
	_wave_manager.wave_started.connect(_hud.update_wave)
	_wave_manager.enemy_killed.connect(_on_enemy_killed)
	_hud.update_score(score)

func _process(_delta: float) -> void:
	_seed_chunks_around_player()

## Endless map: lazily sprinkle crystal blocks into chunks near the player.
func _seed_chunks_around_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var center := Vector2i((_player.global_position / CHUNK_SIZE).floor())
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var chunk := center + Vector2i(dx, dy)
			if _seeded_chunks.has(chunk):
				continue
			_seeded_chunks[chunk] = true
			_seed_chunk(chunk)

func _seed_chunk(chunk: Vector2i) -> void:
	for i in randi_range(MIN_DEPOSITS_PER_CHUNK, MAX_DEPOSITS_PER_CHUNK):
		_place_deposit(deposit_scene, chunk)
	# Gold is rarer: at most one block per chunk.
	if randf() < GOLD_CHUNK_CHANCE:
		_place_deposit(gold_deposit_scene, chunk)

func _place_deposit(scene: PackedScene, chunk: Vector2i) -> void:
	var pos := Vector2(chunk) * CHUNK_SIZE + Vector2(randf_range(80.0, CHUNK_SIZE - 80.0), randf_range(80.0, CHUNK_SIZE - 80.0))
	if pos.distance_to(_player.global_position) < DEPOSIT_PLAYER_CLEARANCE:
		return
	var deposit = scene.instantiate()
	deposit.global_position = pos
	add_child(deposit)

func _on_enemy_killed(points: int) -> void:
	score += points
	_hud.update_score(score)

func _on_player_died() -> void:
	_hud.show_game_over(score, _wave_manager.wave)
	get_tree().paused = true
