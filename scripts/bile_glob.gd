extends Node2D
## Bile glob lobbed by hive bile spires: grenade-pattern arc (lerp to the
## target point, fake height via scaling) with a small AoE splash that damages
## BOTH players and player buildings. Host spawns the real glob; clients get a
## cosmetic replay via the hive site's RPC. Self-freeing.

const FLIGHT_TIME := 0.9

var target_point := Vector2.ZERO
var cosmetic := false
var damage: int = Balance.inum("hive/glob_damage", 8)
var radius: float = Balance.num("hive/glob_radius", 50.0)
## Building positions are footprint centers; extend reach by a half-size.
const BUILDING_REACH := 24.0

var _start := Vector2.ZERO
var _time: float = 0.0

func _ready() -> void:
	_start = global_position
	z_index = 10
	var body := Polygon2D.new()
	body.polygon = _blob(6.0)
	body.color = Color(0.5, 0.85, 0.25, 1.0)
	add_child(body)
	var core := Polygon2D.new()
	core.polygon = _blob(3.0)
	core.position = Vector2(-1.0, -1.5)
	core.color = Color(0.75, 0.95, 0.5, 0.9)
	add_child(core)

func _blob(r: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 8:
		points.append(Vector2.from_angle(TAU * i / 8.0) * r * randf_range(0.8, 1.2))
	return points

func _physics_process(delta: float) -> void:
	_time += delta
	var t := minf(_time / FLIGHT_TIME, 1.0)
	global_position = _start.lerp(target_point, t)
	var arc := 1.0 + 0.9 * sin(t * PI)
	scale = Vector2(arc, arc)
	if t >= 1.0:
		_explode()

func _explode() -> void:
	if not cosmetic:
		for p in get_tree().get_nodes_in_group("player"):
			if p.global_position.distance_to(global_position) <= radius:
				## Host-side: player.take_damage routes puppet hits to the
				## owning peer itself (enemy-melee pattern).
				p.take_damage(damage)
		for b in get_tree().get_nodes_in_group("buildings"):
			if b.global_position.distance_to(global_position) <= radius + BUILDING_REACH:
				b.take_damage(damage)
	_splash_fx()
	Sfx.play("hit", global_position, -6.0)
	queue_free()

## Green splash: one-shot particle burst on the shared self-freeing effect.
func _splash_fx() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	var fx := Node2D.new()
	fx.set_script(Effects.ONE_SHOT_EFFECT)
	fx.life = 0.55
	var p := CPUParticles2D.new()
	p.emitting = false
	p.amount = 14
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 160.0
	p.damping_min = 200.0
	p.damping_max = 350.0
	p.scale_amount_min = 2.5
	p.scale_amount_max = 5.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([Color(0.55, 0.9, 0.3, 0.95), Color(0.2, 0.45, 0.1, 0.0)])
	p.color_ramp = ramp
	fx.add_child(p)
	fx.position = global_position
	scene.add_child(fx)
