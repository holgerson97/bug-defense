extends CharacterBody2D

signal died(points: int)


@export var speed: float = 110.0
@export var max_health: int = 3
@export var damage: int = 8
@export var attack_interval: float = 0.8
@export var attack_range: float = 36.0
@export var points: int = 10
@export var scrap_value: int = 6
@export var crystal_value: int = 0

## Obstacle steering: glide along walls/rocks instead of grinding into them,
## commit to one tangent side to kill corner jitter, and stand-and-gnaw when
## a building truly blocks the way (rocks are indestructible: never stop).
const OBSTACLE_MASK := 48          ## rocks (16) | buildings (32)
const BUILDING_LAYER := 32
const GLIDE_COMMIT := 0.9          ## seconds a chosen tangent side is kept
const GLIDE_GOAL_PULL := 0.35      ## goal blend so gliders peel off at corners
const STUCK_WINDOW := 1.5          ## progress check interval
const STUCK_PROGRESS := 14.0       ## min px gained toward goal per window
const STUCK_DISPLACE := 10.0       ## min px moved at all (rock pocket check)
const CONTACT_GRACE := 0.4         ## building-contact memory; gnaw ends after
const WHISKER_TIME := 0.25         ## whisker length = speed * this

## Local pathfinding: glide handles open ground, but rock pockets (concave
## U/L/S formations) defeat reactive steering — those escalate to a windowed
## A* on the NavGrid occupancy lattice and the enemy walks the waypoints.
## Target selection: nearby buildings outdraw the player, so bases matter.
const AGGRO_RANGE := 420.0         ## building inside this -> attack it
const TARGET_REPICK := 1.0         ## seconds between target re-picks
const BUILDING_REACH := 24.0       ## approx half-size added to melee range vs buildings

const PATH_COOLDOWN := 1.5         ## min seconds between A* requests
const WAYPOINT_REACH := 20.0       ## px to consider a waypoint reached
const PATH_TARGET_DRIFT := 200.0   ## target strays this far from path end -> drop
const RESTUCK_WINDOW := 4.0        ## 2nd stuck event this close -> path even off-rock

## Stable replication id assigned by the wave manager at spawn (node name
## "E<sync_id>" on every peer); the enemy_sync batcher keys packets on it.
var sync_id: int = 0

## Balance ids: scene file basename (the same trick the sell code uses),
## with the generically-named scenes mapped to their wave-kind names.
const BALANCE_ALIASES := {"enemy": "grunt", "drone_tank": "drone", "boss_broodmother": "boss"}

## Wave-manager stat overrides, stashed BEFORE the node enters the tree.
## _ready applies Balance base stats first, then layers these on top, so wave
## scaling always beats the JSON base values (the host computes them from
## Balance anyway; on clients they make puppet max_health match the host).
var spawn_overrides: Dictionary = {}

func balance_id() -> String:
	var base := scene_file_path.get_file().get_basename()
	return str(BALANCE_ALIASES.get(base, base))

## Balance base stats by type id, then the wave manager's spawn overrides.
func _apply_balance() -> void:
	var sec = Balance.section("enemies/" + balance_id())
	max_health = Balance.inum("enemies/%s/hp" % balance_id(), max_health)
	speed = float(sec.get("speed", speed))
	damage = int(sec.get("damage", damage))
	attack_interval = float(sec.get("attack_interval", attack_interval))
	attack_range = float(sec.get("attack_range", attack_range))
	points = int(sec.get("points", points))
	scrap_value = int(sec.get("scrap", scrap_value))
	crystal_value = int(sec.get("crystal", crystal_value))
	if spawn_overrides.has("max_health"):
		max_health = spawn_overrides["max_health"]
	if spawn_overrides.has("speed_delta"):
		speed += spawn_overrides["speed_delta"]
	if spawn_overrides.has("scrap_value"):
		scrap_value = spawn_overrides["scrap_value"]

var health: int
var _attack_cooldown: float = 0.0
var _target
var _retarget_timer: float = 0.0   ## randomized phase staggers group scans
var _dead: bool = false

