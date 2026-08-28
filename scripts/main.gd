extends Node2D

const CHUNK_SIZE := 1024.0
const DEPOSIT_PLAYER_CLEARANCE := 200.0

## Crystal: SC-style mineral lines — one arc cluster in ~40% of chunks.
const CLUSTER_CHUNK_CHANCE := 0.40
const CLUSTER_MIN := 5
const CLUSTER_MAX := 8
const CLUSTER_SPACING := 48.0
const CLUSTER_ARC_RADIUS := 200.0
const CLUSTER_JITTER := 4.0
const CLUSTER_ATTEMPTS := 6
const GOLD_CHUNK_CHANCE := 0.30

## Rocks: large organic masses per chunk (silhouettes live in rock.gd).
const ROCK_TILE := 32.0
const ROCK_CHUNK_CHANCE := 0.60
const ROCK_DEPOSIT_CLEARANCE := 60.0
const ROCK_EDGE_MARGIN := 48.0
const ROCK_ATTEMPTS := 4

## ---- Distance tiers (chunk center -> PLAYER_SPAWN): farther = bigger + denser.
## dist        | rock chance | formations   | cell_scale        | crystals | gold
## < 1500px    | 0.60        | 1            | 1                 | 5-8      | 30%, 1-2
## 1500-4000px | 0.70        | 2nd @ 25%    | 1 (65%) / 2 (35%) | 5-8      | 30%, 1-2
## > 4000px    | 0.80        | 1-2          | 2 (~380-800px)    | 7-10     | 45%, pair @ 75%
const TIER_MID_DIST := 1500.0
const TIER_FAR_DIST := 4000.0
const MID_ROCK_CHANCE := 0.70
const FAR_ROCK_CHANCE := 0.80
const MID_SECOND_ROCK_CHANCE := 0.25
const MID_SCALE2_CHANCE := 0.35
const FAR_CLUSTER_MIN := 7
const FAR_CLUSTER_MAX := 10
const FAR_GOLD_CHANCE := 0.45
const FAR_GOLD_PAIR_CHANCE := 0.75

const PLAYER_SCENE := preload("res://scenes/player.tscn")
## Where the old static Player node sat; extra peers fan out to the right.
const PLAYER_SPAWN := Vector2(1280, 720)
const SPAWN_SPACING := 56.0

## Guaranteed starter kit (U rock pocket, mineral line, gold) fits in this ring.
const STARTER_RADIUS := 600.0

var score: int = 0
var deposit_scene: PackedScene = preload("res://scenes/crystal_deposit.tscn")
var gold_deposit_scene: PackedScene = preload("res://scenes/gold_deposit.tscn")
var rock_scene: PackedScene = preload("res://scenes/rock.tscn")
const Rock := preload("res://scripts/rock.gd")
const BuildController := preload("res://scripts/build_controller.gd")

## Run-wide world-gen seed: online the host's roll (identical terrain on
## every peer), offline a fresh randi(). All chunk seeds derive from it.
var _run_seed: int = 0
var _seeded_chunks: Dictionary = {}
## World rects of starter placements; normal chunk seeding keeps off them.
var _starter_rects: Array[Rect2] = []
## Host: peers whose main scene finished loading (spawning waits for all).
var _ready_peers: Dictionary = {}
var _players_spawned := false

@onready var _players: Node2D = $Players
@onready var _spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _building_spawner: MultiplayerSpawner = $BuildingSpawner
@onready var _wave_manager = $WaveManager
@onready var _hud = $HUD

func _ready() -> void:
	## Custom spawn carries [peer_id, position]; the auto-spawn list can't
	## replicate spawn position for client-authority nodes.
	_spawner.spawn_function = _spawn_player_node
	_building_spawner.spawn_function = _spawn_building_node
	GameState.reset()
	_wave_manager.wave_started.connect(_hud.update_wave)
	_wave_manager.enemy_killed.connect(_on_enemy_killed)
	## Phase 7: intermission revives dead players + lets late joiners in (host).
	_wave_manager.intermission_started.connect(_on_intermission_started)
	## Host drop: clients get a modal and a clean way back to the menu.
	Net.session_ended.connect(_on_session_ended)
	_hud.update_score(score)
	## World gen determinism (MP Phase 4): online every peer derives identical
	## terrain from the host's run seed; offline a fresh random run as before.
	## Starter gen draws from the global RNG seeded with the run seed directly.
	_run_seed = Net.run_seed if Net.is_online() else randi()
	seed(_run_seed)
	## Guaranteed starter terrain, before any lazy chunk seeding runs.
	_seed_starter_area()
	_spawn_or_report()

