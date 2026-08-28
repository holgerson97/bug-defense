class_name FxEvents
extends Node
## Phase 6: combat FX event bus (Main/FxEvents, same pattern as EnemySync).
## The host queues compact events at the source (tower fire paths, shell
## bursts, heal ticks) and flushes them once per physics frame as ONE
## reliable RPC per peer, so bursts (MG at 20 shots/s x N towers) collapse
## into a single packet. Clients replay pure cosmetics: muzzle flash, sfx at
## the host-side volumes, collisionless tracers, cosmetic globs/patches/
## shells. The host never replays (it already played the real thing);
## per-event `except` skips the peer whose own local visual exists (own fire
## tracer, own heal beam). Offline the bus is inert: emits no-op via _active.

enum Kind { TOWER_FIRE, AA_FIRE, TESLA_BOLT, FLAME_GLOB, FLAK_BURST, GRENADE_LOB, REPAIR_BEAM, HEAL_BEAM, PLAYER_FIRE }

const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const FLAK_SHELL_SCENE := preload("res://scenes/flak_shell.tscn")
const GRENADE_SCENE := preload("res://scenes/grenade.tscn")
const FLAK_BURST_SCENE := preload("res://scenes/effects/flak_burst.tscn")
const FLAME_TOWER := preload("res://scripts/flame_tower.gd")

## Heal beams live a bit past the 0.5 s heal tick so follow-up ticks refresh
## them into a continuous beam; a missed tick just lets it fade.
const HEAL_BEAM_HOLD := 0.7

## True only for the online host — the sole emitter. Set once in _ready
## (sessions are fixed at game start), read by the static emit helpers.
var _active := false
var _queue: Array = []              ## [kind, except_peer, args]
var debug_replayed: Dictionary = {} ## kind -> replay count (smoke tests)
var _heal_beams: Dictionary = {}    ## peer_id -> [Line2D, player, target, timer]
var _flame_patches: Dictionary = {} ## tower path -> patch array (per-tower cap)

func _ready() -> void:
	add_to_group("fx_events")
	_active = Net.is_online() and Net.is_host()
	set_physics_process(_active)
	## _process tracks heal beams — the host draws remote healers' beams too.
	set_process(Net.is_online())

## -- host-side emit API: call from the real action's code path. No-ops
## everywhere but the online host, so emit sites need no gating of their own --

## variant: 0 = burst-opening shot (heavy sfx), 1 = shot, 2 = tail (sfx only).
static func tower_fire(src: Node2D, variant: int, from: Vector2, angle: float) -> void:
	_emit(src, Kind.TOWER_FIRE, [src.get_path(), variant, from, angle])

static func aa_fire(src: Node2D, from: Vector2, angle: float, burst_point: Vector2) -> void:
	_emit(src, Kind.AA_FIRE, [src.get_path(), from, angle, burst_point])

static func tesla_bolt(src: Node2D, points: PackedVector2Array) -> void:
	_emit(src, Kind.TESLA_BOLT, [points])

static func flame_glob(src: Node2D, from: Vector2, to: Vector2) -> void:
	_emit(src, Kind.FLAME_GLOB, [src.get_path(), from, to])

static func flak_burst(src: Node, pos: Vector2) -> void:
	_emit(src, Kind.FLAK_BURST, [pos])

static func grenade_lob(src: Node, from: Vector2, to: Vector2) -> void:
	_emit(src, Kind.GRENADE_LOB, [from, to])

static func repair_beam(src: Node2D, target_pos: Vector2) -> void:
	_emit(src, Kind.REPAIR_BEAM, [src.get_path(), target_pos])

## peer_id doubles as `except`: the healing player draws its own beam locally.
static func heal_beam(building: Node2D, peer_id: int) -> void:
	_emit(building, Kind.HEAL_BEAM, [peer_id, building.get_path()], peer_id)
	## Events replay on clients only — the host shows remote healers here.
	if peer_id != 1:
		var bus = building.get_tree().get_first_node_in_group("fx_events")
		if bus != null and bus._active:
			bus.show_heal_beam(peer_id, building)

static func player_fire(player: Node2D, from: Vector2, angle: float, crit: bool, except: int = 0) -> void:
	_emit(player, Kind.PLAYER_FIRE, [from, angle, crit], except)

static func _emit(node: Node, kind: int, args: Array, except: int = 0) -> void:
	var tree := node.get_tree()
	if tree == null:
		return
	var bus = tree.get_first_node_in_group("fx_events")
	if bus != null and bus._active:
		bus._queue.append([kind, except, args])

## Host: flush the frame's batch — one reliable RPC per peer.
func _physics_process(_delta: float) -> void:
	if _queue.is_empty():
		return
	## Fast path: no per-peer exclusion queued this frame (the common case —
	## tower fire, tesla, flak): one broadcast, no per-peer array builds.
	var any_except := false
	for e in _queue:
		if e[1] != 0:
			any_except = true
			break
	if not any_except:
		var events: Array = []
		for e in _queue:
			events.append([e[0], e[2]])
		_rpc_events.rpc(events)
	else:
		for peer in multiplayer.get_peers():
			var events: Array = []
			for e in _queue:
				if e[1] != peer:
					events.append([e[0], e[2]])
			if not events.is_empty():
				_rpc_events.rpc_id(peer, events)
	_queue.clear()

## -- client replay --

