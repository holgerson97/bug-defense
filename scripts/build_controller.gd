extends Node2D
## Building placement for the player: ghost preview with tower range rings
## (directional towers show a facing wedge, rotated in 45° steps with R),
## drag-painted walls, miner deposit-snapping, and per-placement costs.
## The player calls tick(selected) every physics frame.

const MINER_PLACE_RANGE := 80.0
const WALL_GRID := 16.0
const GHOST_MARGIN := 1.0
# Placement collides against player (1), ground enemies (2), deposits (16)
# and buildings (32) — no building on top of any of them.
const PLACE_QUERY_MASK := 1 | 2 | 16 | 32
const BUILDING_SCENES := {
	"wall": preload("res://scenes/wall.tscn"),
	"mg_tower": preload("res://scenes/mg_tower.tscn"),
	"grenade_tower": preload("res://scenes/grenade_tower.tscn"),
	"repair_tower": preload("res://scenes/repair_tower.tscn"),
	"tesla_tower": preload("res://scenes/tesla_tower.tscn"),
	"flame_tower": preload("res://scenes/flame_tower.tscn"),
	"aa_tower": preload("res://scenes/aa_tower.tscn"),
	"solar_panel": preload("res://scenes/solar_panel.tscn"),
	"command_center": preload("res://scenes/command_center.tscn"),
	"light_pole": preload("res://scenes/light_pole.tscn"),
	"searchlight": preload("res://scenes/searchlight.tscn"),
	"battery": preload("res://scenes/battery.tscn"),
	"power_pole": preload("res://scenes/power_pole.tscn"),
	"intake_station": preload("res://scenes/intake_station.tscn"),
	"cooling_tower": preload("res://scenes/cooling_tower.tscn"),
}
## Footprints on the shared 16px lattice: utility 32, walls/turrets 48 (1.5x),
## large structures 64 — all multiples of the base step so everything tiles.
const BUILDING_FOOTPRINT := {"wall": 48.0, "mg_tower": 48.0, "grenade_tower": 48.0, "repair_tower": 48.0, "tesla_tower": 48.0, "flame_tower": 48.0, "aa_tower": 48.0, "solar_panel": 32.0, "command_center": 64.0, "light_pole": 32.0, "searchlight": 32.0, "battery": 32.0, "power_pole": 32.0, "intake_station": 64.0, "cooling_tower": 32.0}
## Placement query shrinks by this so flush neighbors don't block placement.
const PLACE_EPSILON := 2.0
const GHOST_VALID := Color(0.35, 1.0, 0.45, 0.45)
const GHOST_INVALID := Color(1.0, 0.3, 0.3, 0.45)

var build_range: float = Balance.num("player/build_range", 300.0)
## Fraction of the cost refunded on right-click sell.
var sell_refund: float = Balance.num("upgrades/economy/sell_refund", 0.5)

var miner_scene: PackedScene = preload("res://scenes/miner.tscn")
var _ghost
var _ghost_dir
var _ghost_poly
var _ghost_range_poly
var _ghost_range_line
var _ghost_item: String = ""
var _ghost_rotation := 0.0
var _tooltip
var _place_shape
var _place_params
var _drag_origin := Vector2.INF
var _drag_cells: Dictionary = {}
var _snap_enabled := true

@onready var _player = get_parent()

func _ready() -> void:
	_build_ghost()
	## Buying Extended Barrels mid-placement must refresh the preview ring.
	GameState.upgrades_changed.connect(_on_upgrades_changed)

func _on_upgrades_changed() -> void:
	if _ghost_item != "":
		_update_range_ring(_ghost_item)

