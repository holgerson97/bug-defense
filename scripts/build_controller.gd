extends Node2D
## Building placement for the player: ghost preview with tower range rings,
## drag-painted walls, miner deposit-snapping, and per-placement costs.
## The player calls tick(selected) every physics frame.

const MINER_PLACE_RANGE := 80.0
const BUILD_RANGE := 300.0
const WALL_GRID := 32.0
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
}
const BUILDING_FOOTPRINT := {"wall": 30.0, "mg_tower": 38.0, "grenade_tower": 38.0, "repair_tower": 38.0, "tesla_tower": 38.0, "flame_tower": 38.0, "aa_tower": 38.0, "solar_panel": 30.0, "command_center": 54.0}
const GHOST_VALID := Color(0.35, 1.0, 0.45, 0.45)
const GHOST_INVALID := Color(1.0, 0.3, 0.3, 0.45)

var miner_scene: PackedScene = preload("res://scenes/miner.tscn")
var _ghost
var _ghost_poly
var _ghost_range_poly
var _ghost_range_line
var _ghost_item: String = ""
var _place_shape
var _place_params
var _last_wall_cell := Vector2.INF
var _drag_cells: Dictionary = {}

@onready var _player = get_parent()

func _ready() -> void:
	_build_ghost()

func _build_ghost() -> void:
	_ghost = Node2D.new()
	_ghost.top_level = true
	_ghost.visible = false
	_ghost.z_index = 50
	_ghost_range_poly = Polygon2D.new()
	_ghost_range_poly.color = Color(0.5, 0.8, 1.0, 0.07)
	_ghost.add_child(_ghost_range_poly)
	_ghost_range_line = Line2D.new()
	_ghost_range_line.width = 2.0
	_ghost_range_line.default_color = Color(0.5, 0.8, 1.0, 0.35)
	_ghost_range_line.closed = true
	_ghost.add_child(_ghost_range_line)
	_ghost_poly = Polygon2D.new()
	_ghost.add_child(_ghost_poly)
	add_child(_ghost)
	_place_shape = RectangleShape2D.new()
	_place_params = PhysicsShapeQueryParameters2D.new()
	_place_params.shape = _place_shape
	_place_params.collision_mask = PLACE_QUERY_MASK
	_place_params.collide_with_areas = false

## Handles placement input and the ghost for the currently selected item.
func tick(selected: String) -> void:
	if selected == "miner" and Input.is_action_just_pressed("shoot"):
		_try_place_miner()
	elif BUILDING_SCENES.has(selected):
		if selected == "wall" and Input.is_action_pressed("shoot"):
			_drag_place_walls()
		elif Input.is_action_just_pressed("shoot"):
			_try_place_building(selected)
	if not Input.is_action_pressed("shoot"):
		_last_wall_cell = Vector2.INF
		_drag_cells.clear()
	_update_ghost(selected)

func _try_place_miner() -> void:
	var mouse := get_global_mouse_position()
	var target = Util.nearest_in_group(self, "deposits", mouse, MINER_PLACE_RANGE)
	if target == null or target.has_miner:
		return
	if not GameState.spend(GameState.BUILDINGS["miner"]["cost"]):
		return
	var miner = miner_scene.instantiate()
	miner.deposit = target
	target.has_miner = true
	target.add_child(miner)
	Sfx.play("place", target.global_position)

func _build_position(id: String) -> Vector2:
	var pos := get_global_mouse_position()
	if id == "wall":
		pos = pos.snapped(Vector2(WALL_GRID, WALL_GRID))
	return pos

func _placement_valid(id: String, pos: Vector2) -> bool:
	if not GameState.can_afford(GameState.BUILDINGS[id]["cost"]):
		return false
	if _player.global_position.distance_to(pos) > BUILD_RANGE:
		return false
	var footprint: float = BUILDING_FOOTPRINT[id]
	_place_shape.size = Vector2(footprint, footprint)
	_place_params.transform = Transform2D(0.0, pos)
	var hits: Array = get_world_2d().direct_space_state.intersect_shape(_place_params, 1)
	return hits.is_empty()

func _try_place_building(id: String) -> bool:
	return _try_place_building_at(id, _build_position(id))

func _try_place_building_at(id: String, pos: Vector2) -> bool:
	if not _placement_valid(id, pos):
		return false
	if not GameState.spend(GameState.BUILDINGS[id]["cost"]):
		return false
	var building = BUILDING_SCENES[id].instantiate()
	building.global_position = pos
	get_tree().current_scene.add_child(building)
	Sfx.play("place", pos)
	return true

## Hold-and-drag wall painting: fills every grid cell along the drag path.
func _drag_place_walls() -> void:
	var grid := Vector2(WALL_GRID, WALL_GRID)
	var target := _build_position("wall")
	if _last_wall_cell == Vector2.INF:
		if _try_wall_cell(target):
			_last_wall_cell = target
		return
	var dist := _last_wall_cell.distance_to(target)
	var samples := maxi(int(dist / (WALL_GRID * 0.5)), 1)
	for i in samples:
		var cell := _last_wall_cell.lerp(target, float(i + 1) / samples).snapped(grid)
		if _try_wall_cell(cell):
			_last_wall_cell = cell

func _try_wall_cell(cell: Vector2) -> bool:
	if _drag_cells.has(cell):
		return false
	if not _try_place_building_at("wall", cell):
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
	_ghost_poly.color = GHOST_VALID if _placement_valid(selected, pos) else GHOST_INVALID
	_ghost.global_position = pos
	_ghost.visible = true

## RTS-style range preview while placing a tower.
func _update_range_ring(id: String) -> void:
	var radius: float = GameState.BUILDINGS[id].get("range", 0.0)
	if radius <= 0.0:
		_ghost_range_poly.polygon = PackedVector2Array()
		_ghost_range_line.points = PackedVector2Array()
		return
	var points := PackedVector2Array()
	for i in 48:
		points.append(Vector2.from_angle(TAU * i / 48.0) * radius)
	_ghost_range_poly.polygon = points
	_ghost_range_line.points = points
