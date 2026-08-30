extends "res://scripts/building.gd"
## Repair tower: every second heals the most-damaged buildings in range —
## the Targets upgrade adds simultaneous heal targets — or the player when no
## building needs it. Each active heal shows a layered energy beam: a soft
## glow line under a bright mint core, a shimmer streak flowing toward the
## target and a pulsing spark + small light at the target end (reads at
## night). Rigs are pre-built and re-used; nothing allocates per frame beyond
## the Line2D point updates.

const BEAM_TIME := 0.45
const LIGHT_SOURCE := preload("res://scripts/light_source.gd")

var heal_interval: float = Balance.num("towers/repair_tower/interval", 1.0)
var heal_amount: int = Balance.inum("towers/repair_tower/heal_amount", 3)
var energy_per_pulse: int = Balance.inum("towers/repair_tower/energy_per_pulse", 1)

var base_range: float = GameState.BUILDINGS["repair_tower"]["range"]
var heal_range: float = base_range
var _heal_accum: float = 0.0
var _beam_clock: float = 0.0
## Beam rigs (dictionaries, see _make_beam_rig), one per simultaneous target.
var _beams: Array = []

func _ready() -> void:
	super._ready()
	energy_consumer = true

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	## Beam animation runs on every peer: Phase 6 REPAIR_BEAM events replay
	## via _show_beam on client copies, which are otherwise idle below the gate.
	_beam_clock += delta
	_animate_beams(delta)
	## Phase 5: healing is host-only; client copies idle (heal() no-ops there
	## anyway, this just also silences beam FX + energy mirror reads).
	if Net.is_online() and not Net.is_host():
		return
	## The Range building upgrade scales heal reach live.
	heal_range = base_range * GameState.tower_range_mult("repair_tower")
	_heal_accum += delta
	if _heal_accum >= heal_interval:
		_heal_accum = 0.0
		_pulse()

## One heal pulse: the N most-damaged targets (Targets upgrade), paying the
## pulse energy PER TARGET — a starved pool heals as many as it can afford.
func _pulse() -> void:
	var amount := heal_amount + int(GameState.building_stat("repair_tower", "heal"))
	for target in _pick_targets(1 + int(GameState.building_stat("repair_tower", "targets"))):
		if grid_powered() and GameState.try_spend_energy(energy_per_pulse):
			set_powered(true)
			target.heal(amount)
			_show_beam(target.global_position)
			FxEvents.repair_beam(self, target.global_position)
		else:
			set_powered(false)
			return

## The `count` most-damaged distinct buildings in range (missing HP,
## descending); the hurt player fills a trailing slot when buildings run
## short — same priority order as the old single-target pick.
func _pick_targets(count: int) -> Array:
	var hurt: Array = []
	for building in get_tree().get_nodes_in_group("buildings"):
		if building.global_position.distance_to(global_position) > heal_range:
			continue
		if building.max_health - building.health > 0:
			hurt.append(building)
	hurt.sort_custom(func(a, b): return a.max_health - a.health > b.max_health - b.health)
	var out: Array = hurt.slice(0, count)
	if out.size() < count:
		var player = Util.nearest_in_group(self, "player", global_position, heal_range)
		if player != null and player.health < player.max_health():
			out.append(player)
	return out

## -- beam rig visuals --

func _make_beam_rig() -> Dictionary:
	var root := Node2D.new()
	root.z_index = 20
	root.visible = false
	add_child(root)
	var glow := Line2D.new()
	glow.width = 9.0
	glow.default_color = Color(0.3, 1.0, 0.55, 0.16)
	glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	glow.end_cap_mode = Line2D.LINE_CAP_ROUND
	root.add_child(glow)
	var core := Line2D.new()
	core.width = 2.2
	core.default_color = Color(0.72, 1.0, 0.85, 0.95)
	core.begin_cap_mode = Line2D.LINE_CAP_ROUND
	core.end_cap_mode = Line2D.LINE_CAP_ROUND
	root.add_child(core)
	## Shimmer: a short bright segment traveling along the beam each cycle.
	var streak := Line2D.new()
	streak.width = 3.4
	streak.default_color = Color(0.9, 1.0, 0.95, 0.75)
	streak.begin_cap_mode = Line2D.LINE_CAP_ROUND
	streak.end_cap_mode = Line2D.LINE_CAP_ROUND
	root.add_child(streak)
	## Target-end glow burst: pulsing soft polygon circle.
	var spark := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 10:
		pts.append(Vector2.from_angle(TAU * i / 10.0) * 5.0)
	spark.polygon = pts
	spark.color = Color(0.75, 1.0, 0.85, 0.8)
	root.add_child(spark)
	## Small warm light at the target end so heals read at night (shared
	## LightSource texture, tinted mint; plain PointLight2D — no vision pool).
	var light := PointLight2D.new()
	light.texture = LIGHT_SOURCE._get_shared_texture()
	light.color = Color(0.55, 1.0, 0.75)
	light.energy = 0.9
	light.texture_scale = 0.35
	root.add_child(light)
	return {"root": root, "glow": glow, "core": core, "streak": streak,
		"spark": spark, "light": light, "timer": 0.0, "target": Vector2.ZERO,
		"phase": float(_beams.size()) * 1.7}

## Activate a beam toward `target_pos`: refresh the rig already on (nearly)
## that target, else re-use an idle rig, else grow the pool by one.
func _show_beam(target_pos: Vector2) -> void:
	var free = null
	for rig in _beams:
		if rig["timer"] > 0.0 and rig["target"].distance_to(target_pos) < 8.0:
			rig["timer"] = BEAM_TIME
			rig["target"] = target_pos
			return
		if free == null and rig["timer"] <= 0.0:
			free = rig
	if free == null:
		free = _make_beam_rig()
		_beams.append(free)
	free["timer"] = BEAM_TIME
	free["target"] = target_pos

func _animate_beams(delta: float) -> void:
	for rig in _beams:
		if rig["timer"] <= 0.0:
			continue
		rig["timer"] -= delta
		if rig["timer"] <= 0.0:
			rig["root"].visible = false
			continue
		rig["root"].visible = true
		var to: Vector2 = to_local(rig["target"])
		var t: float = _beam_clock
		var phase: float = rig["phase"]
		## Tail fade + gentle width pulsing.
		rig["root"].modulate = Color(1, 1, 1, clampf(rig["timer"] / BEAM_TIME * 2.0, 0.0, 1.0))
		rig["core"].width = 2.2 + 0.7 * sin(t * 9.0 + phase)
		rig["glow"].width = 9.0 + 2.0 * sin(t * 6.0 + phase)
		rig["core"].points = PackedVector2Array([Vector2.ZERO, to])
		rig["glow"].points = PackedVector2Array([Vector2.ZERO, to])
		var dir := to.normalized() if to.length() > 1.0 else Vector2.RIGHT
		var head: Vector2 = to * fmod(t * 1.6 + phase, 1.0)
		rig["streak"].points = PackedVector2Array([head - dir * minf(14.0, head.length()), head])
		rig["spark"].position = to
		rig["spark"].scale = Vector2.ONE * (1.0 + 0.35 * sin(t * 12.0 + phase))
		rig["light"].position = to