var _glide_sign: float = 0.0       ## +1/-1 committed tangent side, 0 = free
var _glide_timer: float = 0.0
var _surf_normal: Vector2 = Vector2.ZERO
var _stuck_timer: float = 0.0
var _stuck_ref: Vector2 = Vector2.ZERO
var _gnawing: bool = false
var _building_contact: float = 999.0   ## seconds since last building touch
var _rock_contact: float = 999.0       ## seconds since last rock touch
var _ray: PhysicsRayQueryParameters2D
var _body_radius: float = 16.0         ## collider radius (gnaw-sense ray length)

## Fire DoT: any fire damage source (flame tower globs, ground fire patches,
## Heavy flame globs) calls ignite(). The burn is HOST-simulated; clients see
## it via throttled FxEvents ignite events driving a visual-only mirror.
var _burn_left: float = 0.0        ## seconds of burn remaining (0 = not burning)
var _burn_tick_damage: int = 0
var _burn_tick_accum: float = 0.0
var _burn_bcast_cd: float = 0.0    ## re-ignite event throttle (host)
var _burn_time: float = 0.0        ## pulse/flicker clock
var _burn_fx: Node2D = null        ## flames+embers+light, child of the enemy
var _burn_light: PointLight2D = null

var _path := PackedVector2Array()  ## active waypoints (empty = pure glide)
var _path_i: int = 0
var _path_cd: float = 0.0          ## per-enemy request throttle
var _path_goal: Vector2 = Vector2.ZERO  ## target pos at request time (drift ref)
var _want_path: bool = false       ## retry latch when NavGrid budget was spent
var _since_stuck: float = 999.0    ## seconds since last stuck event

## Phase 5: online clients hold visual puppets only — the host simulates.
func _is_puppet() -> bool:
	return Net.is_online() and not Net.is_host()

func _ready() -> void:
	## Top-down: no floor snapping, walls never resolve as "slopes" to climb.
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_apply_balance()
	health = max_health
	if _is_puppet():
		## Puppet: no AI/physics; the host resolves collisions, so the local
		## shape only risks races with replicated movement — drop it.
		var shape := get_node_or_null("CollisionShape2D")
		if shape != null:
			shape.set_deferred("disabled", true)
		return
	_target = _pick_target()
	_retarget_timer = randf() * TARGET_REPICK
	_stuck_ref = global_position
	_ray = PhysicsRayQueryParameters2D.new()
	_ray.collision_mask = OBSTACLE_MASK
	var cs := get_node_or_null("CollisionShape2D")
	if cs != null and cs.shape is CircleShape2D:
		_body_radius = cs.shape.radius

func _physics_process(delta: float) -> void:
	## Burn runs above the puppet gate: visuals tick on every peer, the
	## damage inside is host-only.
	_update_burn(delta)
	## Puppets do nothing here; transforms arrive via enemy_sync. Variant
	## overrides that share _behave/_steered_move are gated by this too.
	if _is_puppet():
		return
	## Re-pick on cadence and immediately when the target died (freed building);
	## never idle on a stale target.
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or _target == null or not is_instance_valid(_target):
		_retarget_timer = TARGET_REPICK
		_target = _pick_target()
	if _target == null or not is_instance_valid(_target):
		return
	_behave(delta)

## Nearest building within AGGRO_RANGE wins; no building near -> the nearest
## player. Called ~1/s per enemy (staggered), so the group scan stays cheap.
func _pick_target():
	var best = null
	var best_sq := AGGRO_RANGE * AGGRO_RANGE
	for b in get_tree().get_nodes_in_group("buildings"):
		var sq: float = global_position.distance_squared_to(b.global_position)
		if sq < best_sq:
			best_sq = sq
			best = b
	if best != null:
		return best
	return Util.nearest_in_group(self, "player", global_position, INF)

## Melee reach vs. the current target: building positions are centers of
## 48-64px footprints, so extend by an approximate half-size.
func _target_reach() -> float:
	if _target.is_in_group("buildings"):
		return attack_range + BUILDING_REACH
	return attack_range

