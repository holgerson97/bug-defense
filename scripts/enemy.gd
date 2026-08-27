extends CharacterBody2D

signal died(points: int)

const Effects = preload("res://scripts/effects.gd")

@export var speed: float = 110.0
@export var max_health: int = 3
@export var damage: int = 8
@export var attack_interval: float = 0.8
@export var attack_range: float = 36.0
@export var points: int = 10
@export var xp_value: int = 10
@export var scrap_value: int = 6

var health: int
var _attack_cooldown: float = 0.0
var _target

func _ready() -> void:
	health = max_health
	_target = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return

	var to_target: Vector2 = _target.global_position - global_position
	rotation = to_target.angle()

	if to_target.length() > attack_range:
		velocity = to_target.normalized() * speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO
		_attack_cooldown -= delta
		if _attack_cooldown <= 0.0:
			_target.take_damage(damage)
			_attack_cooldown = attack_interval

func take_damage(amount: int) -> void:
	health -= amount
	# Enemy faces the player, so the bullet came from +x; blood sprays away.
	var hit_pos: Vector2 = global_position + transform.x * 6.0
	var hit_dir: Vector2 = -transform.x
	if health <= 0:
		Effects.blood_death(self, hit_pos, hit_dir)
		GameState.add_xp(xp_value)
		GameState.add_resource("scrap", scrap_value)
		died.emit(points)
		queue_free()
	else:
		Effects.blood_hit(self, hit_pos, hit_dir)
