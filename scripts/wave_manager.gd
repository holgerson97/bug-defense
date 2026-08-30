extends Node2D

signal wave_started(wave: int)
signal intermission_started(seconds: float)
signal enemy_killed(points: int)
signal remaining_changed(counts: Dictionary)

const BRUTE_SCENE = preload("res://scenes/enemies/brute.tscn")
const MAGE_SCENE = preload("res://scenes/enemies/mage.tscn")
const BOSS_SCENE = preload("res://scenes/enemies/boss_broodmother.tscn")
const WASP_SCENE = preload("res://scenes/enemies/wasp.tscn")
const RUNNER_SCENE = preload("res://scenes/enemies/runner.tscn")
const DRONE_SCENE = preload("res://scenes/enemies/drone_tank.tscn")

@export var enemy_scene: PackedScene
@export var time_between_waves: float = 20.0
@export var spawn_interval: float = 0.18
@export var spawn_radius: float = 800.0

## Spawn kind -> HUD display name.
const KIND_NAMES := {"grunt": "Grunt", "runner": "Runner", "brute": "Brute", "mage": "Mage", "wasp": "Wasp", "drone": "Drone", "boss": "Boss"}

## Chaff pours out in big bursts; everything else trickles one per tick.
## Wasps count as chaff so the wave-14+ air hordes arrive as swarms too.
const CHAFF := {"grunt": true, "runner": true, "wasp": true}
var chaff_burst: int = Balance.inum("waves/chaff_burst", 5)

## Hard ceiling on alive enemies: the spawner defers (never drops) at the cap.
var max_alive: int = Balance.inum("waves/max_alive", 350)

## Balance knobs: per-wave HP growth curves, boss cadence and composition
## formula constants (fallbacks = the shipped values).
var hp_scale_factor: float = Balance.num("waves/hp_scale", 1.12)
var chaff_hp_scale_factor: float = Balance.num("waves/chaff_hp_scale", 1.06)
var mage_hp_scale_factor: float = Balance.num("waves/mage_hp_scale", 1.09)
var wasp_hp_scale_factor: float = Balance.num("waves/wasp_hp_scale", 1.07)
var boss_hp_growth: float = Balance.num("waves/boss_hp_growth", 1.5)
var boss_every: int = Balance.inum("waves/boss_every", 10)

var wave: int = 0
var _alive: int = 0
var _spawning: bool = false
var _remaining: Dictionary = {}
var _cluster_angles: PackedFloat32Array = PackedFloat32Array()
## Stable per-run enemy id: node name "E<id>" on every peer; the transform
## batcher (enemy_sync.gd) keys its packets on it.
var _next_id: int = 0
## Host-online: high-frequency signals (remaining counts, kill points) batch
## into at most one reliable RPC per physics frame.
var _remaining_dirty: bool = false
var _points_pending: int = 0

@onready var _spawner: MultiplayerSpawner = $"../EnemySpawner"

func _ready() -> void:
	add_to_group("wave_manager")
	time_between_waves = Balance.num("waves/time_between_waves", time_between_waves)
	spawn_interval = Balance.num("waves/spawn_interval", spawn_interval)
	spawn_radius = Balance.num("waves/spawn_radius", spawn_radius)
	_spawner.spawn_function = _spawn_enemy_node
	## Simulation is host-only (offline counts as host); clients only receive
	## the wave RPCs and re-emit the local signals for the HUD.
	if Net.is_host():
		_start_next_wave_after_delay()
	else:
		## First intermission mirrors locally: the host's initial RPC may race
		## the client's scene load. Later ones arrive via _rpc_intermission.
		call_deferred("emit_signal", "intermission_started", time_between_waves)

## Host-online: flush batched HUD traffic once per physics frame.
func _physics_process(_delta: float) -> void:
	if not Net.is_online() or not Net.is_host():
		return
	if _remaining_dirty or _points_pending > 0:
		_rpc_wave_events.rpc(_remaining, _points_pending)
		_remaining_dirty = false
		_points_pending = 0

func _start_next_wave_after_delay() -> void:
	## HUD mirrors this delay locally; no per-frame signal traffic.
	## Deferred: the first call runs inside _ready, before the HUD has
	## connected — a synchronous emit would be missed. The one-frame delay
	## is harmless for later intermissions.
	call_deferred("_announce_intermission")
	await get_tree().create_timer(time_between_waves, false).timeout
	_start_wave()

func _announce_intermission() -> void:
	intermission_started.emit(time_between_waves)
	if Net.is_online():
		_rpc_intermission.rpc(time_between_waves)