func _build_ghost() -> void:
	_ghost = Node2D.new()
	_ghost.top_level = true
	_ghost.visible = false
	_ghost.z_index = 50
	# Range shapes live on a rotatable child so R can spin the wedge/spot.
	_ghost_dir = Node2D.new()
	_ghost.add_child(_ghost_dir)
	_ghost_range_poly = Polygon2D.new()
	_ghost_range_poly.color = Color(0.5, 0.8, 1.0, 0.07)
	_ghost_dir.add_child(_ghost_range_poly)
	_ghost_range_line = Line2D.new()
	_ghost_range_line.width = 2.0
	_ghost_range_line.default_color = Color(0.5, 0.8, 1.0, 0.35)
	_ghost_range_line.closed = true
	_ghost_dir.add_child(_ghost_range_line)
	_ghost_poly = Polygon2D.new()
	_ghost.add_child(_ghost_poly)
	_tooltip = Label.new()
	_tooltip.position = Vector2(26, 18)
	_tooltip.z_index = 51
	_tooltip.add_theme_font_size_override("font_size", 12)
	_tooltip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_tooltip.add_theme_constant_override("outline_size", 4)
	_ghost.add_child(_tooltip)
	# The night's CanvasModulate would swallow the ghost; a follow-viewport
	# CanvasLayer keeps it in world coordinates on an unmodulated canvas.
	var layer := CanvasLayer.new()
	layer.follow_viewport_enabled = true
	add_child(layer)
	layer.add_child(_ghost)
	_place_shape = RectangleShape2D.new()
	_place_params = PhysicsShapeQueryParameters2D.new()
	_place_params.shape = _place_shape
	_place_params.collision_mask = PLACE_QUERY_MASK
	_place_params.collide_with_areas = false

## Handles placement input and the ghost for the currently selected item.
func tick(selected: String) -> void:
	if Input.is_action_just_pressed("toggle_grid"):
		_snap_enabled = not _snap_enabled
	if Input.is_action_just_pressed("sell"):
		_try_sell_building()
	if BUILDING_SCENES.has(selected) and Input.is_action_just_pressed("rotate_building"):
		_ghost_rotation = wrapf(_ghost_rotation + TAU / 8.0, 0.0, TAU)
	if selected == "miner" and Input.is_action_just_pressed("shoot"):
		_try_place_miner()
	elif BUILDING_SCENES.has(selected) and Input.is_action_pressed("shoot"):
		_drag_place(selected)
	if not Input.is_action_pressed("shoot"):
		_drag_origin = Vector2.INF
		_drag_cells.clear()
	_update_ghost(selected)

func _try_place_miner() -> void:
	var mouse := get_global_mouse_position()
	var target = Util.nearest_in_group(self, "deposits", mouse, MINER_PLACE_RANGE)
	if target == null or target.has_miner:
		return
	## Online clients send the deposit POSITION as the intent key: generated
	## deposits have order-dependent node names (paths differ per peer), but
	## deterministic world gen makes positions match everywhere.
	if Net.is_online() and not Net.is_host():
		_rpc_place_miner.rpc_id(1, target.global_position)
		return
	_place_miner_at(target.global_position)

## Host/offline: resolve the deposit by position, pay, attach, replicate.
func _place_miner_at(deposit_pos: Vector2) -> void:
	var target = Util.nearest_in_group(self, "deposits", deposit_pos, 16.0)
	if target == null or target.has_miner:
		return
	if not GameState.spend(GameState.BUILDINGS["miner"]["cost"]):
		return
	_attach_miner(target)
	if Net.is_online():
		_rpc_spawn_miner.rpc(target.global_position)

func _attach_miner(target) -> void:
	var miner = miner_scene.instantiate()
	miner.deposit = target
	target.has_miner = true
	target.add_child(miner)
	Sfx.play("place", target.global_position)

func _build_position(id: String) -> Vector2:
	var pos := get_global_mouse_position()
	## Walls always tile to the grid; everything else follows the X toggle.
	if id != "wall" and not _snap_enabled:
		return pos
	## Snap the footprint's corner to the 16px lattice so every size (32/48/64
	## — all multiples of the step) tiles flush against every other.
	var half: Vector2 = Vector2.ONE * (BUILDING_FOOTPRINT[id] / 2.0)
	return (pos - half).snapped(Vector2(WALL_GRID, WALL_GRID)) + half

func _placement_valid(id: String, pos: Vector2) -> bool:
	if not GameState.can_afford(GameState.BUILDINGS[id]["cost"]):
		return false
	if _player.global_position.distance_to(pos) > build_range * GameState.build_range_mult():
		return false
	## Query slightly inside the footprint so flush neighbors don't collide.
	var query: float = BUILDING_FOOTPRINT[id] - PLACE_EPSILON
	_place_shape.size = Vector2(query, query)
	_place_params.transform = Transform2D(0.0, pos)
	var hits: Array = get_world_2d().direct_space_state.intersect_shape(_place_params, 1)
	return hits.is_empty()

