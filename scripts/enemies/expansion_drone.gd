extends "res://scripts/enemy.gd"
## Expansion drone: fat larva-carrier the hive sends out every few waves
## (hive_site._try_expand). It never fights — it crawls to a host-chosen spot
## ("dest" spawn override), burrows for morph_time seconds (pulsing, still
## killable) and founds a YOUNG hive site there. Spawned through the wave
## manager's uncounted replicated path, so towers/players on every peer see
## it; killing it cancels that expansion and pays the bounty once (base
## take_damage flow). The node is spawner-replicated ("E<id>" on every peer),
## so the founding decision mirrors host->clients via RPCs on the drone
## itself, the same node-resolution trick as hive_site's combat mirror.

const HIVE_SITE := preload("res://scripts/hive_site.gd")

const ARRIVE_DIST := 30.0

## Target-shaped stand-in: the base chase AI needs _target.global_position,
## but the drone walks to a POINT, not a node.
class Goal:
	extends RefCounted
	var global_position := Vector2.ZERO

var dest := Vector2.ZERO           ## expansion spot (host-rolled, replicated)
var morph_time: float = Balance.num("hive/morph_time", 4.0)

var _goal = null
var _morphing := false
var _morph_left: float = 0.0
var _pulse_t: float = 0.0

@onready var _body: Sprite2D = $Body

## Balance lives under "hive/" (not "enemies/"): the drone belongs to the
## hive system. Site-passed overrides (wave-scaled HP) keep authority.
func _apply_balance() -> void:
	speed = Balance.num("hive/drone_speed", speed)
	max_health = Balance.inum("hive/drone_hp", max_health)
	scrap_value = Balance.inum("hive/drone_bounty", scrap_value)
	if spawn_overrides.has("max_health"):
		max_health = spawn_overrides["max_health"]

func _ready() -> void:
	add_to_group("expansion_drones")
	dest = spawn_overrides.get("dest", position)
	_goal = Goal.new()
	_goal.global_position = dest
	super._ready()
	rotation = (dest - global_position).angle()

## The destination is the one and only target, forever.
func _pick_target():
	return _goal

## Crawl to the spot, then burrow. Never attacks anything.
func _behave(delta) -> void:
	if _dead:
		return
	if _morphing:
		velocity = Vector2.ZERO
		_morph_left -= delta
		if _morph_left <= 0.0:
			_found_site()
		return
	var to: Vector2 = dest - global_position
	if to.length() > ARRIVE_DIST:
		_steered_move(to.normalized(), speed, delta)
		if velocity.length_squared() > 25.0:
			rotation = velocity.angle()
	else:
		_begin_morph()

## Morph pulse runs on every peer (client _morphing arrives via RPC);
## _process halts with pause, and the throb reads as "kill it NOW".
func _process(delta: float) -> void:
	if not _morphing:
		return
	_pulse_t += delta
	var throb := 1.0 + 0.14 * sin(_pulse_t * 9.0)
	if _body != null:
		_body.scale = Vector2(0.5 * throb, 0.5 * throb)
	modulate = Color(1.0, 0.78 + 0.22 * sin(_pulse_t * 6.0), 0.92)

func _begin_morph() -> void:
	_morphing = true
	_morph_left = morph_time
	velocity = Vector2.ZERO
	_steering_reset()
	if Net.is_online():
		_rpc_morph.rpc()

## Host: morph finished — found the young site everywhere, then despawn.
## The reliable RPC is queued before queue_free, so it lands before the
## spawner's despawn on the same ordered channel.
func _found_site() -> void:
	if _dead:
		return
	var sname := "Grown_%d" % sync_id
	if Net.is_online():
		_rpc_found.rpc(dest, sname)
	_spawn_site(dest, sname)
	queue_free()

## Runs on every peer. The site reseeds the global RNG from its own name in
## _ready (young path), so the layout is identical host/client no matter when
## this executes. add_child is deferred: founding happens inside the physics
## step on the host.
func _spawn_site(pos: Vector2, sname: String) -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	var hives = scene.get_node_or_null("Hives")
	if hives == null or hives.has_node(sname):
		return
	var site = HIVE_SITE.new()
	site.name = sname
	site.young = true
	site.position = pos
	hives.add_child.call_deferred(site)
	for i in 3:
		Effects.debris_burst(scene, pos + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 50.0))
	Sfx.play("explosion", pos, -10.0)

## -- host -> clients --

@rpc("authority", "call_remote", "reliable")
func _rpc_morph() -> void:
	_morphing = true

@rpc("authority", "call_remote", "reliable")
func _rpc_found(pos: Vector2, sname: String) -> void:
	_morphing = false
	_spawn_site(pos, sname)
