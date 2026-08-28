extends "res://scripts/building.gd"
## Tesla tower: zaps the nearest enemy, then chains lightning to nearby
## foes at half damage per hop. Bolts are self-freeing jagged Line2D flashes.

const FIRE_INTERVAL := 1.1
const ENERGY_PER_ZAP := 2
const CHAIN_RANGE := 130.0
const MAX_CHAINS := 3
const ZAP_DAMAGE := 2

var base_range: float = GameState.BUILDINGS["tesla_tower"]["range"]
var fire_range: float = base_range
var _fire_accum: float = 0.0

func _ready() -> void:
	super._ready()
	energy_consumer = true

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	## Phase 5: combat is host-only; client copies idle (fire events = Phase 6).
	if Net.is_online() and not Net.is_host():
		return
	## Extended Barrels research scales range live.
	fire_range = base_range * GameState.tower_range_mult()
	_fire_accum += delta
	if _fire_accum >= GameState.tower_interval(FIRE_INTERVAL):
		_fire_accum = 0.0
		_zap()

func _zap() -> void:
	var victims: Array = []
	# The 360° coil arcs to any lit enemy in sight; chains hop freely.
	var first = Util.nearest_visible_in_group(self, "enemies", global_position, fire_range, victims, true)
	if first == null:
		return
	if not grid_powered() or not GameState.try_spend_energy(ENERGY_PER_ZAP):
		set_powered(false)
		return
	set_powered(true)
	victims.append(first)
	var link = first
	for i in MAX_CHAINS:
		var next = Util.nearest_in_group(self, "enemies", link.global_position, CHAIN_RANGE, victims)
		if next == null:
			break
		victims.append(next)
		link = next
	# Capture positions before dealing damage; a kill frees the victim node.
	var points: Array = [global_position]
	var damage := GameState.tower_damage_roll(ZAP_DAMAGE)
	for victim in victims:
		points.append(victim.global_position)
		if victim.has_method("take_damage"):
			victim.take_damage(damage)
		damage = maxi(int(ceil(damage / 2.0)), 1)
	## Bolt drawing lives in Effects (shared with the Phase 6 client replay).
	var pts := PackedVector2Array(points)
	Effects.tesla_bolts(self, pts)
	FxEvents.tesla_bolt(self, pts)
	Sfx.play("zap", global_position, -8.0)
