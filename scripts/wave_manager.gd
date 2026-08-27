extends Node2D

signal wave_started(wave: int)
signal enemy_killed(points: int)

@export var enemy_scene: PackedScene
@export var time_between_waves: float = 4.0
@export var spawn_interval: float = 0.5
@export var spawn_radius: float = 800.0

var wave: int = 0
var _alive: int = 0
var _spawning: bool = false

func _ready() -> void:
	_start_next_wave_after_delay()

func _start_next_wave_after_delay() -> void:
	await get_tree().create_timer(time_between_waves, false).timeout
	_start_wave()

func _start_wave() -> void:
	wave += 1
	wave_started.emit(wave)
	var count := 3 + wave * 2
	_spawning = true
	for i in count:
		_spawn_enemy()
		await get_tree().create_timer(spawn_interval, false).timeout
	_spawning = false
	if _alive == 0:
		_start_next_wave_after_delay()

func _spawn_enemy() -> void:
	var player = get_tree().get_first_node_in_group("player")
	var center: Vector2 = player.global_position if player != null else GameState.WORLD_SIZE / 2.0
	var pos := center + Vector2.from_angle(randf() * TAU) * spawn_radius
	pos = pos.clamp(Vector2(24, 24), GameState.WORLD_SIZE - Vector2(24, 24))

	var enemy = enemy_scene.instantiate()
	enemy.global_position = pos
	# Mild difficulty scaling per wave.
	enemy.max_health = 3 + wave / 3
	enemy.speed += wave * 4.0
	enemy.scrap_value = 4 + wave * 2
	enemy.died.connect(_on_enemy_died)
	_alive += 1
	get_tree().current_scene.add_child(enemy)

func _on_enemy_died(points: int) -> void:
	_alive -= 1
	enemy_killed.emit(points)
	if _alive == 0 and not _spawning:
		_start_next_wave_after_delay()
