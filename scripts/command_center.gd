extends "res://scripts/building.gd"
## Command center: periodically trains gold-harvesting worker units, paying
## scrap + energy per unit and capping the number of living harvesters.

const TRAIN_INTERVAL := 4.0
const MAX_HARVESTERS := 3
const TRAIN_COST := {"scrap": 30}
const TRAIN_ENERGY := 2
const SPAWN_OFFSET := 40.0

var harvester_scene: PackedScene = preload("res://scenes/harvester.tscn")
var _train_accum: float = 0.0
var _harvesters: Array = []

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_train_accum += delta
	if _train_accum >= TRAIN_INTERVAL:
		_train_accum = 0.0
		_prune_harvesters()
		if _harvesters.size() < MAX_HARVESTERS:
			_train_harvester()

func _prune_harvesters() -> void:
	var alive: Array = []
	for h in _harvesters:
		if is_instance_valid(h):
			alive.append(h)
	_harvesters = alive

func _train_harvester() -> void:
	if not GameState.can_afford(TRAIN_COST):
		return
	if not GameState.try_spend_energy(TRAIN_ENERGY):
		set_powered(false)
		return
	set_powered(true)
	GameState.spend(TRAIN_COST)
	var harvester = harvester_scene.instantiate()
	harvester.command_center = self
	harvester.global_position = global_position + Vector2.from_angle(randf() * TAU) * SPAWN_OFFSET
	get_tree().current_scene.add_child(harvester)
	_harvesters.append(harvester)
