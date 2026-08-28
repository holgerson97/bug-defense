extends "res://scripts/building.gd"
## Repair tower: every second heals the most-damaged building in range,
## or the player if no building needs it. Shows a brief green beam.

const BEAM_TIME := 0.4

var heal_interval: float = Balance.num("towers/repair_tower/interval", 1.0)
var heal_amount: int = Balance.inum("towers/repair_tower/heal_amount", 3)
var energy_per_pulse: int = Balance.inum("towers/repair_tower/energy_per_pulse", 1)

var base_range: float = GameState.BUILDINGS["repair_tower"]["range"]
var heal_range: float = base_range
var _heal_accum: float = 0.0
var _beam_timer: float = 0.0

@onready var _beam: Line2D = $Beam

func _ready() -> void:
	super._ready()
	energy_consumer = true

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	## Beam fade runs on every peer: Phase 6 REPAIR_BEAM events replay via
	## _show_beam on client copies, which are otherwise idle below the gate.
	if _beam_timer > 0.0:
		_beam_timer -= delta
		if _beam_timer <= 0.0:
			_beam.visible = false
	## Phase 5: healing is host-only; client copies idle (heal() no-ops there
	## anyway, this just also silences beam FX + energy mirror reads).
	if Net.is_online() and not Net.is_host():
		return
	## Extended Barrels research scales range live.
	heal_range = base_range * GameState.tower_range_mult()
	_heal_accum += delta
	if _heal_accum >= heal_interval:
		_heal_accum = 0.0
		var target = _pick_target()
		if target != null:
			if grid_powered() and GameState.try_spend_energy(energy_per_pulse):
				set_powered(true)
				target.heal(heal_amount)
				_show_beam(target.global_position)
				FxEvents.repair_beam(self, target.global_position)
			else:
				set_powered(false)

func _pick_target():
	# Most-damaged building in range first (missing HP), then the nearest player.
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
	var player = Util.nearest_in_group(self, "player", global_position, heal_range)
	if player != null and player.health < player.max_health():
		return player
	return null

func _show_beam(target_pos: Vector2) -> void:
	_beam.points = PackedVector2Array([Vector2.ZERO, to_local(target_pos)])
	_beam.visible = true
	_beam_timer = BEAM_TIME
