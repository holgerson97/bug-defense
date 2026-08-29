extends "res://scripts/building.gd"
## Flamethrower tower: rotates its nozzle toward the nearest lit enemy in
## its facing arc and lobs burning globs into the enemy line. Each glob
## splashes damage on impact and leaves a fire patch that keeps burning
## the ground for a few seconds. Enemies can waddle out — that is the
## counterplay.

const TURN_SPEED := 8.0
const RETARGET_INTERVAL := 0.1
const FLARE_TIME := 0.18
const NOZZLE_LENGTH := 25.0

var throw_interval: float = Balance.num("towers/flame_tower/interval", 0.9)
var energy_per_throw: int = Balance.inum("towers/flame_tower/energy_per_throw", 1)
var base_range: float = GameState.BUILDINGS["flame_tower"]["range"]
var fire_range: float = base_range
var half_arc: float = deg_to_rad(GameState.BUILDINGS["flame_tower"]["arc"]) / 2.0
var _throw_accum: float = 0.0
var _retarget_accum: float = RETARGET_INTERVAL
var _flare: float = 0.0
var _target

@onready var _nozzle: Node2D = $Nozzle
@onready var _jet: CPUParticles2D = $Nozzle/Jet

func _ready() -> void:
	super._ready()
	energy_consumer = true
	_nozzle.rotation = facing

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	## Jet is a short muzzle flare on each throw; it runs above the puppet
	## gate because Phase 6 glob events set _flare on clients too.
	_flare -= delta
	_jet.emitting = _flare > 0.0
	## Phase 5: combat is host-only; client copies idle (fire events replay
	## the glob/nozzle cosmetically via FxEvents).
	if Net.is_online() and not Net.is_host():
		return
	## Extended Barrels research scales range live.
	fire_range = base_range * GameState.tower_range_mult()
	# The lit-target scan walks every enemy x every light source — with horde
	# waves that is too hot for every frame, so re-scan strictly on the
	# interval; a null/freed target must not defeat the throttle.
	if _target != null and not is_instance_valid(_target):
		_target = null
	_retarget_accum += delta
	if _retarget_accum >= RETARGET_INTERVAL:
		_retarget_accum = 0.0
		_target = Util.nearest_visible_in_group(self, "enemies", global_position, fire_range, [], true, facing, half_arc)
	var target = _target
	if target == null:
		_nozzle.rotation = lerp_angle(_nozzle.rotation, facing, minf(TURN_SPEED * delta, 1.0))
		return
	var aim: float = (target.global_position - global_position).angle()
	_nozzle.rotation = lerp_angle(_nozzle.rotation, aim, minf(TURN_SPEED * delta, 1.0))
	_throw_accum += delta
	if _throw_accum < GameState.tower_interval(throw_interval):
		return
	## Starved nozzle: keep the accumulator full and retry every frame.
	if not grid_powered() or not GameState.try_spend_energy(energy_per_throw):
		set_powered(false)
		return
	set_powered(true)
	_throw_accum = 0.0
	_throw(target)

## Lob a glob at the target, leading slightly so waddlers walk into it.
func _throw(target) -> void:
	var point: Vector2 = target.global_position
	if "velocity" in target:
		point += target.velocity * FireGlob.FLIGHT_TIME * 0.8
	point = global_position + (point - global_position).limit_length(fire_range)
	var glob := FireGlob.new()
	glob.global_position = global_position + Vector2.from_angle(_nozzle.global_rotation) * NOZZLE_LENGTH
	glob.target_point = point
	get_tree().current_scene.add_child(glob)
	_flare = FLARE_TIME
	Sfx.play("flame", global_position, -14.0)
	FxEvents.flame_glob(self, glob.global_position, point)

## Small flaming projectile: grenade-style fake arc flight, splash on
## landing, then a lingering fire patch. Built in code so night lighting
## (own tiny light + world-space ember trail) stays self-contained.
class FireGlob extends Node2D:
	const FIRE_PATCH := preload("res://scripts/effects/fire_patch.gd")
	const FLIGHT_TIME := 0.45

	var splash_radius: float = Balance.num("towers/flame_tower/splash_radius", 40.0)
	var splash_mult: int = Balance.inum("towers/flame_tower/splash_mult", 2)
	var damage_base: int = Balance.inum("towers/flame_tower/damage", 1)
	var target_point: Vector2
	## Phase 6 client replay: no damage on land; the patch spawns with its
	## damage ticking disabled (visual + light only).
	var cosmetic := false
	var _start: Vector2
	var _time: float = 0.0

	func _ready() -> void:
		z_index = 30
		_start = global_position
		var body := Polygon2D.new()
		body.polygon = _circle_points(4.5)
		body.color = Color(1.0, 0.5, 0.12, 1.0)
		add_child(body)
		var core := Polygon2D.new()
		core.polygon = _circle_points(2.2)
		core.color = Color(1.0, 0.9, 0.55, 1.0)
		add_child(core)
		var trail := CPUParticles2D.new()
		trail.amount = 10
		trail.lifetime = 0.3
		trail.local_coords = false
		trail.spread = 180.0
		trail.gravity = Vector2.ZERO
		trail.initial_velocity_min = 5.0
		trail.initial_velocity_max = 20.0
		trail.scale_amount_min = 2.0
		trail.scale_amount_max = 4.0
		## Shared fire ramp: same yellow->red-orange->smoke look as the ground
		## fires and burning enemies (one Gradient object for all of them).
		trail.color_ramp = Effects.fire_gradient()
		trail.emitting = true
		add_child(trail)
		## Tiny own light so the glob is visible against the night.
		var light := PointLight2D.new()
		light.texture = Effects.fire_light_texture()
		light.texture_scale = 1.0
		light.energy = 1.2
		add_child(light)

	func _physics_process(delta: float) -> void:
		_time += delta
		var t := minf(_time / FLIGHT_TIME, 1.0)
		global_position = _start.lerp(target_point, t)
		## Fake arc plus a slight burning pulse so the glob shimmers in flight.
		var arc := (1.0 + 0.6 * sin(t * PI)) * randf_range(0.94, 1.06)
		scale = Vector2(arc, arc)
		if t >= 1.0:
			_land()

	## Punchy landing: small splash at double the patch tick damage that also
	## sets the victims on fire, then the ground catches fire. Dedupe, merge
	## and the global cap all live in FirePatch.ignite_at.
	func _land() -> void:
		if not cosmetic:
			@warning_ignore("integer_division")
			var damage := maxi(damage_base + GameState.tower_damage_bonus() / 4, 1) * splash_mult
			if randf() < GameState.tower_crit_chance():
				damage = int(ceil(damage * GameState.tower_crit_mult()))
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if enemy.global_position.distance_to(global_position) <= splash_radius and enemy.has_method("take_damage"):
					enemy.take_damage(damage)
					if enemy.has_method("ignite"):
						enemy.ignite()
		FIRE_PATCH.ignite_at(self, global_position, cosmetic)
		queue_free()

	func _circle_points(radius: float) -> PackedVector2Array:
		var points := PackedVector2Array()
		for i in 8:
			points.append(Vector2.from_angle(TAU * i / 8) * radius)
		return points