## Default behavior: chase the target (nearby building or player), melee-attack
## in range. Variants override.
func _behave(delta) -> void:
	var to_target: Vector2 = _target.global_position - global_position
	rotation = to_target.angle()

	if to_target.length() > _target_reach():
		_steered_move(to_target.normalized(), speed, delta)
	else:
		velocity = Vector2.ZERO
		_steering_reset()
		_attack_cooldown -= delta
		if _attack_cooldown <= 0.0:
			_target.take_damage(damage)
			_attack_cooldown = attack_interval

## Movement with obstacle steering; desired must be normalized. Glides along
## walls/rocks, commits to one side, gnaws buildings when truly blocked.
## Cost: slide-normal loop + at most one short ray every 2nd physics frame.
func _steered_move(desired: Vector2, spd: float, delta: float) -> void:
	_building_contact += delta
	_rock_contact += delta
	_since_stuck += delta
	_path_cd -= delta
	if _want_path:
		_try_request_path()
	desired = _path_desired(desired)
	if _gnawing:
		if _building_contact > CONTACT_GRACE:
			## Wall destroyed (or we drifted off): resume steering. Keep the
			## waypoints — the path was planned through this very wall.
			var keep := _path
			var keep_i := _path_i
			_steering_reset()
			_path = keep
			_path_i = keep_i
		else:
			## Stand and chew: gnaw damage comes from the building's Sense
			## area, pressing only deepens overlap — hold still instead.
			velocity = Vector2.ZERO
			_gnaw_sense()
			return
	_glide_timer -= delta
	if _glide_timer <= 0.0:
		_glide_sign = 0.0
	if not _path.is_empty():
		## Waypoints already route around the obstacle; the committed glide
		## tangent can point AWAY from the next waypoint, so while a path is
		## live the reflex layer stands down and move_and_slide skims contacts.
		_glide_sign = 0.0
		## Convex-corner deflection: aiming head-on at a rock corner vertex
		## cancels the slide to ~zero and wedges the body there. In fresh rock
		## contact, ride the tangent side TOWARD the waypoint — the sign comes
		## from `desired` every frame, so it can never fight the path.
		if _rock_contact <= delta * 2.0 and desired.dot(_surf_normal) < 0.2:
			var side := 1.0 if _surf_normal.orthogonal().dot(desired) >= 0.0 else -1.0
			desired = (_surf_normal.orthogonal() * side + desired * GLIDE_GOAL_PULL).normalized()
	elif _glide_sign != 0.0 and desired.dot(_surf_normal) > 0.3:
		## Goal is on the free side of the surface: stop hugging it.
		_glide_sign = 0.0
		_glide_timer = 0.0
	elif _glide_sign == 0.0 and (Engine.get_physics_frames() + get_instance_id()) & 1 == 0:
		_whisker(desired, spd)
	var dir := desired
	if _glide_sign != 0.0:
		## Ride the surface tangent with a light goal pull to round corners.
		dir = (_surf_normal.orthogonal() * _glide_sign + desired * GLIDE_GOAL_PULL).normalized()
	velocity = dir * spd
	move_and_slide()
	_read_contacts(desired)
	_check_stuck(desired, delta)

## One short ray ahead so the glide starts before face-planting.
func _whisker(desired: Vector2, spd: float) -> void:
	_ray.from = global_position
	_ray.to = global_position + desired * maxf(spd * WHISKER_TIME, 24.0)
	var hit := get_world_2d().direct_space_state.intersect_ray(_ray)
	if not hit.is_empty():
		_begin_glide(hit.normal, desired)

