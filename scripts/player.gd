extends CharacterBody2D
## The space marine: movement, aiming, shooting and health. Building
## placement lives in the BuildController child node.

signal died

@export var base_speed: float = 320.0
@export var base_fire_rate: float = 0.15

const RECOIL_KICK := 5.0
const RECOIL_MAX := 14.0
const RECOIL_RECOVER := 14.0
const AUTO_ATTACK_RANGE := 700.0

var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
var health: int
var _max_health: int
var _fire_cooldown: float = 0.0
var _regen_accum: float = 0.0
var _dead: bool = false
var _recoil: Vector2 = Vector2.ZERO

@onready var _health_bar: ProgressBar = $HealthBar
@onready var _camera: Camera2D = $Camera2D
@onready var _build = $BuildController

func _ready() -> void:
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
	# Space auto-attacks the closest enemy, overriding mouse aim.
	var auto_target = null
	if Input.is_action_pressed("auto_attack"):
		auto_target = Util.nearest_in_group(self, "enemies", global_position, AUTO_ATTACK_RANGE)
	if auto_target != null:
		look_at(auto_target.global_position)
	else:
		var mouse := get_global_mouse_position()
		if global_position.distance_squared_to(mouse) > 16.0:
			look_at(mouse)

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
	# Auto-attack fires the blaster regardless of the selected hotbar slot.
	var firing := auto_target != null or (selected == "blaster" and Input.is_action_pressed("shoot"))
	if firing and _fire_cooldown <= 0.0:
		_shoot()
		_fire_cooldown = GameState.player_fire_cooldown(base_fire_rate)
	_build.tick(selected)

func _shoot() -> void:
	var bullet = bullet_scene.instantiate()
	bullet.global_position = $Muzzle.global_position
	bullet.rotation = rotation
	var dmg := GameState.player_damage()
	if randf() < GameState.player_crit_chance():
		dmg = int(ceil(dmg * GameState.player_crit_mult()))
		bullet.crit = true
	bullet.damage = dmg
	get_tree().current_scene.add_child(bullet)
	Effects.muzzle_flash(self, $Muzzle.global_position, rotation)
	Sfx.play("shoot", $Muzzle.global_position, -6.0)
	_recoil = (_recoil - transform.x * RECOIL_KICK).limit_length(RECOIL_MAX)

func take_damage(amount: int) -> void:
	if _dead:
		return
	Sfx.play("player_hurt", global_position, -3.0)
	health = maxi(health - amount, 0)
	_update_health_bar()
	if health == 0:
		_dead = true
		died.emit()

func heal(amount: int) -> void:
	if _dead or health >= _max_health:
		return
	health = mini(health + amount, _max_health)
	_update_health_bar()

func max_health() -> int:
	return _max_health

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
