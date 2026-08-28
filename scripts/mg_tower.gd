extends "res://scripts/building.gd"
## Machine gun tower: re-targets the nearest enemy every shot and fires
## a standard bullet from the rotating head's muzzle.

const FIRE_INTERVAL := 0.35
const FIRE_RANGE := 350.0
const ENERGY_PER_SHOT := 1

var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
var _fire_accum: float = 0.0
var _target

@onready var _head: Node2D = $Head
@onready var _muzzle: Marker2D = $Head/Muzzle

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _target != null and is_instance_valid(_target):
		_head.rotation = (_target.global_position - global_position).angle()
	else:
		_target = null
	_fire_accum += delta
	if _fire_accum >= FIRE_INTERVAL:
		_fire_accum = 0.0
		_target = _nearest_enemy()
		if _target != null:
			if GameState.try_spend_energy(ENERGY_PER_SHOT):
				set_powered(true)
				_head.rotation = (_target.global_position - global_position).angle()
				_fire()
			else:
				set_powered(false)

func _nearest_enemy():
	var nearest = null
	var best := FIRE_RANGE
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var dist: float = enemy.global_position.distance_to(global_position)
		if dist <= best:
			best = dist
			nearest = enemy
	return nearest

func _fire() -> void:
	var bullet = bullet_scene.instantiate()
	bullet.global_position = _muzzle.global_position
	bullet.rotation = _head.global_rotation
	bullet.damage = 1 + GameState.tower_damage_bonus()
	get_tree().current_scene.add_child(bullet)
	Effects.muzzle_flash(self, _muzzle.global_position, _head.global_rotation)
	Sfx.play("shoot", _muzzle.global_position, -12.0)
