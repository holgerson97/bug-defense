extends CharacterBody2D

signal died
signal health_changed(current: int, total: int)

@export var base_speed: float = 320.0
@export var base_fire_rate: float = 0.15

const Effects = preload("res://scripts/effects.gd")

const MINER_COST := {"scrap": 25}
const MINER_PLACE_RANGE := 80.0
const RECOIL_KICK := 5.0
const RECOIL_MAX := 14.0
const RECOIL_RECOVER := 14.0

var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
var miner_scene: PackedScene = preload("res://scenes/miner.tscn")
var health: int
var _max_health: int
var _fire_cooldown: float = 0.0
var _regen_accum: float = 0.0
var _dead: bool = false
var _recoil: Vector2 = Vector2.ZERO

@onready var _health_bar: ProgressBar = $HealthBar
@onready var _camera: Camera2D = $Camera2D

func _ready() -> void:
	var cam: Camera2D = $Camera2D
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(GameState.WORLD_SIZE.x)
	cam.limit_bottom = int(GameState.WORLD_SIZE.y)
	GameState.upgrades_changed.connect(_on_upgrades_changed)
	_max_health = GameState.player_max_health()
	health = _max_health
	_update_health_bar()

func _physics_process(delta: float) -> void:
	_health_bar.global_position = global_position + Vector2(-22, -40)

	# Camera recoil eases back to zero; offset doesn't fight position smoothing.
	_recoil *= exp(-RECOIL_RECOVER * delta)
	if _recoil.length_squared() < 0.01:
		_recoil = Vector2.ZERO
	_camera.offset = _recoil

	if _dead:
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_dir * GameState.player_speed(base_speed)
	move_and_slide()
	global_position = global_position.clamp(Vector2(16, 16), GameState.WORLD_SIZE - Vector2(16, 16))
	look_at(get_global_mouse_position())

	var regen := GameState.player_regen()
	if regen > 0.0 and health < _max_health:
		_regen_accum += regen * delta
		if _regen_accum >= 1.0:
			var heal := int(_regen_accum)
			_regen_accum -= heal
			health = mini(health + heal, _max_health)
			_update_health_bar()

	_fire_cooldown -= delta
	var selected := GameState.selected_item_id()
	if selected == "blaster" and Input.is_action_pressed("shoot") and _fire_cooldown <= 0.0:
		_shoot()
		_fire_cooldown = GameState.player_fire_cooldown(base_fire_rate)
	elif selected == "miner" and Input.is_action_just_pressed("shoot"):
		_try_place_miner()

func _try_place_miner() -> void:
	var mouse := get_global_mouse_position()
	var target = null
	var best_dist := MINER_PLACE_RANGE
	for deposit in get_tree().get_nodes_in_group("deposits"):
		var dist: float = deposit.global_position.distance_to(mouse)
		if dist <= best_dist:
			best_dist = dist
			target = deposit
	if target == null or target.crystal <= 0 or target.has_miner:
		return
	if not GameState.spend(MINER_COST):
		return
	var miner = miner_scene.instantiate()
	miner.deposit = target
	target.has_miner = true
	target.add_child(miner)

func _shoot() -> void:
	var bullet = bullet_scene.instantiate()
	bullet.global_position = $Muzzle.global_position
	bullet.rotation = rotation
	bullet.damage = GameState.player_damage()
	get_tree().current_scene.add_child(bullet)
	Effects.muzzle_flash(self, $Muzzle.global_position, rotation)
	_recoil = (_recoil - transform.x * RECOIL_KICK).limit_length(RECOIL_MAX)

func take_damage(amount: int) -> void:
	if _dead:
		return
	health = maxi(health - amount, 0)
	_update_health_bar()
	health_changed.emit(health, _max_health)
	if health == 0:
		_dead = true
		died.emit()

func _update_health_bar() -> void:
	_health_bar.max_value = _max_health
	_health_bar.value = health

func _on_upgrades_changed() -> void:
	var new_max := GameState.player_max_health()
	if new_max != _max_health:
		health += maxi(new_max - _max_health, 0)
		_max_health = new_max
		health = mini(health, _max_health)
		_update_health_bar()
