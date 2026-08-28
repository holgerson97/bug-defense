extends Node2D
## Burning ground patch left where a flame glob lands: ticks damage on
## enemies standing inside, glows with a flickering fire light that also
## reveals bugs for lit-gated towers, fades out over its last second.

const FADE_TIME := 1.0
const LIGHT_RADIUS := 70.0
const LIGHT_ENERGY := 0.9

var radius: float = Balance.num("towers/flame_tower/patch_radius", 48.0)
var lifetime: float = Balance.num("towers/flame_tower/patch_lifetime", 3.5)
var tick_interval: float = Balance.num("towers/flame_tower/patch_tick_interval", 0.5)
var tick_damage_base: int = Balance.inum("towers/flame_tower/damage", 1)

## Phase 6 client replay: skip damage ticking only — visuals, light and the
## light_sources group join stay identical (client vision feeds nothing;
## towers idle there, so the group join causes no divergence).
var cosmetic := false

var _time: float = 0.0
var _tick_accum: float = 0.0
var _flames: CPUParticles2D
var _light: PointLight2D

func _ready() -> void:
	## Scorched ground so the fire reads as sitting on the floor.
	var scorch := Polygon2D.new()
	scorch.polygon = _ring_points(radius * 0.7)
	scorch.color = Color(0.12, 0.07, 0.04, 0.7)
	add_child(scorch)
	var embers := Polygon2D.new()
	embers.polygon = _ring_points(radius * 0.45)
	embers.color = Color(0.9, 0.35, 0.08, 0.35)
	add_child(embers)
	## Low-count flames: the horde budget matters more than fidelity.
	_flames = CPUParticles2D.new()
	_flames.amount = 12
	_flames.lifetime = 0.6
	_flames.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_flames.emission_sphere_radius = radius * 0.75
	_flames.direction = Vector2(0, -1)
	_flames.spread = 15.0
	_flames.gravity = Vector2(0, -70)
	_flames.initial_velocity_min = 8.0
	_flames.initial_velocity_max = 24.0
	_flames.scale_amount_min = 3.0
	_flames.scale_amount_max = 6.0
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.9, 0.45, 0.9),
		Color(1.0, 0.45, 0.1, 0.65),
		Color(0.3, 0.08, 0.04, 0.0),
	])
	_flames.color_ramp = gradient
	_flames.emitting = true
	add_child(_flames)
	## Fire glow that doubles as night vision for the towers.
	_light = PointLight2D.new()
	_light.texture = Effects.radial_light_texture(Color(1.0, 0.65, 0.3, 1.0), Color(1.0, 0.45, 0.15, 0.0))
	_light.texture_scale = LIGHT_RADIUS * 2.0 / 64.0
	_light.energy = LIGHT_ENERGY
	add_child(_light)
	add_to_group("light_sources")

func _physics_process(delta: float) -> void:
	_time += delta
	if _time >= lifetime:
		queue_free()
		return
	var fade := minf((lifetime - _time) / FADE_TIME, 1.0)
	if fade < 1.0:
		modulate.a = fade
		_flames.emitting = false
	## Cheap flicker: the light jitters a little every physics frame.
	_light.energy = LIGHT_ENERGY * fade * randf_range(0.82, 1.12)
	_tick_accum += delta
	if _tick_accum >= tick_interval:
		_tick_accum = 0.0
		_tick_damage()

## Same spirit as the old contact cone: the tower damage bonus applies at
## full value per second, spread over ticks. Periodic group scan, never
## per frame — 350 alive enemies is the budget ceiling.
func _tick_damage() -> void:
	if cosmetic:
		return
	@warning_ignore("integer_division")
	var damage := maxi(tick_damage_base + GameState.tower_damage_bonus() / 4, 1)
	if randf() < GameState.tower_crit_chance():
		damage = int(ceil(damage * GameState.tower_crit_mult()))
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(global_position) <= radius and enemy.has_method("take_damage"):
			enemy.take_damage(damage)

## Vision check used by Util.is_lit: anything standing in the fire is lit.
func covers(pos: Vector2) -> bool:
	return global_position.distance_to(pos) <= LIGHT_RADIUS

## Patch-cap control: the owning tower cuts the oldest patch short.
func force_fade() -> void:
	_time = maxf(_time, lifetime - FADE_TIME)

## A glob landing on an already-burning spot rekindles it instead of
## stacking a second patch (overlapping patches would multiply the DoT).
func refresh() -> void:
	_time = 0.0
	modulate.a = 1.0
	_flames.emitting = true

func _ring_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 8:
		points.append(Vector2.from_angle(TAU * i / 8) * radius * randf_range(0.8, 1.15))
	return points