func _process(_delta: float) -> void:
	_seed_chunks_around_players()

## Offline: one local player, exactly where the old static node sat. Online:
## clients report their scene loaded; the host spawns one player per peer once
## everyone is in (MultiplayerSpawner replicates them; node name = peer id).
func _spawn_or_report() -> void:
	if not Net.is_online():
		_spawn_player(1, 0)
	elif Net.is_host():
		## A peer dropping during load must not stall the wait.
		Net.player_list_changed.connect(_try_spawn_players)
		## Mid-game leavers get their player despawned (registry prune first).
		Net.player_list_changed.connect(_prune_leavers)
		_ready_peers[1] = true
		_try_spawn_players()
	elif Net.late_joining:
		## Late joiner: still in the auth phase — the host spawns us after
		## registration (Net._rpc_register -> spawn_late_joiner), no handshake.
		Net.late_joining = false
	else:
		_rpc_scene_ready.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_scene_ready() -> void:
	if not multiplayer.is_server():
		return
	_ready_peers[multiplayer.get_remote_sender_id()] = true
	_try_spawn_players()

func _try_spawn_players() -> void:
	if _players_spawned:
		return
	for id in Net.players:
		if not _ready_peers.has(id):
			return
	_players_spawned = true
	var index := 0
	for id in Net.players:
		_spawn_player(id, index)
		index += 1

func _spawn_player(peer_id: int, index: int) -> void:
	_spawner.spawn([peer_id, PLAYER_SPAWN + Vector2(SPAWN_SPACING * index, 0)])

## Runs on every peer (host via spawn(), clients via the replicated call).
func _spawn_player_node(data: Array) -> Node:
	var player = PLAYER_SCENE.instantiate()
	player.name = str(data[0])
	player.position = data[1]
	player.died.connect(_on_player_died)
	return player

## Online (host only): buildings live under Buildings so the spawner
## replicates them; queue_free on the host despawns them everywhere.
## Offline keeps the old direct add_child path in build_controller.
func spawn_building(id: String, pos: Vector2, facing: float) -> Node:
	return _building_spawner.spawn([id, pos, facing])

## Runs on every peer; [scene_id, pos, facing] rebuilds the node identically
## (parent Buildings sits at the origin, so position == global position).
func _spawn_building_node(data: Array) -> Node:
	var building = BuildController.BUILDING_SCENES[data[0]].instantiate()
	building.position = data[1]
	building.facing = data[2]
	Sfx.play("place", data[1])
	return building

## Guaranteed base kit near the spawn: one U rock pocket (opening spun toward
## the spawn), one crystal mineral line and one gold deposit, inside
## STARTER_RADIUS and outside the 200px clearance. Runs once in _ready; the
## affected chunks still seed normally later but respect `_starter_rects`, so
## nothing stacks. Like all world gen this runs per instance (host and clients
## independently); deterministic shared gen is MP plan Phase 4.
func _seed_starter_area() -> void:
	_seed_starter_rock()
	_seed_starter_crystals()
	_seed_starter_gold()

## Forced U template, anchor snapped to the build lattice like chunk rocks.
func _seed_starter_rock() -> void:
	for attempt in 24:
		var dir := Vector2.from_angle(randf() * TAU)
		var center := PLAYER_SPAWN + dir * randf_range(430.0, STARTER_RADIUS - 40.0)
		var rock = rock_scene.instantiate()
		## Scale 2: a roomy 384px U pocket the starter base actually fits in.
		rock.generate(rock.SHAPE_U, _u_spin(-dir), 2)
		var bounds: Rect2 = rock.bounds
		var anchor := (center - bounds.get_center()).snapped(Vector2(ROCK_TILE, ROCK_TILE))
		var rect := Rect2(anchor + bounds.position, bounds.size)
		if rect.grow(DEPOSIT_PLAYER_CLEARANCE).has_point(PLAYER_SPAWN):
			rock.free()
			continue
		rock.position = anchor
		add_child(rock)
		_starter_rects.append(rect)
		return

