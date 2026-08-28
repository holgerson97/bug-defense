extends "res://scripts/building.gd"
## Intake station: burner core of the power-plant complex. Each cycle it needs,
## within COMPLEX_RANGE, at least one Cooling Tower, one Battery and one
## grid-connected Power Pole (the output); then it burns crystal into a big
## energy pulse. Extra cooling towers raise the yield (capped). Incomplete
## complex: dim + bolt, no burn, no smoke, coolers idle. Not a grid source
## itself: the output pole must reach a real source (solar/battery/CC).

const SPRITE_SCALE := 0.5

var burn_interval: float = Balance.num("buildings/intake_station/burn_interval", 4.0)
var crystal_per_burn: int = Balance.inum("buildings/intake_station/crystal_per_burn", 5)
var energy_base: int = Balance.inum("buildings/intake_station/energy_base", 40)
var energy_per_extra_cooler: int = Balance.inum("buildings/intake_station/energy_per_extra_cooler", 20)
var max_coolers: int = Balance.inum("buildings/intake_station/max_coolers", 3)
## Complex radius, mirrored by GameState.BUILDINGS["intake_station"]["range"].
var complex_range: float = Balance.num("buildings/intake_station/range", 110.0)

var _burn_accum: float = 0.0
var _burning := false
var _glow: PointLight2D
var _strike_tween: Tween

@onready var _sprite: Sprite2D = $Sprite
@onready var _smoke: CPUParticles2D = $Smoke

func _ready() -> void:
	super._ready()
	_build_glow()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_burn_accum += delta
	if _burn_accum >= burn_interval:
		_burn_accum -= burn_interval
		_cycle()

## One burn cycle: verify the complex, then trade crystal for energy.
## Idle (crystal dry or energy capped) keeps the powered tint but no FX.
func _cycle() -> void:
	var coolers := _in_complex("cooling_towers")
	var complete := not coolers.is_empty() and not _in_complex("batteries").is_empty() and _has_output_pole()
	set_powered(complete)
	_burning = false
	if complete and GameState.resources.get("energy", 0) < GameState.energy_cap():
		## Host owns the crystal->energy trade; clients only predict the burn
		## FX from their mirror so the furnace look matches (cosmetic drift ok).
		if Net.is_host():
			if GameState.spend({"crystal": crystal_per_burn}):
				GameState.add_resource("energy", energy_base + (mini(coolers.size(), max_coolers) - 1) * energy_per_extra_cooler)
				_burning = true
		elif GameState.can_afford({"crystal": crystal_per_burn}):
			_burning = true
	if _burning:
		_strike()
	_smoke.emitting = _burning
	_glow.visible = _burning
	for cooler in coolers:
		cooler.set_running(_burning)

func _in_complex(group: String) -> Array:
	var found: Array = []
	for node in get_tree().get_nodes_in_group(group):
		if node.global_position.distance_to(global_position) <= complex_range:
			found.append(node)
	return found

## The output pole must also be grid-connected so the energy has a grid to feed.
func _has_output_pole() -> bool:
	for pole in _in_complex("power_poles"):
		if PowerGrid.is_pole_connected(pole):
			return true
	return false

## Furnace scale punch on each successful burn, miner-style.
func _strike() -> void:
	if _strike_tween != null and _strike_tween.is_valid():
		_strike_tween.kill()
	_sprite.scale = Vector2.ONE * SPRITE_SCALE
	_strike_tween = create_tween()
	_strike_tween.tween_property(_sprite, "scale", Vector2.ONE * SPRITE_SCALE * 1.08, 0.08)
	_strike_tween.tween_property(_sprite, "scale", Vector2.ONE * SPRITE_SCALE, 0.25)

## Warm furnace glow pulsing on a looped tween while burning; a PointLight2D
## so it reads against the night CanvasModulate.
func _build_glow() -> void:
	_glow = PointLight2D.new()
	_glow.texture = Effects.radial_light_texture(Color(1.0, 0.62, 0.25, 1.0), Color(1.0, 0.62, 0.25, 0.0), 128)
	_glow.color = Color(1.0, 0.65, 0.3)
	_glow.texture_scale = 0.8
	_glow.visible = false
	add_child(_glow)
	var tween := _glow.create_tween().set_loops()
	tween.tween_property(_glow, "energy", 1.4, 0.6)
	tween.tween_property(_glow, "energy", 0.7, 0.6)
