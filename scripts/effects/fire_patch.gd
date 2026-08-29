class_name FirePatch
extends Node2D
## Individual burning ground fire left where a flame glob lands: a few licking
## flame tongues + occasional ember pops over a charred decal, a flickering
## fire light that also reveals bugs for lit-gated towers, and damage ticks
## that IGNITE their victims (fire DoT, see enemy.ignite). Fires never stack:
## ignite_at() merges nearby requests into a refresh of the existing patch and
## holds a global cap, so massed flame towers read as distinct campfire-like
## flames instead of one merged carpet.

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
var _char_left: float = -1.0       ## >= 0 once burnt out: char decal linger
var _char_total: float = 2.0
var _size: float = randf_range(0.85, 1.2)
var _phase: float = randf() * TAU  ## per-patch flicker phase
var _char: Node2D
var _bed: Polygon2D
var _flames: CPUParticles2D
var _embers: CPUParticles2D
var _light: PointLight2D

## Single entry point for setting ground on fire. A request within
## fire/patch_merge_radius of a live patch REFRESHES it (max footprint wins)
## instead of stacking a second node; beyond fire/patch_cap live fires the
## oldest ones are burnt out early. Returns the live patch (or null).
static func ignite_at(spawner: Node, pos: Vector2, cosmetic_patch := false, patch_radius := -1.0):
	var tree = spawner.get_tree()
	if tree == null or tree.current_scene == null:
		return null
	var merge_radius: float = Balance.num("fire/patch_merge_radius", 28.0)
	var live = tree.get_nodes_in_group("fire_patches")
	for existing in live:
		if is_instance_valid(existing) and existing.global_position.distance_to(pos) <= merge_radius:
			existing.refresh(patch_radius)
			return existing
	## Global cap: get_nodes_in_group returns tree order == spawn order, so
	## the front of the list holds the oldest fires.
	var cap: int = Balance.inum("fire/patch_cap", 60)
	var overflow := live.size() + 1 - cap
	for i in maxi(overflow, 0):
		if is_instance_valid(live[i]):
			live[i].burn_out()
	var patch = FirePatch.new()
	patch.cosmetic = cosmetic_patch
	if patch_radius > 0.0:
		patch.radius = patch_radius
	patch.global_position = pos
	tree.current_scene.add_child(patch)
	return patch

func _ready() -> void:
	add_to_group("fire_patches")
	add_to_group("light_sources")
	## Charred ground beneath the fire; lingers after the flames die. Decals
	## get a random spin — the emitters stay unrotated so flames rise up.
	var spin := randf() * TAU
	_char = Node2D.new()
	_char.rotation = spin
	var scorch := Polygon2D.new()
	scorch.polygon = _ring_points(radius * 0.7 * _size)
	scorch.color = Color(0.1, 0.06, 0.04, 0.75)
	_char.add_child(scorch)
	add_child(_char)
	## Glowing ember bed under the tongues.
	_bed = Polygon2D.new()
	_bed.polygon = _ring_points(radius * 0.42 * _size)
	_bed.rotation = spin
	_bed.color = Color(0.95, 0.4, 0.1, 0.4)
	add_child(_bed)
	## Licking tongues: few particles — motion + light carry the read, not
	## particle mass (the horde budget matters more than fidelity).
	_flames = CPUParticles2D.new()
	_flames.amount = 9
	_flames.lifetime = 0.55
	_flames.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_flames.emission_sphere_radius = radius * 0.45 * _size
	_flames.direction = Vector2(0, -1)
	_flames.spread = 12.0
	_flames.gravity = Vector2(0, -85)
	_flames.initial_velocity_min = 10.0
	_flames.initial_velocity_max = 26.0
	_flames.scale_amount_min = 3.0 * _size
	_flames.scale_amount_max = 5.5 * _size
	_flames.color_ramp = Effects.fire_gradient()
	_flames.emitting = true
	add_child(_flames)
	## Occasional ember pops climbing out of the fire.
	_embers = CPUParticles2D.new()
	_embers.amount = 3
	_embers.lifetime = 0.9
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_embers.emission_sphere_radius = radius * 0.3 * _size
	_embers.direction = Vector2(0, -1)
	_embers.spread = 30.0
	_embers.gravity = Vector2(0, -120)
	_embers.initial_velocity_min = 20.0
	_embers.initial_velocity_max = 55.0
	_embers.scale_amount_min = 1.0
	_embers.scale_amount_max = 1.8
	_embers.color_ramp = Effects.ember_gradient()
	_embers.emitting = true
	add_child(_embers)
	## Fire glow that doubles as night vision for the towers.
	_light = PointLight2D.new()
	_light.texture = Effects.fire_light_texture()
	_light.texture_scale = LIGHT_RADIUS * 2.0 / 64.0 * _size
	_light.energy = LIGHT_ENERGY
	add_child(_light)

