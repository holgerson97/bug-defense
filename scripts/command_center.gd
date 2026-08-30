extends "res://scripts/building.gd"
## Command center: periodically trains gold-harvesting worker units, paying
## crystal + energy per unit and capping the number of living harvesters.

const SPAWN_OFFSET := 40.0

var train_interval: float = Balance.num("buildings/command_center/train_interval", 4.0)
var max_workers: int = Balance.inum("buildings/command_center/max_workers", 5)
## Hearts are research-only; workers train on crystal like all construction.
var train_cost: Dictionary = Balance.cost_dict("buildings/command_center/train_cost", {"crystal": 12})
var train_energy: int = Balance.inum("buildings/command_center/train_energy", 2)

var harvester_scene: PackedScene = preload("res://scenes/harvester.tscn")
var _train_accum: float = 0.0
var _harvesters: Array = []

@onready var _worker_label: Label = $WorkerLabel

func _ready() -> void:
	super._ready()
	energy_consumer = true
	PowerGrid.register_source(self)
	## The Crew building upgrade raises the cap live — refresh the label.
	GameState.upgrades_changed.connect(_update_worker_label)
	_update_worker_label()

## Worker cap: base plus the Crew building upgrade.
func _max_workers() -> int:
	return max_workers + int(GameState.building_stat("command_center", "crew"))

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_prune_harvesters()
	_train_accum += delta
	if _train_accum >= train_interval:
		_train_accum = 0.0
		if _harvesters.size() < _max_workers():
			_train_harvester()

## Drop freed/dead harvesters so their slots open up again.
func _prune_harvesters() -> void:
	var alive: Array = []
	for h in _harvesters:
		if is_instance_valid(h):
			alive.append(h)
	if alive.size() != _harvesters.size():
		_harvesters = alive
		_update_worker_label()

func _update_worker_label() -> void:
	_worker_label.text = "%d/%d" % [_harvesters.size(), _max_workers()]

func _train_harvester() -> void:
	if not GameState.can_afford(train_cost):
		return
	if not grid_powered() or not GameState.try_spend_energy(train_energy):
		set_powered(false)
		return
	set_powered(true)
	## Host owns the scrap + energy cost (client try_spend_energy above is a
	## mirror availability check); client CCs train VISUAL-only drones so both
	## screens show the same base — the host's drones bank the real gold.
	if Net.is_host():
		GameState.spend(train_cost)
	var harvester = harvester_scene.instantiate()
	harvester.command_center = self
	harvester.global_position = global_position + Vector2.from_angle(randf() * TAU) * SPAWN_OFFSET
	get_tree().current_scene.add_child(harvester)
	_harvesters.append(harvester)
	_update_worker_label()
