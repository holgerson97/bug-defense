extends "res://scripts/building.gd"
## WW2-style anti-air flak cannon: only engages air enemies, leading each
## target and firing timed-fuse shells that burst at the predicted position.

const MUZZLE_OFFSET := 34.0
const IDLE_TURN_SPEED := 4.0

var fire_interval: float = Balance.num("towers/aa_tower/interval", 0.9)
var energy_per_shell: int = Balance.inum("towers/aa_tower/energy_per_shell", 2)
var shell_speed: float = Balance.num("towers/aa_tower/shell_speed", 600.0)

var shell_scene: PackedScene = preload("res://scenes/flak_shell.tscn")
var base_range: float = GameState.BUILDINGS["aa_tower"]["range"]
var fire_range: float = base_range
var half_arc: float = deg_to_rad(GameState.BUILDINGS["aa_tower"]["arc"]) / 2.0
var _fire_accum: float = 0.0
var _target

@onready var _head: Node2D = $Head

func _ready() -> void:
	super._ready()
	energy_consumer = true
	_head.rotation = facing

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	## Phase 5: combat is host-only; client copies idle (fire events = Phase 6).
	if Net.is_online() and not Net.is_host():
		return
	## Extended Barrels research scales range live.
	fire_range = base_range * GameState.tower_range_mult()
	if _target != null and is_instance_valid(_target):
		_head.rotation = (_target.global_position - global_position).angle()
	else:
		_target = null
		_head.rotation = lerp_angle(_head.rotation, facing, minf(IDLE_TURN_SPEED * delta, 1.0))
	_fire_accum += delta
	if _fire_accum >= GameState.tower_interval(fire_interval):
		_fire_accum = 0.0
		_target = Util.nearest_in_group(self, "air_enemies", global_position, fire_range, [], true, facing, half_arc)
		if _target != null:
			if grid_powered() and GameState.try_spend_energy(energy_per_shell):
				set_powered(true)
				_fire(_target)
			else:
				set_powered(false)

## Timed-fuse flak: lead the target, clamp the fuse point to max range and
## let the shell burst there whether or not the target is still nearby.
func _fire(target) -> void:
	var flight_time: float = global_position.distance_to(target.global_position) / shell_speed
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
	FxEvents.aa_fire(self, muzzle, _head.rotation, predicted)