## Spin (0-3) that points the U opening (up at spin 0) along `dir`.
func _u_spin(dir: Vector2) -> int:
	if absf(dir.x) > absf(dir.y):
		return 1 if dir.x > 0.0 else 3
	return 2 if dir.y > 0.0 else 0

func _seed_starter_crystals() -> void:
	for attempt in 24:
		var center := PLAYER_SPAWN + Vector2.from_angle(randf() * TAU) \
			* randf_range(300.0, STARTER_RADIUS - CLUSTER_ARC_RADIUS)
		var rect := _try_crystal_line(center, [])
		if rect.has_area():
			_starter_rects.append(rect)
			return

func _seed_starter_gold() -> void:
	for attempt in 24:
		var pos := PLAYER_SPAWN + Vector2.from_angle(randf() * TAU) \
			* randf_range(DEPOSIT_PLAYER_CLEARANCE + 40.0, STARTER_RADIUS)
		if not _deposit_pos_clear(pos, []):
			continue
		var deposit = gold_deposit_scene.instantiate()
		deposit.global_position = pos
		add_child(deposit)
		_starter_rects.append(Rect2(pos, Vector2.ZERO).grow(24.0))
		return

## Endless map: lazily sprinkle crystal blocks into chunks near every player.
func _seed_chunks_around_players() -> void:
	for player in _players.get_children():
		var center := Vector2i((player.global_position / CHUNK_SIZE).floor())
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var chunk := center + Vector2i(dx, dy)
				if _seeded_chunks.has(chunk):
					continue
				_seeded_chunks[chunk] = true
				_seed_chunk(chunk)

## Rock first (deposits check its bbox), then crystal cluster, then gold.
## Density and rock size ramp with distance from spawn — see the tier table.
func _seed_chunk(chunk: Vector2i) -> void:
	## Deterministic per-chunk RNG: reseed the GLOBAL stream — all generation
	## below (incl. rock.generate/_ready jitter + facets) runs synchronously
	## inside this call, so every peer draws the exact same sequence per chunk
	## regardless of the order chunks get triggered in.
	seed(hash(_run_seed ^ hash(chunk)))
	var dist := ((Vector2(chunk) + Vector2(0.5, 0.5)) * CHUNK_SIZE).distance_to(PLAYER_SPAWN)
	var far := dist >= TIER_FAR_DIST
	var mid := not far and dist >= TIER_MID_DIST
	var rock_chance := FAR_ROCK_CHANCE if far else (MID_ROCK_CHANCE if mid else ROCK_CHUNK_CHANCE)
	var rock_rects: Array[Rect2] = []
	if randf() < rock_chance:
		var count := 1
		if far:
			count = randi_range(1, 2)
		elif mid and randf() < MID_SECOND_ROCK_CHANCE:
			count = 2
		for i in count:
			var rock_scale := 1
			if far or (mid and randf() < MID_SCALE2_CHANCE):
				rock_scale = 2
			var rect := _place_rock_formation(chunk, rock_rects, rock_scale)
			if rect.has_area():
				rock_rects.append(rect)
	if randf() < CLUSTER_CHUNK_CHANCE:
		_place_crystal_cluster(chunk, rock_rects,
			FAR_CLUSTER_MIN if far else CLUSTER_MIN,
			FAR_CLUSTER_MAX if far else CLUSTER_MAX)
	# Gold is rarer and stays scattered: a single or a pair (richer far out).
	if randf() < (FAR_GOLD_CHANCE if far else GOLD_CHUNK_CHANCE):
		var gold_count := (2 if randf() < FAR_GOLD_PAIR_CHANCE else 1) if far \
			else randi_range(1, 2)
		for i in gold_count:
			_place_gold(chunk, rock_rects)

