extends CharacterBody2D

signal died
signal health_changed(current: int, total: int)

@export var base_speed: float = 320.0
@export var base_fire_rate: float = 0.15

const Effects = preload("res://scripts/effects.gd")

const MINER_COST := {"scrap": 25}
const MINER_PLACE_RANGE := 80.0
const RECOIL_KICK := 5.0
const RECOIL_MAX := 14.0
const RECOIL_RECOVER := 14.0

const BUILD_RANGE := 300.0
const WALL_GRID := 32.0
# Placement collides against player (1), deposits (16) and buildings (32).
const PLACE_QUERY_MASK := 1 | 16 | 32
const BUILDING_SCENES := {
	"wall": preload("res://scenes/wall.tscn"),
	"mg_tower": preload("res://scenes/mg_tower.tscn"),
	"grenade_tower": preload("res://scenes/grenade_tower.tscn"),
	"repair_tower": preload("res://scenes/repair_tower.tscn"),
}
const BUILDING_FOOTPRINT := {"wall": 30.0, "mg_tower": 38.0, "grenade_tower": 38.0, "repair_tower": 38.0}
const GHOST_SIZE := {"wall": 32.0, "mg_tower": 40.0, "grenade_tower": 40.0, "repair_tower": 40.0}
# Must match the range each tower script actually uses.
const TOWER_RANGE := {"mg_tower": 350.0, "grenade_tower": 450.0, "repair_tower": 250.0}
const GHOST_VALID := Color(0.35, 1.0, 0.45, 0.45)
const GHOST_INVALID := Color(1.0, 0.3, 0.3, 0.45)

var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
var miner_scene: PackedScene = preload("res://scenes/miner.tscn")
var health: int
var _max_health: int
var _fire_cooldown: float = 0.0
var _regen_accum: float = 0.0
var _dead: bool = false
var _recoil: Vector2 = Vector2.ZERO
var _ghost
var _ghost_poly
var _ghost_range_poly
var _ghost_range_line
var _ghost_item: String = ""
var _place_shape
var _place_params

@onready var _health_bar: ProgressBar = $HealthBar
@onready var _camera: Camera2D = $Camera2D

func _ready() -> void:
	GameState.upgrades_changed.connect(_on_upgrades_changed)
	_max_health = GameState.player_max_health()
	health = _max_health
	_update_health_bar()
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

func _physics_process(delta: float) -> void:
	_health_bar.global_position = global_position + Vector2(-22, -40)

	# Camera recoil eases back to zero; offset doesn't fight position smoothing.
	_recoil *= exp(-RECOIL_RECOVER * delta)
	if _recoil.length_squared() < 0.01:
		_recoil = Vector2.ZERO
	_camera.offset = _recoil

	if _dead:
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_dir * GameState.player_speed(base_speed)
	move_and_slide()
	look_at(get_global_mouse_position())

	var regen := GameState.player_regen()
	if regen > 0.0 and health < _max_health:
		_regen_accum += regen * delta
		if _regen_accum >= 1.0:
			var heal := int(_regen_accum)
			_regen_accum -= heal
			health = mini(health + heal, _max_health)
			_update_health_bar()

	_fire_cooldown -= delta
	var selected := GameState.selected_item_id()
	if selected == "blaster" and Input.is_action_pressed("shoot") and _fire_cooldown <= 0.0:
		_shoot()
		_fire_cooldown = GameState.player_fire_cooldown(base_fire_rate)
	elif selected == "miner" and Input.is_action_just_pressed("shoot"):
		_try_place_miner()
	elif BUILDING_SCENES.has(selected) and Input.is_action_just_pressed("shoot"):
		_try_place_building(selected)
	_update_ghost(selected)

func _try_place_miner() -> void:
	var mouse := get_global_mouse_position()
	var target = null
	var best_dist := MINER_PLACE_RANGE
	for deposit in get_tree().get_nodes_in_group("deposits"):
		var dist: float = deposit.global_position.distance_to(mouse)
		if dist <= best_dist:
			best_dist = dist
			target = deposit
	if target == null or target.crystal <= 0 or target.has_miner:
		return
	if not GameState.spend(MINER_COST):
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
	if global_position.distance_to(pos) > BUILD_RANGE:
		return false
	var footprint: float = BUILDING_FOOTPRINT[id]
	_place_shape.size = Vector2(footprint, footprint)
	_place_params.transform = Transform2D(0.0, pos)
	var hits: Array = get_world_2d().direct_space_state.intersect_shape(_place_params, 1)
	return hits.is_empty()

func _try_place_building(id: String) -> void:
	var pos := _build_position(id)
	if not _placement_valid(id, pos):
		return
	if not GameState.spend(GameState.BUILDINGS[id]["cost"]):
		return
	var building = BUILDING_SCENES[id].instantiate()
	building.global_position = pos
	get_tree().current_scene.add_child(building)
	Sfx.play("place", pos)

func _update_ghost(selected: String) -> void:
	if not BUILDING_SCENES.has(selected):
		_ghost.visible = false
		return
	if selected != _ghost_item:
		_ghost_item = selected
		_update_range_ring(selected)
	var pos := _build_position(selected)
	var half: float = GHOST_SIZE[selected] / 2.0
	_ghost_poly.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)
	])
	_ghost_poly.color = GHOST_VALID if _placement_valid(selected, pos) else GHOST_INVALID
	_ghost.global_position = pos
	_ghost.visible = true

## RTS-style range preview while placing a tower.
func _update_range_ring(id: String) -> void:
	if not TOWER_RANGE.has(id):
		_ghost_range_poly.polygon = PackedVector2Array()
		_ghost_range_line.points = PackedVector2Array()
		return
	var radius: float = TOWER_RANGE[id]
	var points := PackedVector2Array()
	for i in 48:
		points.append(Vector2.from_angle(TAU * i / 48.0) * radius)
	_ghost_range_poly.polygon = points
	_ghost_range_line.points = points

func _shoot() -> void:
	var bullet = bullet_scene.instantiate()
	bullet.global_position = $Muzzle.global_position
	bullet.rotation = rotation
	var dmg := GameState.player_damage()
	if randf() < GameState.player_crit_chance():
		dmg = int(ceil(dmg * GameState.player_crit_mult()))
		bullet.crit = true
	bullet.damage = dmg
	get_tree().current_scene.add_child(bullet)
	Effects.muzzle_flash(self, $Muzzle.global_position, rotation)
	Sfx.play("shoot", $Muzzle.global_position, -6.0)
	_recoil = (_recoil - transform.x * RECOIL_KICK).limit_length(RECOIL_MAX)

func take_damage(amount: int) -> void:
	if _dead:
		return
	Sfx.play("player_hurt", global_position, -3.0)
	health = maxi(health - amount, 0)
	_update_health_bar()
	health_changed.emit(health, _max_health)
	if health == 0:
		_dead = true
		died.emit()

func heal(amount: int) -> void:
	if _dead or health >= _max_health:
		return
	health = mini(health + amount, _max_health)
	_update_health_bar()
	health_changed.emit(health, _max_health)

func max_health() -> int:
	return _max_health

func _update_health_bar() -> void:
	_health_bar.max_value = _max_health
	_health_bar.value = health

func _on_upgrades_changed() -> void:
	var new_max := GameState.player_max_health()
	if new_max != _max_health:
		health += maxi(new_max - _max_health, 0)
		_max_health = new_max
		health = mini(health, _max_health)
		_update_health_bar()
