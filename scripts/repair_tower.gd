extends "res://scripts/building.gd"
## Repair tower: every second heals the most-damaged building in range,
## or the player if no building needs it. Shows a brief green beam.

const HEAL_INTERVAL := 1.0
const HEAL_AMOUNT := 3
const ENERGY_PER_PULSE := 1
const BEAM_TIME := 0.4

var heal_range: float = GameState.BUILDINGS["repair_tower"]["range"]
var _heal_accum: float = 0.0
var _beam_timer: float = 0.0

@onready var _beam: Line2D = $Beam

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_heal_accum += delta
	if _heal_accum >= HEAL_INTERVAL:
		_heal_accum = 0.0
		var target = _pick_target()
		if target != null:
			if GameState.try_spend_energy(ENERGY_PER_PULSE):
				set_powered(true)
				target.heal(HEAL_AMOUNT)
				_show_beam(target.global_position)
			else:
				set_powered(false)
	if _beam_timer > 0.0:
		_beam_timer -= delta
		if _beam_timer <= 0.0:
			_beam.visible = false

func _pick_target():
	# Most-damaged building in range first (missing HP), then the player.
	var best = null
	var best_missing := 0
	for building in get_tree().get_nodes_in_group("buildings"):
		if building.global_position.distance_to(global_position) > heal_range:
			continue
		var missing: int = building.max_health - building.health
		if missing > best_missing:
			best_missing = missing
			best = building
	if best != null:
		return best
	var player = get_tree().get_first_node_in_group("player")
	if player != null and is_instance_valid(player):
		if player.global_position.distance_to(global_position) <= heal_range and player.health < player.max_health():
			return player
	return null

func _show_beam(target_pos: Vector2) -> void:
	_beam.points = PackedVector2Array([Vector2.ZERO, to_local(target_pos)])
	_beam.visible = true
	_beam_timer = BEAM_TIME
