extends "res://scripts/building.gd"
## Tesla tower: zaps the nearest enemy, then chains lightning to nearby
## foes at half damage per hop. Bolts are self-freeing jagged Line2D flashes.

var fire_interval: float = Balance.num("towers/tesla_tower/interval", 1.1)
var energy_per_zap: int = Balance.inum("towers/tesla_tower/energy_per_zap", 2)
var chain_range: float = Balance.num("towers/tesla_tower/chain_range", 130.0)
var max_chains: int = Balance.inum("towers/tesla_tower/max_chains", 3)
var zap_damage: int = Balance.inum("towers/tesla_tower/damage", 2)

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
	## (No range upgrade for the tesla coil; base range stays.)
	fire_range = base_range
	_fire_accum += delta
	if _fire_accum >= fire_interval:
		_fire_accum = 0.0
		_zap()

func _zap() -> void:
	var victims: Array = []
	# The 360° coil arcs to any lit GROUND enemy in sight; chains hop freely
	# between ground targets (air is the AA cannon's job).
	var first = Util.nearest_visible_in_group(self, "enemies", global_position, fire_range, victims, true, 0.0, PI, "air_enemies")
	if first == null:
		return
	if not grid_powered() or not GameState.try_spend_energy(energy_per_zap):
		set_powered(false)
		return
	set_powered(true)
	victims.append(first)
	var link = first
	## Chain Jump upgrade: each level adds one more hop (same falloff/range).
	for i in max_chains + int(GameState.building_stat("tesla_tower", "chain")):
		var next = Util.nearest_in_group(self, "enemies", link.global_position, chain_range, victims, false, 0.0, PI, "air_enemies")
		if next == null:
			break
		victims.append(next)
		link = next
	# Capture positions before dealing damage; a kill frees the victim node.
	var points: Array = [global_position]
	var damage := GameState.tower_damage_roll("tesla_tower", zap_damage)
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
