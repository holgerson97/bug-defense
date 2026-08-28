extends "res://scripts/building.gd"
## Solar panel: cheap, fragile generator trickling energy into the shared pool.

const PRODUCE_INTERVAL := 2.0
const PRODUCE_AMOUNT := 4

var _produce_accum: float = 0.0

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_produce_accum += delta
	if _produce_accum >= PRODUCE_INTERVAL:
		_produce_accum -= PRODUCE_INTERVAL
		GameState.add_resource("energy", PRODUCE_AMOUNT)
