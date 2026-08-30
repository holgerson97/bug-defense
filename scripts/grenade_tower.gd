extends "res://scripts/building.gd"
## Grenade tower: lobs grenades at random GROUND enemies in range every few
## seconds (air is the AA cannon's job). The Extra Bomb upgrade turns each
## shot into a staggered volley — one grenade at the primary target plus one
## per level at other enemies (scattered drops around the primary when
## targets run short). Every grenade pays the tower's full energy cost.

const VOLLEY_STAGGER := 0.1
const SCATTER_MIN := 60.0
const SCATTER_MAX := 90.0

var fire_interval: float = Balance.num("towers/grenade_tower/interval", 2.5)
var energy_per_lob: int = Balance.inum("towers/grenade_tower/energy_per_lob", 2)

var grenade_scene: PackedScene = preload("res://scenes/grenade.tscn")
var base_range: float = GameState.BUILDINGS["grenade_tower"]["range"]
var fire_range: float = base_range
var half_arc: float = deg_to_rad(GameState.BUILDINGS["grenade_tower"]["arc"]) / 2.0
var _fire_accum: float = 0.0
## Pending volley lob points, popped one per VOLLEY_STAGGER — host-side and
## delta-accumulated, so pause freezes a mid-flight barrage for free.
var _volley: Array = []
var _volley_accum: float = 0.0

func _ready() -> void:
	super._ready()
	energy_consumer = true
	$Sprite.rotation = facing

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	## Phase 5: combat is host-only; client copies idle (fire events = Phase 6).
	if Net.is_online() and not Net.is_host():
		return
	## The Range building upgrade scales targeting range live.
	fire_range = base_range * GameState.tower_range_mult("grenade_tower")
	if not _volley.is_empty():
		_volley_accum += delta
		if _volley_accum >= VOLLEY_STAGGER:
			_volley_accum = 0.0
			_lob(_volley.pop_front())
	_fire_accum += delta
	if _fire_accum >= GameState.tower_interval("grenade_tower", fire_interval):
		_fire_accum = 0.0
		_fire()

func _fire() -> void:
	var candidates: Array = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		## Only the AA flak cannon may engage air units.
		if enemy.is_in_group("air_enemies"):
			continue
		if enemy.global_position.distance_to(global_position) > fire_range:
			continue
		if not Util.in_arc(global_position, facing, half_arc, enemy.global_position):
			continue
		if not Util.is_lit(self, enemy.global_position):
			continue
		## Rocks and ore block sight — no lobbing at targets the tower can't see.
		if Util.has_los(self, global_position, enemy.global_position):
			candidates.append(enemy)
	if candidates.is_empty():
		return
	var target = candidates.pick_random()
	var points: Array = [target.global_position]
	## Extra Bomb: +1 grenade per level — different enemies when available,
	## scattered drops around the primary otherwise.
	var others: Array = candidates.duplicate()
	others.erase(target)
	for i in int(GameState.building_stat("grenade_tower", "bombs")):
		if not others.is_empty():
			var pick = others.pick_random()
			others.erase(pick)
			points.append(pick.global_position)
		else:
			points.append(target.global_position
				+ Vector2.from_angle(randf() * TAU) * randf_range(SCATTER_MIN, SCATTER_MAX))
	## First bomb flies immediately; the rest stagger out as a barrage.
	if _lob(points.pop_front()):
		_volley = points
		_volley_accum = 0.0

## Pay energy for ONE grenade and throw it; a failed spend darks the tower
## and cancels the rest of the volley.
func _lob(point: Vector2) -> bool:
	if not grid_powered() or not GameState.try_spend_energy(energy_per_lob):
		set_powered(false)
		_volley.clear()
		return false
	set_powered(true)
	var grenade = grenade_scene.instantiate()
	grenade.global_position = global_position
	grenade.target_point = point
	get_tree().current_scene.add_child(grenade)
	FxEvents.grenade_lob(self, global_position, point)
	return true
