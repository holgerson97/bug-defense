class_name Effects
extends RefCounted
## Static helpers to spawn self-freeing combat effects into the current scene.
## Callers pass themselves (any node in the tree) so effects are never
## parented to something that may be freed on the same frame.

const ONE_SHOT_EFFECT = preload("res://scripts/effects/one_shot_effect.gd")
const MUZZLE_FLASH_SCENE = preload("res://scenes/effects/muzzle_flash.tscn")
const IMPACT_SCENE = preload("res://scenes/effects/impact.tscn")
const BLOOD_SCENE = preload("res://scenes/effects/blood_burst.tscn")
const DEBRIS_SCENE = preload("res://scenes/effects/debris_burst.tscn")
const EXPLOSION_SCENE = preload("res://scenes/effects/explosion.tscn")

const DEATH_BLOOD_AMOUNT := 26
const MAX_SPLATTERS := 150
const SPLAT_GROUP := "blood_splats"

## Tesla bolt styling, shared by the host's real zap and the Phase 6 replay.
const BOLT_LIFETIME := 0.15
const BOLT_SEGMENT := 18.0
const BOLT_JITTER := 7.0
const BOLT_COLOR := Color(0.75, 0.95, 1.0, 0.9)
const BOLT_CORE_COLOR := Color(0.95, 1.0, 1.0, 0.95)

static var _bolt_light_texture: GradientTexture2D

## Shared fire resources: every flame in the scene (burning enemies, ground
## patches, glob trails) pulls the SAME texture/gradient objects — built once,
## never per node, so massed fires cost no extra resource churn.
static var _fire_light_texture: GradientTexture2D
static var _fire_gradient: Gradient
static var _ember_gradient: Gradient

static func fire_light_texture() -> GradientTexture2D:
	if _fire_light_texture == null:
		_fire_light_texture = radial_light_texture(Color(1.0, 0.65, 0.3, 1.0), Color(1.0, 0.45, 0.15, 0.0))
	return _fire_light_texture

## Flame particle ramp: yellow core -> red-orange -> smoke-dark tips.
static func fire_gradient() -> Gradient:
	if _fire_gradient == null:
		_fire_gradient = Gradient.new()
		_fire_gradient.offsets = PackedFloat32Array([0.0, 0.4, 0.8, 1.0])
		_fire_gradient.colors = PackedColorArray([
			Color(1.0, 0.92, 0.5, 0.95),
			Color(1.0, 0.45, 0.1, 0.7),
			Color(0.45, 0.12, 0.05, 0.35),
			Color(0.12, 0.08, 0.07, 0.0),
		])
	return _fire_gradient

## Ember spark ramp: hot pinpoints that wink out.
static func ember_gradient() -> Gradient:
	if _ember_gradient == null:
		_ember_gradient = Gradient.new()
		_ember_gradient.offsets = PackedFloat32Array([0.0, 1.0])
		_ember_gradient.colors = PackedColorArray([
			Color(1.0, 0.85, 0.4, 1.0),
			Color(1.0, 0.4, 0.1, 0.0),
		])
	return _ember_gradient

static func muzzle_flash(node, pos: Vector2, rot: float) -> void:
	_spawn(node, MUZZLE_FLASH_SCENE.instantiate(), pos, rot)

static func impact(node, pos: Vector2, rot: float) -> void:
	_spawn(node, IMPACT_SCENE.instantiate(), pos, rot)

## Blood-free destruction burst for buildings.
static func debris_burst(node, pos: Vector2) -> void:
	_spawn(node, DEBRIS_SCENE.instantiate(), pos, 0.0)

## Orange explosion burst with a brief light flash.
static func explosion(node, pos: Vector2) -> void:
	_spawn(node, EXPLOSION_SCENE.instantiate(), pos, 0.0)

static func blood_hit(node, pos: Vector2, dir: Vector2) -> void:
	_spawn(node, BLOOD_SCENE.instantiate(), pos, dir.angle())

