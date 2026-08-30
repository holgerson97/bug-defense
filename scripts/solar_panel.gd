extends "res://scripts/building.gd"
## Solar panel: cheap, fragile generator trickling energy into the shared pool.

## 3/s: two panels sustain any single turret, even at high attack-speed
## research (MG peaks ~3.6/s upgraded).
var produce_interval: float = Balance.num("buildings/solar_panel/produce_interval", 2.0)
var produce_amount: int = Balance.inum("buildings/solar_panel/produce_amount", 6)

var _produce_accum: float = 0.0

func _ready() -> void:
	super._ready()
	PowerGrid.register_source(self)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_produce_accum += delta
	if _produce_accum >= produce_interval:
		_produce_accum -= produce_interval
		## Host-only: replicated copies must not double-produce (Phase 4).
		## The Output building upgrade adds flat energy per cycle.
		if Net.is_host():
			GameState.add_resource("energy", produce_amount + int(GameState.building_stat("solar_panel", "output")))