func _physics_process(delta: float) -> void:
	## Char-only afterlife: nothing burns anymore, the scorch fades out.
	if _char_left >= 0.0:
		_char_left -= delta
		if _char_left <= 0.0:
			queue_free()
			return
		_char.modulate.a = minf(_char_left / _char_total, 1.0)
		return
	_time += delta
	if _time >= lifetime:
		burn_out()
		return
	var fade := minf((lifetime - _time) / FADE_TIME, 1.0)
	if fade < 1.0:
		_flames.modulate.a = fade
		_embers.modulate.a = fade
		_bed.modulate.a = fade
		_flames.emitting = false
		_embers.emitting = false
	## Soft flicker: slow sine breathing plus per-frame noise jitter.
	_light.energy = LIGHT_ENERGY * fade * (0.82 + 0.13 * sin(_time * 9.0 + _phase) + randf_range(-0.07, 0.07))
	if cosmetic:
		return
	_tick_accum += delta
	if _tick_accum >= tick_interval:
		_tick_accum = 0.0
		_tick_damage()

## Same spirit as the old contact cone: the tower damage bonus applies at
## full value per second, spread over ticks. Periodic group scan, never
## per frame — 350 alive enemies is the budget ceiling. Victims also catch
## fire (DoT keeps ticking after they waddle out).
func _tick_damage() -> void:
	@warning_ignore("integer_division")
	var damage := maxi(tick_damage_base + GameState.tower_damage_bonus() / 4, 1)
	if randf() < GameState.tower_crit_chance():
		damage = int(ceil(damage * GameState.tower_crit_mult()))
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(global_position) <= radius and enemy.has_method("take_damage"):
			enemy.take_damage(damage)
			if enemy.has_method("ignite"):
				enemy.ignite()

## Vision check used by Util.is_lit: anything standing in the fire is lit.
## A charring (burnt-out) patch gives no light and no vision.
func covers(pos: Vector2) -> bool:
	return _char_left < 0.0 and global_position.distance_to(pos) <= LIGHT_RADIUS

## Flames die: leave only the charred ground for fire/char_linger seconds.
## Also the cap path — the oldest fire is burnt out early, never popped.
## Leaves both groups immediately so dedupe/cap/vision only track live fires.
func burn_out() -> void:
	if _char_left >= 0.0:
		return
	_char_total = maxf(Balance.num("fire/char_linger", 2.0), 0.05)
	_char_left = _char_total
	remove_from_group("fire_patches")
	remove_from_group("light_sources")
	_flames.emitting = false
	_embers.emitting = false
	_bed.visible = false
	_light.visible = false

## A glob landing on an already-burning spot rekindles it instead of
## stacking a second patch (overlapping patches would multiply the DoT);
## the bigger footprint wins.
func refresh(new_radius := -1.0) -> void:
	_time = 0.0
	_flames.modulate.a = 1.0
	_embers.modulate.a = 1.0
	_bed.modulate.a = 1.0
	_flames.emitting = true
	_embers.emitting = true
	if new_radius > radius:
		radius = new_radius
		_flames.emission_sphere_radius = radius * 0.45 * _size

func _ring_points(r: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 8:
		points.append(Vector2.from_angle(TAU * i / 8) * r * randf_range(0.8, 1.15))
	return points