static func blood_death(node, pos: Vector2, dir: Vector2) -> void:
	var burst = BLOOD_SCENE.instantiate()
	burst.amount = DEATH_BLOOD_AMOUNT
	_spawn(node, burst, pos, dir.angle())
	_splatter(node, pos)

## Small radial gradient texture for PointLight2D glows. Light diameter
## on screen is `size` x texture_scale.
static func radial_light_texture(inner: Color, outer: Color, size: int = 64) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([inner, outer])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = size
	tex.height = size
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return tex

## Tesla chain lightning: one self-freeing node holding every jagged chain
## segment (outer glow + bright core) plus a brief coil flash light.
## Extracted from tesla_tower so client event replay draws the same bolt.
static func tesla_bolts(node, points: PackedVector2Array) -> void:
	if points.size() < 2:
		return
	var tree = node.get_tree()
	var scene = tree.current_scene if tree != null else null
	if scene == null:
		return
	if _bolt_light_texture == null:
		_bolt_light_texture = radial_light_texture(Color(0.7, 0.95, 1.0, 1.0), Color(0.7, 0.95, 1.0, 0.0))
	var fx := Node2D.new()
	fx.set_script(ONE_SHOT_EFFECT)
	fx.life = BOLT_LIFETIME
	fx.light_time = BOLT_LIFETIME
	fx.global_position = points[0]
	fx.z_index = 40
	for i in points.size() - 1:
		var from: Vector2 = points[i] - points[0]
		var to: Vector2 = points[i + 1] - points[0]
		var bolt := Line2D.new()
		bolt.points = _jagged_points(from, to)
		bolt.width = 2.5
		bolt.default_color = BOLT_COLOR
		fx.add_child(bolt)
		var core := Line2D.new()
		core.points = bolt.points
		core.width = 1.0
		core.default_color = BOLT_CORE_COLOR
		fx.add_child(core)
	var light := PointLight2D.new()
	light.name = "Light"
	light.color = Color(0.7, 0.95, 1.0)
	light.energy = 2.0
	light.texture = _bolt_light_texture
	light.texture_scale = 2.8
	fx.add_child(light)
	scene.add_child(fx)

static func _jagged_points(from: Vector2, to: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array([from])
	var segments := maxi(int(from.distance_to(to) / BOLT_SEGMENT), 2)
	var normal := (to - from).normalized().orthogonal()
	for i in range(1, segments):
		points.append(from.lerp(to, float(i) / segments) + normal * randf_range(-BOLT_JITTER, BOLT_JITTER))
	points.append(to)
	return points

static func _spawn(node, fx, pos: Vector2, rot: float) -> void:
	var tree = node.get_tree()
	var scene = tree.current_scene if tree != null else null
	if scene == null:
		fx.free()
		return
	fx.position = pos
	fx.rotation = rot
	scene.add_child(fx)

## Persistent ground splatter: a few cheap static polygons, capped globally.
static func _splatter(node, pos: Vector2) -> void:
	var tree = node.get_tree()
	if tree == null or tree.current_scene == null:
		return
	var scene = tree.current_scene
	var parent = scene.get_node_or_null("SplatterLayer")
	if parent == null:
		parent = scene
	var splat := Node2D.new()
	splat.position = pos
	splat.rotation = randf() * TAU
	splat.add_to_group(SPLAT_GROUP)
	for i in randi_range(3, 5):
		var blob := Polygon2D.new()
		blob.polygon = _blob_points(randf_range(3.0, 8.0))
		blob.position = Vector2(randf_range(-14.0, 14.0), randf_range(-14.0, 14.0))
		blob.color = Color(randf_range(0.28, 0.42), 0.03, 0.05, randf_range(0.55, 0.85))
		splat.add_child(blob)
	parent.add_child(splat)
	var splats = tree.get_nodes_in_group(SPLAT_GROUP)
	while splats.size() > MAX_SPLATTERS:
		var oldest = splats.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

static func _blob_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := randi_range(5, 7)
	for i in count:
		var angle := TAU * i / count
		points.append(Vector2.from_angle(angle) * radius * randf_range(0.6, 1.4))
	return points
