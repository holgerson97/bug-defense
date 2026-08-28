extends "res://scripts/building.gd"
## Tesla tower: zaps the nearest enemy, then chains lightning to nearby
## foes at half damage per hop. Bolts are self-freeing jagged Line2D flashes.

const ONE_SHOT_EFFECT = preload("res://scripts/effects/one_shot_effect.gd")

const FIRE_INTERVAL := 1.1
const FIRE_RANGE := 300.0
const ENERGY_PER_ZAP := 2
const CHAIN_RANGE := 130.0
const MAX_CHAINS := 3
const ZAP_DAMAGE := 2
const BOLT_LIFETIME := 0.15
const BOLT_SEGMENT := 18.0
const BOLT_JITTER := 7.0
const BOLT_COLOR := Color(0.75, 0.95, 1.0, 0.9)
const BOLT_CORE_COLOR := Color(0.95, 1.0, 1.0, 0.95)

var _fire_accum: float = 0.0
var _light_texture

func _ready() -> void:
	super._ready()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color(0.7, 0.95, 1.0, 1.0), Color(0.7, 0.95, 1.0, 0.0)])
	_light_texture = GradientTexture2D.new()
	_light_texture.gradient = gradient
	_light_texture.fill = GradientTexture2D.FILL_RADIAL
	_light_texture.fill_from = Vector2(0.5, 0.5)
	_light_texture.fill_to = Vector2(0.5, 0.0)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_fire_accum += delta
	if _fire_accum >= FIRE_INTERVAL:
		_fire_accum = 0.0
		_zap()

func _zap() -> void:
	var victims: Array = []
	var first = _nearest_enemy(global_position, FIRE_RANGE, victims)
	if first == null:
		return
	if not GameState.try_spend_energy(ENERGY_PER_ZAP):
		set_powered(false)
		return
	set_powered(true)
	victims.append(first)
	var link = first
	for i in MAX_CHAINS:
		var next = _nearest_enemy(link.global_position, CHAIN_RANGE, victims)
		if next == null:
			break
		victims.append(next)
		link = next
	# Capture positions before dealing damage; a kill frees the victim node.
	var points: Array = [global_position]
	var damage := ZAP_DAMAGE + GameState.tower_damage_bonus()
	for victim in victims:
		points.append(victim.global_position)
		if victim.has_method("take_damage"):
			victim.take_damage(damage)
		damage = maxi(int(ceil(damage / 2.0)), 1)
	_spawn_bolts(points)
	Sfx.play("zap", global_position, -8.0)

func _nearest_enemy(from: Vector2, radius: float, exclude: Array):
	var nearest = null
	var best := radius
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy in exclude:
			continue
		var dist: float = enemy.global_position.distance_to(from)
		if dist <= best:
			best = dist
			nearest = enemy
	return nearest

## One self-freeing effect node holding every chain segment plus a coil flash.
func _spawn_bolts(points: Array) -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
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
	light.energy = 1.6
	light.texture = _light_texture
	light.texture_scale = 2.5
	fx.add_child(light)
	scene.add_child(fx)

func _jagged_points(from: Vector2, to: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array([from])
	var segments := maxi(int(from.distance_to(to) / BOLT_SEGMENT), 2)
	var normal := (to - from).normalized().orthogonal()
	for i in range(1, segments):
		points.append(from.lerp(to, float(i) / segments) + normal * randf_range(-BOLT_JITTER, BOLT_JITTER))
	points.append(to)
	return points
