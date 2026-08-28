extends "res://scripts/building.gd"
## Flamethrower tower: rotates its nozzle toward the nearest enemy and
## sprays a burning cone, ticking damage on every enemy inside the arc.

const CONE_HALF_ANGLE := deg_to_rad(35.0)
const TICK_INTERVAL := 0.25
const TICK_DAMAGE := 1
const SOUND_INTERVAL := 0.5
const TURN_SPEED := 8.0
const ENERGY_INTERVAL := 0.5
const ENERGY_PER_INTERVAL := 1

var fire_range: float = GameState.BUILDINGS["flame_tower"]["range"]
var _tick_accum: float = 0.0
var _sound_accum: float = SOUND_INTERVAL
var _energy_accum: float = 0.0

@onready var _nozzle: Node2D = $Nozzle
@onready var _jet: CPUParticles2D = $Nozzle/Jet

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	var target = Util.nearest_in_group(self, "enemies", global_position, fire_range, [], true)
	if target == null:
		_jet.emitting = false
		_tick_accum = 0.0
		_sound_accum = SOUND_INTERVAL
		_energy_accum = 0.0
		return
	var aim: float = (target.global_position - global_position).angle()
	_nozzle.rotation = lerp_angle(_nozzle.rotation, aim, minf(TURN_SPEED * delta, 1.0))
	# Starved nozzle: retry the spend every frame; stay dark until it succeeds.
	if not _powered:
		if GameState.try_spend_energy(ENERGY_PER_INTERVAL):
			set_powered(true)
			_energy_accum = 0.0
		else:
			_jet.emitting = false
			_tick_accum = 0.0
			_sound_accum = SOUND_INTERVAL
			return
	# Continuous spray drains 1 energy per half second of nozzle-on time.
	_energy_accum += delta
	if _energy_accum >= ENERGY_INTERVAL:
		_energy_accum -= ENERGY_INTERVAL
		if not GameState.try_spend_energy(ENERGY_PER_INTERVAL):
			set_powered(false)
			_jet.emitting = false
			return
	_jet.emitting = true
	_tick_accum += delta
	if _tick_accum >= GameState.tower_interval(TICK_INTERVAL):
		_tick_accum = 0.0
		_burn()
	_sound_accum += delta
	if _sound_accum >= SOUND_INTERVAL:
		_sound_accum = 0.0
		Sfx.play("flame", global_position, -14.0)

## The tower damage bonus applies at full value per second, spread over ticks.
func _burn() -> void:
	@warning_ignore("integer_division")
	var damage := maxi(TICK_DAMAGE + GameState.tower_damage_bonus() / 4, 1)
	if randf() < GameState.tower_crit_chance():
		damage = int(ceil(damage * GameState.tower_crit_mult()))
	var nozzle_dir := Vector2.from_angle(_nozzle.global_rotation)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > fire_range:
			continue
		if absf(nozzle_dir.angle_to(to_enemy)) > CONE_HALF_ANGLE:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage)