func _start_wave() -> void:
	wave += 1
	_remaining.clear()
	remaining_changed.emit(_remaining)
	wave_started.emit(wave)
	if Net.is_online():
		_rpc_wave_started.rpc(wave)
	var boss_wave := wave % boss_every == 0
	var comp := Balance.section("waves/composition")
	## Chaff flood: every wave visibly bigger than the last. Grunts retire
	## after grunt_last_wave — from then on, mages summon the ground swarm.
	var grunts: int = int(comp.get("grunt_base", 20)) + wave * int(comp.get("grunt_per_wave", 8))
	if wave > int(comp.get("grunt_last_wave", 999999)):
		grunts = 0
	var runners: int = int(comp.get("runner_base", 10)) + wave * int(comp.get("runner_per_wave", 6)) \
			if wave >= int(comp.get("runner_from_wave", 2)) else 0
	@warning_ignore("integer_division")
	var brutes: int = wave / int(comp.get("brute_divisor", 4))
	@warning_ignore("integer_division")
	var mages: int = mini(wave / int(comp.get("mage_divisor", 6)), int(comp.get("mage_cap", 3)))
	if wave >= int(comp.get("mage_from_wave", 999999)):
		mages = maxi(mages, 1)
	else:
		mages = 0
	@warning_ignore("integer_division")
	var wasps: int = mini((wave / int(comp.get("wasp_divisor", 6))) * int(comp.get("wasp_per_step", 4)), int(comp.get("wasp_cap", 24)))
	## Armored air brutes: flak sponges for the swarm.
	@warning_ignore("integer_division")
	var drones: int = wave / int(comp.get("drone_divisor", 8))
	## The sky stays clear until the air-entry waves; build AA before then.
	if wave < int(comp.get("wasp_from_wave", 15)):
		wasps = 0
	if wave < int(comp.get("drone_from_wave", 25)):
		drones = 0
	## Late flood: wasps pour in like ground chaff.
	var flood_wave: int = int(comp.get("wasp_flood_wave", 20))
	if wave >= flood_wave:
		wasps = int(comp.get("wasp_flood_base", 12)) + (wave - flood_wave) * int(comp.get("wasp_flood_per_wave", 4))
	if boss_wave:
		# Boss waves: the boss plus half the normal composition.
		grunts /= 2
		runners /= 2
		brutes /= 2
		mages /= 2
		## Air pressure spike: drones surge on boss waves instead of halving.
		drones = int(ceil(drones * 1.5))
	var queue: Array = []
	for i in grunts:
		queue.append("grunt")
	for i in runners:
		queue.append("runner")
	for i in brutes:
		queue.append("brute")
	for i in mages:
		queue.append("mage")
	for i in wasps:
		queue.append("wasp")
	for i in drones:
		queue.append("drone")
	queue.shuffle()
	if boss_wave:
		queue.push_front("boss")
	_pick_cluster_angles()
	_spawning = true
	var idx := 0
	while idx < queue.size():
		## At the alive cap: hold the queue until towers thin the horde.
		while _alive >= max_alive:
			await get_tree().create_timer(spawn_interval, false).timeout
		var burst: int = chaff_burst if CHAFF.has(queue[idx]) else 1
		for b in burst:
			if idx >= queue.size() or (b > 0 and not CHAFF.has(queue[idx])) or _alive >= max_alive:
				break
			_spawn_kind(queue[idx])
			idx += 1
		await get_tree().create_timer(spawn_interval, false).timeout
	_spawning = false
	if _alive == 0:
		_start_next_wave_after_delay()

## Steep curve for the wall-breakers (brutes): they keep pace with upgrades.
func _hp_scale() -> float:
	return pow(hp_scale_factor, wave - 1)

## Gentle curve for chaff: swarm count carries the threat, not per-unit HP.
func _chaff_hp_scale() -> float:
	return pow(chaff_hp_scale_factor, wave - 1)

## Per-type base HP from Balance, feeding the wave-scaling formulas below.
func _base_hp(kind: String, fallback: float) -> float:
	return Balance.num("enemies/%s/hp" % kind, fallback)

## Host-only: compute the wave stat overrides, then spawn through the
## replicated path so every peer builds the identical node.
@warning_ignore("integer_division")
func _spawn_kind(kind) -> void:
	var ov := {}
	match kind:
		"brute":
			ov = {"max_health": int(ceil(_base_hp("brute", 15.0) * _hp_scale())), "speed_delta": wave * 2.0}
		"mage":
			ov = {"max_health": int(ceil(_base_hp("mage", 6.0) * pow(mage_hp_scale_factor, wave - 1)))}
		"wasp":
			ov = {"max_health": int(ceil(_base_hp("wasp", 3.0) * pow(wasp_hp_scale_factor, wave - 1)))}
		"drone":
			## Brute curve: the air tank must outlast flak upgrades too.
			ov = {"max_health": int(ceil(_base_hp("drone", 25.0) * _hp_scale()))}
		"runner":
			## Mirrors summoned runners: near-one-shot chaff at any wave.
			ov = {"max_health": Balance.inum("enemies/runner/hp", 1) + wave / 10, "speed_delta": wave * 2.0}
		"boss":
			var boss_number := wave / boss_every
			ov = {"max_health": int(_base_hp("boss", 250.0) * boss_number * pow(boss_hp_growth, boss_number - 1))}
		_:
			kind = "grunt"
			## Cheap per kill; ~2.5x count keeps wave income roughly flat.
			ov = {"max_health": int(ceil(_base_hp("grunt", 2.0) * _chaff_hp_scale())), "speed_delta": wave * 2.0,
				"scrap_value": maxi(Balance.inum("enemies/grunt/scrap", 1) + (wave * 2) / 5, 1)}
	_spawn(kind, _spawn_position(), ov)

