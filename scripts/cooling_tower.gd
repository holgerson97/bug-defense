extends "res://scripts/building.gd"
## Cooling tower: passive part of the power-plant complex. Steams while its
## intake station is burning — set_running pings decay on a timer so a dead
## or stalled intake lets the steam die out on its own.

const RUN_WINDOW := 6.0

var _run_timer: float = 0.0

@onready var _steam: CPUParticles2D = $Steam

func _ready() -> void:
	super._ready()
	add_to_group("cooling_towers")

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_run_timer = maxf(_run_timer - delta, 0.0)
	_steam.emitting = _run_timer > 0.0

## The intake station pings this every burn cycle while the complex runs.
func set_running(running: bool) -> void:
	_run_timer = RUN_WINDOW if running else 0.0
