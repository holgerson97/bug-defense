extends "res://scripts/building.gd"
## Machine gun tower: fires proper bursts — 30 rapid bullets with a slight
## spray, then a short cooldown. Retargets a few times per burst so the
## stream walks across the horde.

const RETARGET_EVERY := 6
const SPRAY := 0.06
const IDLE_TURN_SPEED := 4.0

var burst_size: int = Balance.inum("towers/mg_tower/burst_size", 30)
var shot_interval: float = Balance.num("towers/mg_tower/shot_interval", 0.05)
var cooldown: float = Balance.num("towers/mg_tower/cooldown", 0.5)
var energy_per_burst: int = Balance.inum("towers/mg_tower/energy_per_burst", 5)
var damage_base: int = Balance.inum("towers/mg_tower/damage", 1)

var base_range: float = GameState.BUILDINGS["mg_tower"]["range"]
var fire_range: float = base_range
var half_arc: float = deg_to_rad(GameState.BUILDINGS["mg_tower"]["arc"]) / 2.0

var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
var _accum: float = 0.0
var _burst_left: int = 0
var _burst_first: bool = false
var _shots_since_retarget: int = 0
var _target

@onready var _head: Node2D = $Head
@onready var _muzzle: Marker2D = $Head/Muzzle

func _ready() -> void:
	super._ready()
	energy_consumer = true
	_head.rotation = facing

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	## Phase 5: combat is host-only; client copies idle (fire events = Phase 6).
	if Net.is_online() and not Net.is_host():
		return
	## The Attack Range building upgrade scales range live.
	fire_range = base_range * GameState.tower_range_mult("mg_tower")
	if _target != null and is_instance_valid(_target):
		_head.rotation = (_target.global_position - global_position).angle()
	else:
		_target = null
		if _burst_left == 0:
			_head.rotation = lerp_angle(_head.rotation, facing, minf(IDLE_TURN_SPEED * delta, 1.0))
	_accum += delta
	if _burst_left > 0:
		# Mid-burst: rattle off shots on the fast interval.
		if _accum < shot_interval:
			return
		_accum = 0.0
		_shots_since_retarget += 1
		if _target == null or _shots_since_retarget >= RETARGET_EVERY:
			_shots_since_retarget = 0
			_target = Util.nearest_visible_in_group(self, "enemies", global_position, fire_range, [], true, facing, half_arc, "air_enemies")
		if _target == null:
			# Nothing left to shoot: cut the burst, keep the cooldown honest.
			_end_burst()
			return
		_head.rotation = (_target.global_position - global_position).angle()
		_burst_left -= 1
		_fire()
		if _burst_left == 0:
			_end_burst()
		return
	# Between bursts: wait out the cooldown (research speeds it up), then a
	# new burst starts only with a lit target and one energy payment upfront.
	if _accum < GameState.tower_interval("mg_tower", cooldown):
		return
	_target = Util.nearest_visible_in_group(self, "enemies", global_position, fire_range, [], true, facing, half_arc, "air_enemies")
	if _target == null:
		# Failed acquisition: back the accumulator off so the lit-target scan
		# retries ~10x/s instead of every frame while the tower sits idle.
		_accum = GameState.tower_interval("mg_tower", cooldown) - 0.1
		return
	if grid_powered() and GameState.try_spend_energy(energy_per_burst):
		set_powered(true)
		_accum = 0.0
		_burst_left = burst_size
		_burst_first = true
		_shots_since_retarget = 0
	else:
		set_powered(false)

func _fire() -> void:
	var bullet = bullet_scene.instantiate()
	bullet.global_position = _muzzle.global_position
	bullet.rotation = _head.global_rotation + randf_range(-SPRAY, SPRAY)
	var dmg := damage_base + GameState.tower_damage_bonus("mg_tower")
	if randf() < GameState.tower_crit_chance("mg_tower"):
		dmg = int(ceil(dmg * GameState.tower_crit_mult("mg_tower")))
		bullet.crit = true
	bullet.damage = dmg
	# Tower bullets fly over deposits (mask without 16) — otherwise an ore
	# block in the firing line eats shots and mints free crystal — and skip
	# air (layer 64): only the AA flak cannon engages air units.
	bullet.collision_mask = 2
	get_tree().current_scene.add_child(bullet)
	Effects.muzzle_flash(self, _muzzle.global_position, _head.global_rotation)
	# Burst shape: heavy first-round thump, quieter rattle behind it.
	if _burst_first:
		_burst_first = false
		Sfx.play("shoot_heavy", _muzzle.global_position, -10.0)
		FxEvents.tower_fire(self, 0, _muzzle.global_position, bullet.rotation)
	else:
		Sfx.play("shoot", _muzzle.global_position, -14.0)
		FxEvents.tower_fire(self, 1, _muzzle.global_position, bullet.rotation)

## Both burst exits (ammo out, target lost) land here: mechanical wind-down.
func _end_burst() -> void:
	_burst_left = 0
	Sfx.play("mg_tail", _muzzle.global_position, -10.0)
	FxEvents.tower_fire(self, 2, _muzzle.global_position, _head.global_rotation)
