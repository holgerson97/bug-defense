extends "res://scripts/building.gd"
## Searchlight: a head slowly sweeps a long bright beam through the night.
## Towers can engage anything the beam currently touches (see covers()).

const SWEEP_SPEED := 0.5
const BEAM_REACH := 500.0
const BEAM_HALF_ANGLE := deg_to_rad(15.0)
const ENERGY_INTERVAL := 2.0
const ENERGY_PER_INTERVAL := 1

var _energy_accum: float = 0.0

@onready var _head: Node2D = $Head

func _ready() -> void:
	super._ready()
	add_to_group("light_sources")
	_head.rotation = randf() * TAU

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# Starved: beam dark, sweep paused; retry the spend every frame.
	if not _powered:
		if GameState.try_spend_energy(ENERGY_PER_INTERVAL):
			set_powered(true)
			_energy_accum = 0.0
		else:
			return
	_energy_accum += delta
	if _energy_accum >= ENERGY_INTERVAL:
		_energy_accum -= ENERGY_INTERVAL
		if not GameState.try_spend_energy(ENERGY_PER_INTERVAL):
			set_powered(false)
			return
	_head.rotation += SWEEP_SPEED * delta

func set_powered(p: bool) -> void:
	super.set_powered(p)
	_head.get_node("BeamLight").visible = p
	_head.get_node("BeamPoly").visible = p

## Vision contract for Util.is_lit: inside beam reach and within the cone
## around the current heading, only while powered.
func covers(pos: Vector2) -> bool:
	if not _powered:
		return false
	var to_pos := pos - global_position
	if to_pos.length() > BEAM_REACH:
		return false
	return absf(Vector2.from_angle(_head.global_rotation).angle_to(to_pos)) <= BEAM_HALF_ANGLE