## Harvest obstacle normals from this frame's slides (ignore enemy shoves).
func _read_contacts(desired: Vector2) -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var collider := col.get_collider()
		if collider is not PhysicsBody2D:
			continue
		var layer: int = collider.collision_layer
		if layer & OBSTACLE_MASK == 0:
			continue
		_begin_glide(col.get_normal(), desired)
		if layer & BUILDING_LAYER:
			_building_contact = 0.0
			## A live path was planned through this wall: gnaw right away
			## instead of ramming out the stuck window (visible clipping).
			if not _path.is_empty():
				_gnawing = true
		else:
			## FRESH rock contact with no path: request one now instead of
			## grinding out the 1.5s stuck window (cooldown still throttles).
			if _rock_contact > CONTACT_GRACE and _path.is_empty():
				_want_path = true
			_rock_contact = 0.0

## Standing still yields no slide contacts, so while gnawing a short ray
## toward the wall keeps _building_contact fresh until it's destroyed.
func _gnaw_sense() -> void:
	_ray.from = global_position
	_ray.to = global_position - _surf_normal * (_body_radius + 12.0)
	var hit := get_world_2d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		return
	var collider = hit.collider
	if collider is PhysicsBody2D and collider.collision_layer & BUILDING_LAYER:
		_building_contact = 0.0
		_surf_normal = hit.normal

## Refresh the glide surface; pick a tangent side only when uncommitted,
## favoring the side closer to the goal bearing.
func _begin_glide(normal: Vector2, desired: Vector2) -> void:
	_surf_normal = normal
	if _glide_sign == 0.0:
		_glide_sign = 1.0 if normal.orthogonal().dot(desired) >= 0.0 else -1.0
	_glide_timer = GLIDE_COMMIT

## Every STUCK_WINDOW seconds: no real progress toward the goal while touching
## a building -> stand and gnaw. Blocked by rock, repeatedly stuck, or stuck
## while already walking waypoints -> escalate to an A* path request; the
## glide-side flip stays as the immediate reflex while the path arrives.
func _check_stuck(desired: Vector2, delta: float) -> void:
	_stuck_timer += delta
	if _stuck_timer < STUCK_WINDOW:
		return
	var moved := global_position - _stuck_ref
	if moved.dot(desired) < STUCK_PROGRESS:
		if _building_contact <= CONTACT_GRACE:
			_gnawing = true
		else:
			if not _path.is_empty():
				## The path itself is blocked: toss it and ask for a fresh one.
				_drop_path()
				_want_path = true
			elif _rock_contact <= CONTACT_GRACE or _since_stuck <= RESTUCK_WINDOW:
				## Only path when the goal really is the chase target ahead;
				## retreating/flanking variants keep their reactive steering.
				var to_goal: Vector2 = _target.global_position - global_position
				if desired.dot(to_goal.normalized()) > 0.3:
					_want_path = true
			if moved.length() < STUCK_DISPLACE and _glide_sign != 0.0:
				_glide_sign = -_glide_sign
				_glide_timer = GLIDE_COMMIT
		_since_stuck = 0.0
	_stuck_timer = 0.0
	_stuck_ref = global_position

## While a path is live, steer at the current waypoint instead of the raw
## goal (glide still handles enemy shoving and wall nicks along the way).
## Advances on arrival; drops the path when finished or the target strayed.
func _path_desired(desired: Vector2) -> Vector2:
	if _path.is_empty():
		return desired
	## Drift vs the goal captured at request time — paths may legitimately end
	## SHORT of far targets (best-effort legs), so the end point is no anchor.
	if _target.global_position.distance_to(_path_goal) > PATH_TARGET_DRIFT:
		_drop_path()
		return desired
	while _path_i < _path.size() and global_position.distance_to(_path[_path_i]) <= WAYPOINT_REACH:
		_path_i += 1
	## Corner-miss rescue (staggered): clipping an outer rock corner can leave
	## the reach circle unentered; skip ahead once the NEXT point has grid LOS.
	if _path_i + 1 < _path.size() and (Engine.get_physics_frames() + get_instance_id()) & 3 == 0 \
			and NavGrid.line_clear(global_position, _path[_path_i + 1]):
		_path_i += 1
	if _path_i >= _path.size():
		_drop_path()
		## Best-effort leg walked but the goal is still far: chain the next one.
		if _target.global_position.distance_to(global_position) > PATH_TARGET_DRIFT:
			_want_path = true
		return desired
	return (_path[_path_i] - global_position).normalized()

