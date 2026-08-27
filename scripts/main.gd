extends Node2D

const DEPOSIT_COUNT := 10
const DEPOSIT_CENTER_CLEARANCE := 250.0
const DEPOSIT_EDGE_MARGIN := 100.0

var score: int = 0
var deposit_scene: PackedScene = preload("res://scenes/crystal_deposit.tscn")

@onready var _player = $Player
@onready var _wave_manager = $WaveManager
@onready var _hud = $HUD

func _ready() -> void:
	GameState.reset()
	_player.died.connect(_on_player_died)
	_wave_manager.wave_started.connect(_hud.update_wave)
	_wave_manager.enemy_killed.connect(_on_enemy_killed)
	_hud.update_score(score)
	_spawn_deposits()

func _spawn_deposits() -> void:
	var center := GameState.WORLD_SIZE / 2.0
	for i in DEPOSIT_COUNT:
		var pos := center
		while pos.distance_to(center) < DEPOSIT_CENTER_CLEARANCE:
			pos = Vector2(
				randf_range(DEPOSIT_EDGE_MARGIN, GameState.WORLD_SIZE.x - DEPOSIT_EDGE_MARGIN),
				randf_range(DEPOSIT_EDGE_MARGIN, GameState.WORLD_SIZE.y - DEPOSIT_EDGE_MARGIN)
			)
		var deposit = deposit_scene.instantiate()
		deposit.global_position = pos
		add_child(deposit)

func _on_enemy_killed(points: int) -> void:
	score += points
	_hud.update_score(score)

func _on_player_died() -> void:
	_hud.show_game_over(score, _wave_manager.wave)
	get_tree().paused = true
