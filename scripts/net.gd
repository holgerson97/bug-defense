extends Node
## Autoload: network seam. Owns the MultiplayerPeer (ENet for LAN, Steam later)
## and the replicated player registry. Nothing else touches the transport.
## No peer set = offline: the game behaves exactly like single-player.

signal player_list_changed
signal session_ended(reason: String)
## Lobby status line for a client held in the auth phase (game in progress).
signal late_join_status(message: String)

const DEFAULT_PORT := 4514
const MAX_PLAYERS := 4
## Preset player colors, assigned by join order (host = first).
const PLAYER_COLORS: Array[Color] = [
	Color(0.55, 0.82, 1.0),
	Color(0.4, 0.9, 0.55),
	Color(1.0, 0.75, 0.35),
	Color(0.9, 0.5, 0.9),
]

## peer_id -> {"name": String, "color": Color, "class": String}. Host-
## authoritative; the full registry is re-broadcast (reliable) on every change.
var players: Dictionary = {}

## Local player's chosen class id: persisted via Settings, carried into the
## registry when hosting/registering. Offline (zero peers, empty registry)
## player_class() serves it directly to the spawned player node.
var local_class: String = "assault"

## World-gen seed for the current run: the host rolls it at game start and the
## start RPC carries it, so every peer derives identical chunk/starter terrain
## (MP plan Phase 4). Offline runs ignore it (main.gd rolls its own).
var run_seed: int = 0

## Local world pick (persisted via Settings). HOST-scoped in co-op: only the
## host's pick matters — it shows in the lobby via the host's registry entry
## and rides the start RPC / late-join auth as `run_world`.
var local_world: String = "grasslands"
## World id for the current online run (set by the start RPC alongside the
## seed; restarts keep it — _rpc_restart only rerolls the seed). "" offline.
var run_world: String = ""

## True from the start RPC until the session drops: gates the late-join hold.
var game_running := false
## Client: joined a running game; main.gd skips the normal ready handshake
## (the host spawns us after registration instead).
var late_joining := false

var _peer: ENetMultiplayerPeer = null
## Host: peers held in the auth phase until the next intermission.
var _waiting_auth: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	## Phase 7 late join: every connection runs through SceneMultiplayer auth.
	## The connection (and thus spawner catch-up replication) only completes
	## once the client has the game scene loaded — so a late joiner receives
	## every already-spawned player/building/enemy into a matching tree.
	multiplayer.auth_callback = _on_auth_received
	multiplayer.auth_timeout = 0.0
	multiplayer.peer_authenticating.connect(_on_peer_authenticating)
	multiplayer.peer_authentication_failed.connect(_on_peer_auth_failed)
	local_class = Settings.player_class
	if not GameState.CLASSES.has(local_class):
		local_class = GameState.CLASSES.keys()[0]
	local_world = Settings.world
	if not GameState.WORLDS.is_empty() and not GameState.WORLDS.has(local_world):
		local_world = "grasslands" if GameState.WORLDS.has("grasslands") else GameState.WORLDS.keys()[0]

## True offline (OfflineMultiplayerPeer acts as server) and when hosting.
func is_host() -> bool:
	return _peer == null or multiplayer.is_server()

## True while hosting or joined/joining a session.
func is_online() -> bool:
	return _peer != null

func host(port := DEFAULT_PORT, max_players := MAX_PLAYERS) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players - 1)
	if err != OK:
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	var host_name := _os_name()
	## "world" only rides the host's entry: the lobby's shared-world display.
	players[1] = {"name": host_name if host_name != "" else "Player 1", "color": PLAYER_COLORS[0], "class": local_class, "world": local_world}
	player_list_changed.emit()
	return OK