## Lets summoners (mage, boss) birth runners through the replicated spawn
## path; their spawns count toward wave clearing like before.
func spawn_summon(pos: Vector2, max_health: int, speed_delta: float) -> Node:
	## Mage/boss birth rings can clip rock edges — slide embeds to free ground.
	return _spawn("runner", NavGrid.nearest_free(pos), {"max_health": max_health, "speed_delta": speed_delta})

## Hive defenders (hive_site.gd): spawned through the same replicated path so
## clients see them, but NOT registered — they never touch _alive/_remaining,
## so they don't count toward wave clearing and can't hold up intermissions.
func spawn_hive_defender(kind: String, pos: Vector2, ov: Dictionary) -> Node:
	return _spawn(kind, NavGrid.nearest_free(pos), ov, false)

## Spawner round-trip: offline and host alike go through the MultiplayerSpawner
## (its spawn() also works with the offline peer); clients replay
## _spawn_enemy_node with identical data, so names/stats/positions match.
## `counted` = false spawns a full replicated enemy outside the wave ledger.
func _spawn(kind: String, pos: Vector2, ov: Dictionary, counted := true) -> Node:
	_next_id += 1
	return _spawner.spawn([_next_id, kind, pos, ov, counted])

func _kind_scene(kind: String) -> PackedScene:
	match kind:
		"brute": return BRUTE_SCENE
		"mage": return MAGE_SCENE
		"wasp": return WASP_SCENE
		"drone": return DRONE_SCENE
		"runner": return RUNNER_SCENE
		"boss": return BOSS_SCENE
		_: return enemy_scene

## Runs on every peer (host via spawn(), clients via the replicated call).
## Data: [id, kind, pos, stat overrides, counted]. Only the host registers —
## clients get counts via _rpc_wave_events and never simulate the enemy
## (enemy.gd puppet gate). Uncounted spawns (hive defenders) skip _register.
func _spawn_enemy_node(data: Array) -> Node:
	var enemy = _kind_scene(data[1]).instantiate()
	enemy.name = "E%d" % data[0]
	enemy.sync_id = data[0]
	## Stashed, not applied: enemy._ready() layers these over its Balance base
	## stats, so the wave overrides keep authority regardless of balance.json.
	enemy.spawn_overrides = data[3]
	## Enemies container sits at the origin: position == global position.
	enemy.position = data[2]
	if Net.is_host() and (data.size() < 5 or data[4]):
		_register(enemy, KIND_NAMES.get(data[1], "Grunt"))
	return enemy

## 2-3 attack directions per wave: columns marching in, not a thin ring.
func _pick_cluster_angles() -> void:
	_cluster_angles = PackedFloat32Array()
	for i in 2 + randi() % 2:
		_cluster_angles.append(randf() * TAU)

## Spawn ring centers on the centroid of all (alive) players.
func _spawn_position() -> Vector2:
	var center := Vector2.ZERO
	var players := get_tree().get_nodes_in_group("player")
	for player in players:
		center += player.global_position
	if not players.is_empty():
		center /= players.size()
	var angle := randf() * TAU
	if not _cluster_angles.is_empty():
		angle = _cluster_angles[randi() % _cluster_angles.size()] + randf_range(-0.4, 0.4)
	## Ring points that land inside a rock mass slide to the nearest free cell.
	return NavGrid.nearest_free(center + Vector2.from_angle(angle) * spawn_radius)

## Tracks alive + per-type remaining counts; type name rides along on `died`.
func _register(enemy, type_name: String) -> void:
	enemy.died.connect(_on_enemy_died.bind(type_name))
	_alive += 1
	_remaining[type_name] = _remaining.get(type_name, 0) + 1
	remaining_changed.emit(_remaining)
	_remaining_dirty = true

func _on_enemy_died(points: int, type_name: String) -> void:
	_alive -= 1
	_remaining[type_name] = maxi(_remaining.get(type_name, 1) - 1, 0)
	if _remaining[type_name] == 0:
		_remaining.erase(type_name)
	remaining_changed.emit(_remaining)
	enemy_killed.emit(points)
	if Net.is_online():
		_remaining_dirty = true
		_points_pending += points
	if _alive == 0 and not _spawning:
		_start_next_wave_after_delay()

## -- host -> clients: wave state mirror; clients re-emit the local signals so
## the HUD/score wiring stays untouched --

@rpc("authority", "call_remote", "reliable")
func _rpc_wave_started(w: int) -> void:
	wave = w
	_remaining.clear()
	remaining_changed.emit(_remaining)
	wave_started.emit(w)

@rpc("authority", "call_remote", "reliable")
func _rpc_intermission(seconds: float) -> void:
	intermission_started.emit(seconds)

@rpc("authority", "call_remote", "reliable")
func _rpc_wave_events(counts: Dictionary, points: int) -> void:
	_remaining = counts
	remaining_changed.emit(_remaining)
	if points > 0:
		enemy_killed.emit(points)
