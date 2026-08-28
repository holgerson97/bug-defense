extends "res://scripts/building.gd"
## WW2-style anti-air flak cannon: only engages air enemies, leading each
## target and firing timed-fuse shells that burst at the predicted position.

const FIRE_INTERVAL := 0.9
const ENERGY_PER_SHELL := 2
const SHELL_SPEED := 600.0
const MUZZLE_OFFSET := 30.0

var shell_scene: PackedScene = preload("res://scenes/flak_shell.tscn")
var fire_range: float = GameState.BUILDINGS["aa_tower"]["range"]
var _fire_accum: float = 0.0
var _target

@onready var _head: Node2D = $Head

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _target != null and is_instance_valid(_target):
		_head.rotation = (_target.global_position - global_position).angle()
	else:
		_target = null
	_fire_accum += delta
	if _fire_accum >= GameState.tower_interval(FIRE_INTERVAL):
		_fire_accum = 0.0
		_target = Util.nearest_in_group(self, "air_enemies", global_position, fire_range, [], true)
		if _target != null:
			if GameState.try_spend_energy(ENERGY_PER_SHELL):
				set_powered(true)
				_fire(_target)
			else:
				set_powered(false)

## Timed-fuse flak: lead the target, clamp the fuse point to max range and
## let the shell burst there whether or not the target is still nearby.
func _fire(target) -> void:
	var flight_time: float = global_position.distance_to(target.global_position) / SHELL_SPEED
	var predicted: Vector2 = target.global_position + target.velocity * flight_time
	var offset := predicted - global_position
	if offset.length() > fire_range:
		predicted = global_position + offset.normalized() * fire_range
	_head.rotation = offset.angle()
	var muzzle: Vector2 = global_position + Vector2.from_angle(_head.rotation) * MUZZLE_OFFSET
	var shell = shell_scene.instantiate()
	shell.global_position = muzzle
	shell.burst_point = predicted
	get_tree().current_scene.add_child(shell)
	Effects.muzzle_flash(self, muzzle, _head.rotation)
	Sfx.play("shoot", muzzle, -14.0)