## One large organic mass. The rock generates its own outline; we pick an
## anchor snapped to the 32px build lattice (so walls butt up cleanly) that
## keeps the outline bbox inside the chunk, and reject on player/starter/rock
## overlap. `cell_scale` doubles the template cell (96 -> 192px); only shapes
## whose scaled bbox fits the chunk-with-margins are drawn from, and if none
## fit the scale clamps back to 1. Returns the world-space outline bbox, or a
## zero Rect2 if no spot worked.
func _place_rock_formation(chunk: Vector2i, existing: Array[Rect2], cell_scale := 1) -> Rect2:
	var origin := Vector2(chunk) * CHUNK_SIZE
	var chunk_rect := Rect2(origin, Vector2(CHUNK_SIZE, CHUNK_SIZE)).grow(-ROCK_EDGE_MARGIN)
	var fit := _fitting_shapes(chunk_rect.size, cell_scale)
	if fit.is_empty():
		cell_scale = 1
		fit = _fitting_shapes(chunk_rect.size, cell_scale)
	if fit.is_empty():
		return Rect2()
	for attempt in ROCK_ATTEMPTS:
		var rock = rock_scene.instantiate()
		rock.generate(fit.pick_random(), -1, cell_scale)
		var bounds: Rect2 = rock.bounds
		var slack := chunk_rect.size - bounds.size
		var anchor: Vector2 = chunk_rect.position - bounds.position \
			+ Vector2(randf() * slack.x, randf() * slack.y)
		anchor = anchor.snapped(Vector2(ROCK_TILE, ROCK_TILE))
		var rect := Rect2(anchor + bounds.position, bounds.size)
		if _overlaps_spawn_fan(rect.grow(DEPOSIT_PLAYER_CLEARANCE)) or _overlaps_starter(rect) \
				or _overlaps_rects(rect.grow(ROCK_DEPOSIT_CLEARANCE), existing):
			rock.free()
			continue
		rock.position = anchor
		add_child(rock)
		return rect
	return Rect2()

## Template indices whose scaled bbox fits `avail` in any spin (avail is the
## square chunk-with-margins, so the longest side is the only thing to check).
func _fitting_shapes(avail: Vector2, cell_scale: int) -> Array[int]:
	var out: Array[int] = []
	for i in Rock.SHAPES.size():
		var dims: Vector2i = Rock.shape_cell_dims(i)
		if float(maxi(dims.x, dims.y)) * Rock.CELL * cell_scale <= minf(avail.x, avail.y):
			out.append(i)
	return out

func _overlaps_rects(rect: Rect2, rects: Array[Rect2]) -> bool:
	for r in rects:
		if rect.intersects(r):
			return true
	return false

## Deterministic stand-in for the old live-player clearance: world gen must
## be identical on every peer (Phase 4), so it may only depend on the seed
## and the fixed spawn fan. Safe: a chunk always seeds while every player is
## >= 1 full chunk (1024px) away — except the initial ring around the spawn,
## which exactly these points cover.
func _spawn_fan_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in Net.MAX_PLAYERS:
		out.append(PLAYER_SPAWN + Vector2(SPAWN_SPACING * i, 0))
	return out

func _overlaps_spawn_fan(rect: Rect2) -> bool:
	for p in _spawn_fan_points():
		if rect.has_point(p):
			return true
	return false

## Normal chunk rocks keep off the guaranteed starter placements.
func _overlaps_starter(rect: Rect2) -> bool:
	for srect in _starter_rects:
		if rect.grow(ROCK_DEPOSIT_CLEARANCE).intersects(srect):
			return true
	return false

## Mineral line: crystals along a shallow arc bowing toward a random facing,
## ~48px apart (miners need >=40px) with slight jitter. Retries a few
## anchors; a chunk crowded by rocks or the player just goes without.
## `cmin`/`cmax` size the line (far chunks pass richer counts).
func _place_crystal_cluster(chunk: Vector2i, rock_rects: Array[Rect2],
		cmin := CLUSTER_MIN, cmax := CLUSTER_MAX) -> void:
	var origin := Vector2(chunk) * CHUNK_SIZE
	for attempt in CLUSTER_ATTEMPTS:
		var center := origin + Vector2(randf_range(200.0, CHUNK_SIZE - 200.0), randf_range(200.0, CHUNK_SIZE - 200.0))
		if _try_crystal_line(center, rock_rects, cmin, cmax).has_area():
			return

