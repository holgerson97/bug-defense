extends RefCounted
## Static helpers to spawn self-freeing combat effects into the current scene.
## Callers pass themselves (any node in the tree) so effects are never
## parented to something that may be freed on the same frame.

const MUZZLE_FLASH_SCENE = preload("res://scenes/effects/muzzle_flash.tscn")
const IMPACT_SCENE = preload("res://scenes/effects/impact.tscn")
const BLOOD_SCENE = preload("res://scenes/effects/blood_burst.tscn")
const DEBRIS_SCENE = preload("res://scenes/effects/debris_burst.tscn")
const EXPLOSION_SCENE = preload("res://scenes/effects/explosion.tscn")

const DEATH_BLOOD_AMOUNT := 26
const MAX_SPLATTERS := 150
const SPLAT_GROUP := "blood_splats"

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