func join(ip: String, port := DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	return OK

## Drop the session and return to offline. Emits no session_ended; callers that
## leave voluntarily already know why.
func leave() -> void:
	if _peer == null:
		return
	_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	game_running = false
	late_joining = false
	run_world = ""
	_waiting_auth.clear()
	player_list_changed.emit()

## Host-only: everyone (host included) switches to the game scene, seeded
## with one shared world-gen seed and the host's world pick.
func start_game() -> void:
	if not is_host():
		return
	_rpc_start_game.rpc(randi(), local_world)

## OS username, "" if unavailable (host substitutes "Player N").
func _os_name() -> String:
	var user := OS.get_environment("USER")
	if user == "":
		user = OS.get_environment("USERNAME")
	return user

## World id for the current run: online the host's pick (rode the start RPC or
## the late-join auth payload), offline the local menu pick. main.gd resolves
## it through GameState.world_def at scene start.
func world_id() -> String:
	if is_online() and run_world != "":
		return run_world
	return local_world

## Menu/lobby world pick. The world is HOST-scoped (one shared world per run):
## the pick persists locally, and while hosting a pre-game lobby it rides the
## host's registry entry so every client's lobby shows it. Clients never call
## this from the lobby (their picker is read-only); their single-player pick
## still persists for offline runs.
func set_local_world(id: String) -> void:
	if not GameState.WORLDS.has(id):
		return
	local_world = id
	Settings.world = id
	Settings.save_settings()
	if is_online() and is_host() and not game_running and players.has(1):
		players[1]["world"] = id
		_broadcast_players()
		player_list_changed.emit()

## Class id for a peer: registry entry when online, the local pick offline
## (single player runs with an empty registry). Missing key = assault.
func player_class(peer_id: int) -> String:
	if players.has(peer_id):
		return str(players[peer_id].get("class", "assault"))
	return local_class

## Menu/lobby class pick. Persists, and while in a lobby routes into the
## registry (host directly, clients via RPC — dropped by the host once the run
## starts, so a class is fixed at game start). A late joiner parked in the auth
## phase can't RPC yet; its pick rides _rpc_register when the hold lifts.
func set_local_class(cls: String) -> void:
	if not GameState.CLASSES.has(cls):
		return
	local_class = cls
	Settings.player_class = cls
	Settings.save_settings()
	if not is_online():
		return
	if is_host():
		if not game_running and players.has(1):
			players[1]["class"] = cls
			_broadcast_players()
			player_list_changed.emit()
	elif not multiplayer.get_peers().is_empty():
		_rpc_set_class.rpc_id(1, cls)

## First color not yet taken; join order decides.
func _next_color() -> Color:
	for color in PLAYER_COLORS:
		var taken := false
		for info in players.values():
			if info["color"] == color:
				taken = true
				break
		if not taken:
			return color
	return PLAYER_COLORS[players.size() % PLAYER_COLORS.size()]

func _end_session(reason: String) -> void:
	leave()
	session_ended.emit(reason)

## Host, at intermission start: let held late joiners in. They load the game
## scene, ack via auth, and only then does the connection (and the spawners'
## catch-up replication) complete.
func release_late_joiners() -> void:
	if not multiplayer.is_server():
		return
	for id in _waiting_auth:
		multiplayer.send_auth(id, var_to_bytes({"late": true, "seed": run_seed, "world": run_world}))
	_waiting_auth.clear()

## -- auth phase (late-join gate) --

func _on_peer_authenticating(id: int) -> void:
	if not multiplayer.is_server():
		return  ## Client: wait for the host's auth message.
	if game_running:
		_waiting_auth[id] = true
		multiplayer.send_auth(id, var_to_bytes({"wait": true}))
	else:
		multiplayer.send_auth(id, var_to_bytes({"late": false}))

func _on_auth_received(id: int, data: PackedByteArray) -> void:
	var msg = bytes_to_var(data)
	if not (msg is Dictionary):
		return
	if multiplayer.is_server():
		## Client acked (scene loaded when late): finish the handshake.
		if msg.get("ready", false):
			_waiting_auth.erase(id)
			multiplayer.complete_auth(id)
		return
	if msg.get("wait", false):
		late_join_status.emit("Game in progress — joining at next intermission")
	elif msg.get("late", false):
		late_joining = true
		run_seed = msg.get("seed", 0)
		run_world = str(msg.get("world", ""))
		_finish_late_join()
	else:
		## Normal pre-game join: ack immediately.
		multiplayer.send_auth(1, var_to_bytes({"ready": true}))
		multiplayer.complete_auth(1)

## Client: load the game scene FIRST, then ack — spawner catch-up packets
## arrive at peer_connected and need the matching tree to land in.
func _finish_late_join() -> void:
	late_join_status.emit("Joining...")
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	while get_tree().current_scene == null or get_tree().current_scene.name != "Main":
		await get_tree().process_frame
	multiplayer.send_auth(1, var_to_bytes({"ready": true}))
	multiplayer.complete_auth(1)

func _on_peer_auth_failed(id: int) -> void:
	if multiplayer.is_server():
		_waiting_auth.erase(id)
	else:
		_end_session("Connection failed")

## -- multiplayer signal handlers --

func _on_peer_connected(_id: int) -> void:
	# Registry entry waits for the client's _rpc_register name RPC.
	pass

func _on_peer_disconnected(id: int) -> void:
	_waiting_auth.erase(id)
	if multiplayer.is_server() and players.erase(id):
		_broadcast_players()
		player_list_changed.emit()

func _on_connected_to_server() -> void:
	_rpc_register.rpc_id(1, _os_name(), local_class)

func _on_connection_failed() -> void:
	_end_session("Connection failed")

func _on_server_disconnected() -> void:
	_end_session("Host disconnected")

## -- RPCs --

## Client -> host: announce name + class pick; host assigns color and
## re-broadcasts. Late joiners register at spawn time, so their class lands
## exactly once, right before the player node is created.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_register(player_name: String, cls := "assault") -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if player_name.strip_edges() == "":
		player_name = "Player %d" % (players.size() + 1)
	if not GameState.CLASSES.has(cls):
		cls = GameState.CLASSES.keys()[0]
	players[id] = {"name": player_name, "color": _next_color(), "class": cls}
	_broadcast_players()
	player_list_changed.emit()
	## Late joiner registering into a running game: the game scene spawns them.
	if game_running:
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("spawn_late_joiner"):
			scene.spawn_late_joiner(id)

## Client -> host: lobby class change. Locked once the run starts — class
## stats are baked into damage caps and spawned player stats, so a mid-run
## flip would desync; the host simply drops the request.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_class(cls: String) -> void:
	if not multiplayer.is_server() or game_running:
		return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id) or not GameState.CLASSES.has(cls):
		return
	players[id]["class"] = cls
	_broadcast_players()
	player_list_changed.emit()

func _broadcast_players() -> void:
	_rpc_sync_players.rpc(players)

## Host -> clients: full registry replace.
@rpc("authority", "call_remote", "reliable")
func _rpc_sync_players(registry: Dictionary) -> void:
	players = registry
	player_list_changed.emit()

@rpc("authority", "call_local", "reliable")
func _rpc_start_game(seed_value: int, world_id := "") -> void:
	run_seed = seed_value
	## Host-chosen world for the whole run. An id missing from a client's
	## balance.json degrades to the midnight fallback (world_def -> {}) —
	## visual-only, same as any other balance divergence.
	run_world = world_id
	game_running = true
	get_tree().change_scene_to_file("res://scenes/main.tscn")
