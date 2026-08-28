extends "res://scripts/building.gd"
## Solar panel: cheap, fragile generator trickling energy into the shared pool.

## 3/s: two panels sustain any single turret, even at high attack-speed
## research (MG peaks ~3.6/s upgraded).
const PRODUCE_INTERVAL := 2.0
const PRODUCE_AMOUNT := 6

var _produce_accum: float = 0.0

func _ready() -> void:
	super._ready()
	PowerGrid.register_source(self)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_produce_accum += delta
	if _produce_accum >= PRODUCE_INTERVAL:
		_produce_accum -= PRODUCE_INTERVAL
		## Host-only: replicated copies must not double-produce (Phase 4).
		if Net.is_host():
			GameState.add_resource("energy", PRODUCE_AMOUNT)