## Right-click a building to sell it for half its cost. The building id is
## derived from its scene file name (e.g. mg_tower.tscn -> "mg_tower").
func _try_sell_building() -> void:
	## Online clients send a sell intent; the host resolves + refunds.
	if Net.is_online() and not Net.is_host():
		_rpc_sell_building.rpc_id(1, get_global_mouse_position())
		return
	_sell_at(get_global_mouse_position())

## Host/offline: resolve the building under `pos`, refund half, free it (the
## host's queue_free despawns replicated buildings on every client).
func _sell_at(pos: Vector2) -> void:
	var params := PhysicsPointQueryParameters2D.new()
	params.position = pos
	params.collision_mask = 32
	var hits: Array = get_world_2d().direct_space_state.intersect_point(params, 1)
	if hits.is_empty():
		return
	var building = hits[0]["collider"]
	var id: String = building.scene_file_path.get_file().get_basename()
	if not GameState.BUILDINGS.has(id):
		return
	var cost: Dictionary = GameState.BUILDINGS[id]["cost"]
	for kind in cost:
		GameState.add_resource(kind, int(cost[kind] * sell_refund))
	_sell_fx(building.global_position)
	if Net.is_online():
		_rpc_sell_fx.rpc(building.global_position)
	building.queue_free()

func _sell_fx(pos: Vector2) -> void:
	Effects.debris_burst(self, pos)
	Sfx.play("place", pos, -4.0)

func _try_place_building_at(id: String, pos: Vector2) -> bool:
	if not _placement_valid(id, pos):
		return false
	## Online client: reliable intent up, optimistic true (keeps drag rows
	## responsive; the host revalidates cost/range/occupancy and spawns).
	if Net.is_online() and not Net.is_host():
		_rpc_place_building.rpc_id(1, id, pos, _ghost_rotation)
		return true
	if not GameState.spend(GameState.BUILDINGS[id]["cost"]):
		return false
	if Net.is_online():
		## Host: spawn through the replicating BuildingSpawner (plays the
		## place sfx in its spawn_function on every peer).
		get_tree().current_scene.spawn_building(id, pos, _ghost_rotation)
	else:
		var building = BUILDING_SCENES[id].instantiate()
		building.global_position = pos
		building.facing = _ghost_rotation
		get_tree().current_scene.add_child(building)
		Sfx.play("place", pos)
	return true

## Hold-and-drag: the first click places at the cursor; dragging then fills a
## straight row locked to the dominant axis (X or Y) from that origin,
## stepping by the building's cell size so 2x2 buildings tile flush too.
func _drag_place(id: String) -> void:
	var target := _build_position(id)
	if _drag_origin == Vector2.INF:
		if _try_drag_cell(id, target):
			_drag_origin = target
		return
	var step: float = BUILDING_FOOTPRINT[id]
	var delta := get_global_mouse_position() - _drag_origin
	var locked := _drag_origin
	if absf(delta.x) >= absf(delta.y):
		locked.x = target.x
	else:
		locked.y = target.y
	var dist := _drag_origin.distance_to(locked)
	if dist < step * 0.5:
		return
	var dir := (locked - _drag_origin) / dist
	for i in int(dist / step) + 1:
		_try_drag_cell(id, _drag_origin + dir * step * i)

func _try_drag_cell(id: String, cell: Vector2) -> bool:
	if _drag_cells.has(cell):
		return false
	if not _try_place_building_at(id, cell):
		return false
	_drag_cells[cell] = true
	return true

func _update_ghost(selected: String) -> void:
	if not BUILDING_SCENES.has(selected):
		_ghost.visible = false
		return
	if selected != _ghost_item:
		_ghost_item = selected
		_update_range_ring(selected)
	var pos := _build_position(selected)
	var half: float = BUILDING_FOOTPRINT[selected] / 2.0 + GHOST_MARGIN
	_ghost_poly.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)
	])
	var valid := _placement_valid(selected, pos)
	_ghost_poly.color = GHOST_VALID if valid else GHOST_INVALID
	_ghost_dir.rotation = _ghost_rotation
	_update_tooltip(selected, pos, valid)
	_ghost.global_position = pos
	_ghost.visible = true