@rpc("authority", "call_remote", "reliable")
func _rpc_events(events: Array) -> void:
	for e in events:
		var kind: int = e[0]
		var a: Array = e[1]
		debug_replayed[kind] = int(debug_replayed.get(kind, 0)) + 1
		match kind:
			Kind.TOWER_FIRE:
				_replay_tower_fire(a)
			Kind.AA_FIRE:
				_replay_aa_fire(a)
			Kind.TESLA_BOLT:
				Effects.tesla_bolts(self, a[0])
				Sfx.play("zap", a[0][0], -8.0)
			Kind.FLAME_GLOB:
				_replay_flame_glob(a)
			Kind.FLAK_BURST:
				_spawn_at(FLAK_BURST_SCENE.instantiate(), a[0])
				Sfx.play("flak", a[0], -2.0)
			Kind.GRENADE_LOB:
				_replay_grenade_lob(a)
			Kind.REPAIR_BEAM:
				var tower = get_node_or_null(a[0])
				if tower != null:
					tower._show_beam(a[1])
			Kind.HEAL_BEAM:
				_replay_heal_beam(a)
			Kind.PLAYER_FIRE:
				Effects.muzzle_flash(self, a[0], a[1])
				Sfx.play("shoot_player", a[0], -6.0)
				_tracer(a[0], a[1], a[2], 80)

## MG shot: snap the head so client towers visibly track, then flash + sfx
## + a cosmetic tracer. Tail variant is the burst wind-down sfx only.
func _replay_tower_fire(a: Array) -> void:
	_snap_head(a[0], a[3])
	if a[1] == 2:
		Sfx.play("mg_tail", a[2], -10.0)
		return
	Effects.muzzle_flash(self, a[2], a[3])
	if a[1] == 0:
		Sfx.play("shoot_heavy", a[2], -10.0)
	else:
		Sfx.play("shoot", a[2], -14.0)
	_tracer(a[2], a[3], false, 64)

## AA shot: the tracer is a cosmetic flak shell flying the host's route; the
## burst FX arrives separately as the host shell's FLAK_BURST event.
func _replay_aa_fire(a: Array) -> void:
	_snap_head(a[0], a[2])
	Effects.muzzle_flash(self, a[1], a[2])
	Sfx.play("shoot", a[1], -14.0)
	var shell = FLAK_SHELL_SCENE.instantiate()
	shell.burst_point = a[3]
	shell.cosmetic = true
	_spawn_at(shell, a[1])

## Cosmetic glob: full arc + landing visual, no damage; its patch is spawned
## with damage ticking disabled. Patches are keyed per source tower so the
## per-tower cap/rekindle logic matches the host.
func _replay_flame_glob(a: Array) -> void:
	var tower = get_node_or_null(a[0])
	if tower != null:
		tower._flare = tower.FLARE_TIME
		var nozzle = tower.get_node_or_null("Nozzle")
		if nozzle != null:
			nozzle.rotation = (a[2] - tower.global_position).angle()
	var glob = FLAME_TOWER.FireGlob.new()
	glob.cosmetic = true
	glob.target_point = a[2]
	glob.patches = _flame_patches.get_or_add(a[0], [])
	_spawn_at(glob, a[1])
	Sfx.play("flame", a[1], -14.0)

## Cosmetic grenade: arc + explosion FX/sfx at landing, damage skipped.
func _replay_grenade_lob(a: Array) -> void:
	var grenade = GRENADE_SCENE.instantiate()
	grenade.cosmetic = true
	grenade.target_point = a[1]
	_spawn_at(grenade, a[0])

func _replay_heal_beam(a: Array) -> void:
	var target = get_node_or_null(a[1])
	if target != null:
		show_heal_beam(a[0], target)

## Remote player heal beam: one Line2D per healing peer that follows the
## synced player/target positions in _process until the refresh runs dry.
## Called by client replay AND directly on the host for client healers.
func show_heal_beam(peer_id: int, target: Node2D) -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	var player = scene.get_node_or_null("Players/%d" % peer_id)
	if player == null:
		return
	var entry: Array = _heal_beams.get_or_add(peer_id, [null, null, null, 0.0])
	if entry[0] == null or not is_instance_valid(entry[0]):
		var line := Line2D.new()
		line.top_level = true
		line.z_index = 50
		line.width = 3.0
		line.default_color = Color(0.35, 1, 0.55, 0.85)
		scene.add_child(line)
		entry[0] = line
	entry[1] = player
	entry[2] = target
	entry[3] = HEAL_BEAM_HOLD

## Client: heal beams track the moving player/target, then fade on timeout.
func _process(delta: float) -> void:
	for peer in _heal_beams.keys():
		var entry: Array = _heal_beams[peer]
		if not is_instance_valid(entry[0]):
			_heal_beams.erase(peer)
			continue
		entry[3] -= delta
		if entry[3] <= 0.0 or not is_instance_valid(entry[1]) or not is_instance_valid(entry[2]):
			entry[0].visible = false
			continue
		entry[0].points = PackedVector2Array([entry[1].global_position, entry[2].global_position])
		entry[0].visible = true

## Cosmetic tracer: zero damage, enemy bit dropped from the mask (puppets
## have no collision anyway), auto-frees via the bullet's own lifetime.
func _tracer(from: Vector2, angle: float, crit: bool, mask: int) -> void:
	var bullet = BULLET_SCENE.instantiate()
	bullet.rotation = angle
	bullet.damage = 0
	bullet.crit = crit
	bullet.collision_mask = mask
	_spawn_at(bullet, from)

func _snap_head(path: NodePath, angle: float) -> void:
	var tower = get_node_or_null(path)
	if tower != null:
		var head = tower.get_node_or_null("Head")
		if head != null:
			head.rotation = angle

func _spawn_at(node: Node2D, pos: Vector2) -> void:
	var scene = get_tree().current_scene
	if scene == null:
		node.free()
		return
	node.global_position = pos
	scene.add_child(node)