## One mineral-line attempt arcing around `center`; places the deposits and
## returns their padded bbox, or a zero Rect2 when a position was blocked.
func _try_crystal_line(center: Vector2, rock_rects: Array[Rect2],
		cmin := CLUSTER_MIN, cmax := CLUSTER_MAX) -> Rect2:
	var count := randi_range(cmin, cmax)
	var step := CLUSTER_SPACING / CLUSTER_ARC_RADIUS
	var facing := randf() * TAU
	var arc_center := center + Vector2.from_angle(facing) * CLUSTER_ARC_RADIUS
	var positions: Array[Vector2] = []
	for i in count:
		var a := facing + PI + (float(i) - float(count - 1) / 2.0) * step
		var pos := arc_center + Vector2.from_angle(a) * CLUSTER_ARC_RADIUS \
			+ Vector2(randf_range(-CLUSTER_JITTER, CLUSTER_JITTER), randf_range(-CLUSTER_JITTER, CLUSTER_JITTER))
		if not _deposit_pos_clear(pos, rock_rects):
			return Rect2()
		positions.append(pos)
	var rect := Rect2(positions[0], Vector2.ZERO)
	for pos in positions:
		rect = rect.expand(pos)
		var deposit = deposit_scene.instantiate()
		deposit.global_position = pos
		add_child(deposit)
	return rect.grow(16.0)

func _place_gold(chunk: Vector2i, rock_rects: Array[Rect2]) -> void:
	for attempt in 4:
		var pos := Vector2(chunk) * CHUNK_SIZE + Vector2(randf_range(80.0, CHUNK_SIZE - 80.0), randf_range(80.0, CHUNK_SIZE - 80.0))
		if not _deposit_pos_clear(pos, rock_rects):
			continue
		var deposit = gold_deposit_scene.instantiate()
		deposit.global_position = pos
		add_child(deposit)
		return

## Rock clearance is bbox + margin — approximate, but formations are convex
## enough at seeding scale that exact point-in-poly isn't worth it.
func _deposit_pos_clear(pos: Vector2, rock_rects: Array[Rect2]) -> bool:
	## Clearance against the deterministic spawn fan only (see
	## _spawn_fan_points): live-player positions would desync world gen.
	for p in _spawn_fan_points():
		if pos.distance_to(p) < DEPOSIT_PLAYER_CLEARANCE:
			return false
	for rect in rock_rects + _starter_rects:
		if rect.grow(ROCK_DEPOSIT_CLEARANCE).has_point(pos):
			return false
	return true

func _on_enemy_killed(points: int) -> void:
	score += points
	_hud.update_score(score)

## Offline: instant game over, unchanged. Online: the dead player spectates
## (player.gd); the host declares game over only on a team wipe.
func _on_player_died() -> void:
	if not Net.is_online():
		_hud.show_game_over(score, _wave_manager.wave)
		get_tree().paused = true
		return
	if Net.is_host():
		_check_team_wipe()

func _check_team_wipe() -> void:
	if _players.get_child_count() == 0:
		return
	for player in _players.get_children():
		if not player.is_queued_for_deletion() and not player.dead:
			return
	_rpc_game_over.rpc(score, _wave_manager.wave)

@rpc("authority", "call_local", "reliable")
func _rpc_game_over(final_score: int, wave: int) -> void:
	_hud.show_game_over(final_score, wave)
	get_tree().paused = true

## -- Phase 7: respawn, restart vote, host pause, disconnects, late join --

## Host: intermission start revives every dead player beside a living teammate
## (team wipe would already have ended the run) and admits held late joiners.
func _on_intermission_started(_seconds: float) -> void:
	if not Net.is_online() or not Net.is_host():
		return
	var living: Array = []
	var fallen: Array = []
	for player in _players.get_children():
		if player.is_queued_for_deletion():
			continue
		(fallen if player.dead else living).append(player)
	if not living.is_empty():
		for i in fallen.size():
			fallen[i].revive_at(living[0].global_position + Vector2(SPAWN_SPACING * (i + 1), 0))
	Net.release_late_joiners()

