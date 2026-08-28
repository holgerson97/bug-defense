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
var _tooltip
var _place_shape
var _place_params
var _drag_origin := Vector2.INF
var _drag_cells: Dictionary = {}
var _snap_enabled := true

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
	_tooltip = Label.new()
	_tooltip.position = Vector2(26, 18)
	_tooltip.z_index = 51
	_tooltip.add_theme_font_size_override("font_size", 12)
	_tooltip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_tooltip.add_theme_constant_override("outline_size", 4)
	_ghost.add_child(_tooltip)
	add_child(_ghost)
	_place_shape = RectangleShape2D.new()
	_place_params = PhysicsShapeQueryParameters2D.new()
	_place_params.shape = _place_shape
	_place_params.collision_mask = PLACE_QUERY_MASK
	_place_params.collide_with_areas = false

## Handles placement input and the ghost for the currently selected item.
func tick(selected: String) -> void:
	if Input.is_action_just_pressed("toggle_grid"):
		_snap_enabled = not _snap_enabled
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
	if not GameState.spend(GameState.BUILDINGS["miner"]["cost"]):
		return
	var miner = miner_scene.instantiate()
	miner.deposit = target
	target.has_miner = true
	target.add_child(miner)
	Sfx.play("place", target.global_position)

func _build_position(id: String) -> Vector2:
	var pos := get_global_mouse_position()
	# Walls always tile to the grid; everything else follows the X toggle.
	if id == "wall" or _snap_enabled:
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

## Hold-and-drag: the first click places at the cursor; dragging then fills a
## straight row locked to the dominant axis (X or Y) from that origin. Bigger
## buildings space themselves out naturally — intermediate cells that overlap
## an already-placed one simply fail the placement check.
func _drag_place(id: String) -> void:
	var target := _build_position(id)
	if _drag_origin == Vector2.INF:
		if _try_drag_cell(id, target):
			_drag_origin = target
		return
	var delta := get_global_mouse_position() - _drag_origin
	var locked := _drag_origin
	if absf(delta.x) >= absf(delta.y):
		locked.x = target.x
	else:
		locked.y = target.y
	var dist := _drag_origin.distance_to(locked)
	if dist < WALL_GRID * 0.5:
		return
	var dir := (locked - _drag_origin) / dist
	for i in int(dist / WALL_GRID) + 1:
		_try_drag_cell(id, _drag_origin + dir * WALL_GRID * i)

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
	_update_tooltip(selected, pos, valid)
	_ghost.global_position = pos
	_ghost.visible = true

func _update_tooltip(id: String, pos: Vector2, valid: bool) -> void:
	var b: Dictionary = GameState.BUILDINGS[id]
	var text := "%s  (%s)\nGrid snap: %s  [X]" % [b["name"], Util.cost_text(b["cost"]), "on" if _snap_enabled else "off"]
	if not valid:
		if not GameState.can_afford(b["cost"]):
			text += "\nNot enough resources"
		elif _player.global_position.distance_to(pos) > BUILD_RANGE:
			text += "\nToo far away"
		else:
			text += "\nBlocked"
	_tooltip.text = text
	_tooltip.modulate = Color(1, 1, 1, 1) if valid else Color(1, 0.75, 0.75, 1)

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