## Budgeted request: null means NavGrid's per-frame allowance was spent, so
## the latch stays set and we retry next physics frame. Empty result means
## no route in the search window -> keep the plain glide fallback.
func _try_request_path() -> void:
	if _path_cd > 0.0:
		_want_path = false
		return
	var res = NavGrid.request_path(global_position, _target.global_position)
	if res == null:
		return
	_want_path = false
	_path_cd = PATH_COOLDOWN
	_path = _smooth_path(res)
	_path_i = 0
	_path_goal = _target.global_position

## String-pull over grid LOS: drop every waypoint a straight leg can skip,
## leaving corners only — straighter motion, fewer 20px reach discs to miss.
## Runs once per path grant (cooldown + frame budget), never per frame.
func _smooth_path(raw: PackedVector2Array) -> PackedVector2Array:
	if raw.size() < 3:
		return raw
	var out := PackedVector2Array()
	var anchor := global_position
	var i := 0
	while i < raw.size():
		var j := i
		while j + 1 < raw.size() and NavGrid.line_clear(anchor, raw[j + 1]):
			j += 1
		out.append(raw[j])
		anchor = raw[j]
		i = j + 1
	return out

func _drop_path() -> void:
	_path = PackedVector2Array()
	_path_i = 0

## Clear steering memory (attacking, resting, or teleported).
func _steering_reset() -> void:
	_gnawing = false
	_glide_sign = 0.0
	_glide_timer = 0.0
	_stuck_timer = 0.0
	_stuck_ref = global_position
	_want_path = false
	_drop_path()

## -- fire DoT ------------------------------------------------------------

## Catch fire (host): re-ignites REFRESH the running burn — duration back to
## full, strongest tick damage wins — they never stack a second DoT.
func ignite(tick_damage = -1, duration = -1.0) -> void:
	if _dead or _is_puppet():
		return
	var dur := float(duration) if float(duration) > 0.0 else Balance.num("fire/burn_duration", 3.0)
	var dmg := int(tick_damage) if int(tick_damage) > 0 else Balance.inum("fire/burn_tick_damage", 1)
	var was_burning := _burn_left > 0.0
	_burn_left = maxf(_burn_left, dur)
	_burn_tick_damage = maxi(_burn_tick_damage, dmg) if was_burning else dmg
	if not was_burning:
		_burn_tick_accum = 0.0
		_burn_fx_start()
	## Clients mirror via FX events; refreshes are throttled to ~1/s per
	## enemy so patch ticks re-igniting a horde don't spam the bus.
	if Net.is_online() and Net.is_host() and (not was_burning or _burn_bcast_cd <= 0.0):
		FxEvents.enemy_ignite(self, sync_id, _burn_left)
		_burn_bcast_cd = 1.0

## Client puppet: visual-only burn driven by the host's ignite events (the
## timer runs in parallel; refresh events keep it from expiring early).
func client_ignite(duration: float) -> void:
	if _dead:
		return
	var was_burning := _burn_left > 0.0
	_burn_left = maxf(_burn_left, float(duration))
	if not was_burning:
		_burn_fx_start()

## Runs on every peer (above the puppet gate): pulse + flicker everywhere,
## damage ticks host-only. Delta-accumulated, so pausing pauses the burn.
func _update_burn(delta: float) -> void:
	if _burn_left <= 0.0:
		return
	_burn_left -= delta
	_burn_bcast_cd -= delta
	_burn_time += delta
	if _burn_left <= 0.0 or _dead:
		_burn_end()
		return
	## Orange-hot pulse; the fx rig is counter-rotated every frame so the
	## flames always rise screen-up while the enemy spins.
	var heat := 0.7 + 0.3 * sin(_burn_time * 8.0)
	modulate = Color(1.0, lerpf(1.0, 0.65, heat), lerpf(1.0, 0.35, heat))
	if _burn_fx != null:
		_burn_fx.global_rotation = 0.0
		_burn_light.energy = 0.85 + 0.15 * sin(_burn_time * 9.0) + randf_range(-0.08, 0.08)
	if _is_puppet():
		return
	_burn_tick_accum += delta
	var tick := Balance.num("fire/burn_tick_interval", 0.5)
	if _burn_tick_accum >= tick:
		_burn_tick_accum -= tick
		## Full death/reward flow via take_damage; no blood spray per tick.
		take_damage(_burn_tick_damage, false)