func _update_tooltip(id: String, pos: Vector2, valid: bool) -> void:
	var b: Dictionary = GameState.BUILDINGS[id]
	var text := "%s  (%s)\nGrid snap: %s  [X]" % [b["name"], Util.cost_text(b["cost"]), "on" if _snap_enabled else "off"]
	if b.has("arc") or b.has("cone"):
		text += "\nRotate: [R]"
	if not valid:
		if not GameState.can_afford(b["cost"]):
			text += "\nNot enough resources"
		elif _player.global_position.distance_to(pos) > build_range * GameState.build_range_mult():
			text += "\nToo far away"
		else:
			text += "\nBlocked"
	_tooltip.text = text
	_tooltip.modulate = Color(1, 1, 1, 1) if valid else Color(1, 0.75, 0.75, 1)

## RTS-style range preview while placing a tower: a facing wedge for
## directional towers, beam cone + sweep arc for the searchlight, and a
## plain circle for omnidirectional ranges.
func _update_range_ring(id: String) -> void:
	var b: Dictionary = GameState.BUILDINGS[id]
	var radius: float = b.get("range", 0.0)
	## Extended Barrels scales tower attack/heal ranges only — not the
	## searchlight cone or power coverage radii. The "tower" capability flag
	## in BUILDINGS marks combat towers; never sniff the id string.
	if b.get("tower", false):
		radius *= GameState.tower_range_mult()
	if radius <= 0.0:
		_ghost_range_poly.polygon = PackedVector2Array()
		_ghost_range_line.points = PackedVector2Array()
		return
	if b.has("cone"):
		# Searchlight: the poly is the beam cone at the facing, the line traces
		# the "sweep" arc it ping-pongs across (BUILDINGS is the single source;
		# mirrors SWEEP_HALF_ARC in searchlight.gd) — rotating moves both.
		var half_cone: float = deg_to_rad(b["cone"]) / 2.0
		var cone := PackedVector2Array()
		cone.append(Vector2.ZERO)
		for i in 24:
			cone.append(Vector2.from_angle(-half_cone + half_cone * 2.0 * i / 23.0) * radius)
		var half_sweep: float = deg_to_rad(b.get("sweep", 140.0)) / 2.0
		var sweep := PackedVector2Array()
		for i in 25:
			sweep.append(Vector2.from_angle(-half_sweep + half_sweep * 2.0 * i / 24.0) * radius)
		_ghost_range_line.closed = false
		_ghost_range_line.points = sweep
		_ghost_range_poly.polygon = cone
		return
	_ghost_range_line.closed = true
	var points := PackedVector2Array()
	if b.has("arc"):
		# Directional tower: wedge sector centered on the facing.
		var half: float = deg_to_rad(b["arc"]) / 2.0
		points.append(Vector2.ZERO)
		for i in 24:
			points.append(Vector2.from_angle(-half + half * 2.0 * i / 23.0) * radius)
	else:
		for i in 48:
			points.append(Vector2.from_angle(TAU * i / 48.0) * radius)
	_ghost_range_poly.polygon = points
	_ghost_range_line.points = points

## -- MP RPCs (Phase 4): placement/sell/miner intents up, spawn events down.
## This controller exists on every peer under the same player node path, so
## the host handles a client's intent on its copy of that client's controller
## — _placement_valid's range check reads the puppet's synced position and
## the occupancy query runs against the host's own physics space.

@rpc("any_peer", "call_remote", "reliable")
func _rpc_place_building(id: String, pos: Vector2, facing: float) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	if not BUILDING_SCENES.has(id) or not _placement_valid(id, pos):
		return
	if not GameState.spend(GameState.BUILDINGS[id]["cost"]):
		return
	get_tree().current_scene.spawn_building(id, pos, facing)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_sell_building(pos: Vector2) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_sell_at(pos)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_place_miner(deposit_pos: Vector2) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_place_miner_at(deposit_pos)

## Host -> clients: sell debris/sfx (the spawner despawn itself is silent).
## any_peer + sender guard, NOT "authority": this node's authority is its
## OWNING PEER, so a host broadcast from a client-owned controller (client
## sell intent) would be rejected by every receiver (soak-test find).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_sell_fx(pos: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_sell_fx(pos)

## Host -> clients: attach a miner to the deposit at `deposit_pos`. Miners
## replicate via this spawn event instead of the BuildingSpawner because they
## are CHILDREN of their deposit (locally generated, order-dependent node
## names) — a spawner can't target those parents path-safely, positions can.
## any_peer + sender guard for the same reason as _rpc_sell_fx above.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_spawn_miner(deposit_pos: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var target = Util.nearest_in_group(self, "deposits", deposit_pos, 16.0)
	if target == null or target.has_miner:
		return
	_attach_miner(target)
