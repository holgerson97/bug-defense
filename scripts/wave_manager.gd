extends Node2D

signal wave_started(wave: int)
signal enemy_killed(points: int)

const BRUTE_SCENE = preload("res://scenes/enemies/brute.tscn")
const HEALER_SCENE = preload("res://scenes/enemies/healer.tscn")
const MAGE_SCENE = preload("res://scenes/enemies/mage.tscn")
const BOSS_SCENE = preload("res://scenes/enemies/boss_broodmother.tscn")

@export var enemy_scene: PackedScene
@export var time_between_waves: float = 4.0
@export var spawn_interval: float = 0.5
@export var spawn_radius: float = 800.0

var wave: int = 0
var _alive: int = 0
var _spawning: bool = false

func _ready() -> void:
	add_to_group("wave_manager")
	_start_next_wave_after_delay()

func _start_next_wave_after_delay() -> void:
	await get_tree().create_timer(time_between_waves, false).timeout
	_start_wave()

func _start_wave() -> void:
	wave += 1
	wave_started.emit(wave)
	var boss_wave := wave % 10 == 0
	var grunts := 3 + wave * 2
	@warning_ignore("integer_division")
	var brutes := wave / 4
	@warning_ignore("integer_division")
	var healers := wave / 5
	@warning_ignore("integer_division")
	var mages := mini(wave / 6, 3)
	if boss_wave:
		# Boss waves: the boss plus half the normal composition.
		grunts /= 2
		brutes /= 2
		healers /= 2
		mages /= 2
	var queue: Array = []
	for i in grunts:
		queue.append("grunt")
	for i in brutes:
		queue.append("brute")
	for i in healers:
		queue.append("healer")
	for i in mages:
		queue.append("mage")
	queue.shuffle()
	if boss_wave:
		queue.push_front("boss")
	_spawning = true
	for kind in queue:
		_spawn_kind(kind)
		await get_tree().create_timer(spawn_interval, false).timeout
	_spawning = false
	if _alive == 0:
		_start_next_wave_after_delay()

@warning_ignore("integer_division")
func _spawn_kind(kind) -> void:
	var enemy
	match kind:
		"brute":
			enemy = BRUTE_SCENE.instantiate()
			# Brutes track grunt HP scaling at 5x, with a gentle speed ramp.
			enemy.max_health = (3 + wave / 3) * 5
			enemy.speed += wave * 2.0
		"healer":
			enemy = HEALER_SCENE.instantiate()
			enemy.max_health += wave / 2
		"mage":
			enemy = MAGE_SCENE.instantiate()
			enemy.max_health += wave / 2
		"boss":
			enemy = BOSS_SCENE.instantiate()
			enemy.max_health = 250 * (wave / 10)
		_:
			enemy = enemy_scene.instantiate()
			# Mild difficulty scaling per wave.
			enemy.max_health = 3 + wave / 3
			enemy.speed += wave * 4.0
			enemy.scrap_value = 4 + wave * 2
	enemy.global_position = _spawn_position()
	enemy.died.connect(_on_enemy_died)
	_alive += 1
	get_tree().current_scene.add_child(enemy)

func _spawn_position() -> Vector2:
	var player = get_tree().get_first_node_in_group("player")
	var center: Vector2 = player.global_position if player != null else Vector2.ZERO
	return center + Vector2.from_angle(randf() * TAU) * spawn_radius

## Lets summoners (mage, boss) count their spawns toward wave clearing.
func register_enemy(enemy) -> void:
	enemy.died.connect(_on_enemy_died)
	_alive += 1

func _on_enemy_died(points: int) -> void:
	_alive -= 1
	enemy_killed.emit(points)
	if _alive == 0 and not _spawning:
		_start_next_wave_after_delay()