## Flames licking the victim: tiny shared-resource emitters + a flickering
## light, parented to the enemy so death/queue_free frees them with the body.
func _burn_fx_start() -> void:
	if _burn_fx != null:
		return
	_burn_time = randf() * TAU  ## desync pulse phases across the horde
	_burn_fx = Node2D.new()
	_burn_fx.z_index = 3
	var flames := CPUParticles2D.new()
	flames.amount = 7
	flames.lifetime = 0.45
	flames.local_coords = false
	flames.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = _body_radius * 0.55
	flames.direction = Vector2(0, -1)
	flames.spread = 20.0
	flames.gravity = Vector2(0, -90)
	flames.initial_velocity_min = 8.0
	flames.initial_velocity_max = 24.0
	flames.scale_amount_min = 2.2
	flames.scale_amount_max = 4.0
	flames.color_ramp = Effects.fire_gradient()
	flames.emitting = true
	_burn_fx.add_child(flames)
	var embers := CPUParticles2D.new()
	embers.amount = 3
	embers.lifetime = 0.6
	embers.local_coords = false
	embers.direction = Vector2(0, -1)
	embers.spread = 45.0
	embers.gravity = Vector2(0, -140)
	embers.initial_velocity_min = 25.0
	embers.initial_velocity_max = 60.0
	embers.scale_amount_min = 1.0
	embers.scale_amount_max = 1.6
	embers.color_ramp = Effects.ember_gradient()
	embers.emitting = true
	_burn_fx.add_child(embers)
	_burn_light = PointLight2D.new()
	_burn_light.texture = Effects.fire_light_texture()
	_burn_light.texture_scale = 0.9
	_burn_light.energy = 1.0
	_burn_fx.add_child(_burn_light)
	add_child(_burn_fx)

func _burn_end() -> void:
	_burn_left = 0.0
	modulate = Color.WHITE
	if _burn_fx != null:
		_burn_fx.queue_free()
		_burn_fx = null
		_burn_light = null

## -------------------------------------------------------------------------

func heal(amount) -> void:
	## Puppet HP is host-owned (nothing heals client-side, belt and braces).
	if _dead or _is_puppet():
		return
	health = mini(health + int(amount), max_health)

## hit_fx=false skips the non-lethal blood spray (burn ticks would bleed
## every half-second otherwise); the death flow is identical either way.
func take_damage(amount, hit_fx := true) -> void:
	## Puppets never take damage locally: client bullets are cosmetic tracers
	## and client towers idle; the despawn + death event arrive from the host.
	if _dead or _is_puppet():
		return
	health -= int(amount)
	# Enemy faces the player, so the bullet came from +x; blood sprays away.
	var hit_pos: Vector2 = global_position + transform.x * 6.0
	var hit_dir: Vector2 = -transform.x
	if health <= 0:
		_dead = true
		Effects.blood_death(self, hit_pos, hit_dir)
		Sfx.play("enemy_die", global_position, -12.0)
		## Death feedback for clients: the spawner despawn is silent, so the
		## host broadcasts a tiny position event (enemy_sync plays blood+sfx).
		if Net.is_online():
			var sync = get_tree().get_first_node_in_group("enemy_sync")
			if sync != null:
				sync.broadcast_death(hit_pos, hit_dir)
		## Bounty multiplier + fractional carry live in GameState.
		GameState.add_scrap_bounty(scrap_value)
		if crystal_value > 0:
			GameState.add_resource("crystal", crystal_value)
		died.emit(points)
		queue_free()
	elif hit_fx:
		Effects.blood_hit(self, hit_pos, hit_dir)