## Host game-over vote: everyone reloads with a fresh seed; the Net session
## stays up, so the scene-ready handshake re-runs like a normal start.
@rpc("authority", "call_local", "reliable")
func _rpc_restart(new_seed: int) -> void:
	Net.run_seed = new_seed
	get_tree().paused = false
	if Net.is_host():
		get_tree().reload_current_scene()
		return
	## Clients reload a beat later so the host teardown's despawn packets land
	## in the old tree instead of erroring against the reloaded one; pausing
	## also stops our synchronizers chattering at the host's fresh scene.
	get_tree().paused = true
	await get_tree().create_timer(0.3).timeout
	get_tree().paused = false
	get_tree().reload_current_scene()

## Host-only pause: engine pause is local, so the host replicates the flag.
@rpc("authority", "call_local", "reliable")
func _rpc_set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_hud.set_pause_panel(paused)

@rpc("authority", "call_remote", "reliable")
func _rpc_set_score(value: int) -> void:
	score = value
	_hud.update_score(score)

## Host: despawn players whose peer left the registry (spawner replicates the
## free); a wipe among the remaining players must still end the run.
func _prune_leavers() -> void:
	if not _players_spawned:
		return
	var pruned := false
	for player in _players.get_children():
		if not Net.players.has(str(player.name).to_int()):
			player.queue_free()
			pruned = true
	if pruned:
		call_deferred("_check_team_wipe")

## Client: the host vanished — freeze, tell the player, offer the menu.
func _on_session_ended(reason: String) -> void:
	get_tree().paused = true
	_hud.show_session_end(reason)

## Host: spawn a late joiner's player (called from Net after registration; the
## client already holds the full scene via spawner catch-up replication).
func spawn_late_joiner(peer_id: int) -> void:
	if not Net.is_host() or _players.has_node(str(peer_id)):
		return
	_ready_peers[peer_id] = true
	var pos := PLAYER_SPAWN
	for player in _players.get_children():
		if not player.dead and not player.is_queued_for_deletion():
			pos = player.global_position + Vector2(SPAWN_SPACING, 0)
			break
	_spawner.spawn([peer_id, pos])
	## State catch-up: economy mirror, score, wave counter (+ live counts).
	GameState._sync_dirty = true
	_rpc_set_score.rpc_id(peer_id, score)
	if _wave_manager.wave > 0:
		_wave_manager._rpc_wave_started.rpc_id(peer_id, _wave_manager.wave)
		_wave_manager._remaining_dirty = true
	_sync_building_hp(peer_id)
	_replay_miners(peer_id)

## Late join: spawner catch-up rebuilds buildings at FULL health (the spawn
## payload is fixed at spawn time), so pre-damaged HP ships as one batched RPC.
## Spawner-assigned node names match across peers; max_health rides along
## because the joiner's _ready computed it from a not-yet-synced upgrade mirror.
func _sync_building_hp(peer_id: int) -> void:
	var damaged := {}
	for building in $Buildings.get_children():
		if not building.is_queued_for_deletion() and building.health < building.max_health:
			damaged[String(building.name)] = [building.health, building.max_health]
	if not damaged.is_empty():
		_rpc_sync_building_hp.rpc_id(peer_id, damaged)

## Host -> late joiner: [health, max_health] per pre-damaged building.
@rpc("authority", "call_remote", "reliable")
func _rpc_sync_building_hp(damaged: Dictionary) -> void:
	for bname in damaged:
		var building = $Buildings.get_node_or_null(NodePath(bname))
		if building != null:
			building.max_health = int(damaged[bname][1])
			building._rpc_set_health(int(damaged[bname][0]))

## Miners replicate by deposit-position events, not the spawner — replay them
## once the joiner's chunk gen has caught up around the spawned players.
func _replay_miners(peer_id: int) -> void:
	await get_tree().create_timer(1.0, false).timeout
	if not Net.players.has(peer_id):
		return
	var controller = _players.get_node_or_null("1/BuildController")
	if controller == null:
		return
	for deposit in get_tree().get_nodes_in_group("deposits"):
		if deposit.has_miner:
			controller._rpc_spawn_miner.rpc_id(peer_id, deposit.global_position)
