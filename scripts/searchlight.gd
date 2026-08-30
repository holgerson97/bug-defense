extends "res://scripts/building.gd"
## Searchlight: the head ping-pongs across a 140° arc centered on the
## placement facing, casting a beam cone that restores normal visibility —
## a neutral-white cone light that cancels the night CanvasModulate instead
## of glowing. covers() gives matching cone vision. Reach/angle mirror
## GameState.BUILDINGS["searchlight"] "range" / "cone".

const CONE_TEX_SIZE := 256

var sweep_speed: float = Balance.num("buildings/searchlight/sweep_speed", 0.5)
var sweep_half_arc: float = deg_to_rad(Balance.num("buildings/searchlight/sweep", 140.0)) / 2.0
var energy_interval: float = Balance.num("buildings/searchlight/energy_interval", 2.0)
var energy_per_interval: int = Balance.inum("buildings/searchlight/energy_per_interval", 1)
var beam_reach: float = Balance.num("buildings/searchlight/range", 500.0)
var beam_half_angle: float = deg_to_rad(Balance.num("buildings/searchlight/cone", 36.0)) / 2.0

var _energy_accum: float = 0.0
var _sweep_dir := 1.0
var _cone: PointLight2D
var _darkness := 1.0
## Reach upgrade multiplier over beam_reach (cone light + covers()).
var _reach_mult := 1.0

@onready var _head: Node2D = $Head

func _ready() -> void:
	super._ready()
	energy_consumer = true
	_head.rotation = facing
	_build_cone_light()
	## The Reach building upgrade stretches the beam live.
	GameState.upgrades_changed.connect(_apply_reach)
	_apply_reach()
	add_to_group("light_sources")
	var dn = get_tree().get_first_node_in_group("day_night")
	set_darkness(dn.darkness_factor() if dn != null else 1.0)

## Day/night: the beam fades with the darkness and the light parks in
## daylight — no sweep, no energy drain (nothing to reveal by day).
func set_darkness(f: float) -> void:
	_darkness = f
	if _cone:
		_cone.energy = f
		_cone.visible = _powered and f > 0.02

## Rescale the cone light to the upgraded reach (texture stays; only the
## scale and the apex offset change).
func _apply_reach() -> void:
	_reach_mult = GameState.tower_range_mult("searchlight")
	if _cone:
		_cone.texture_scale = beam_reach * _reach_mult / float(CONE_TEX_SIZE)
		_cone.position = Vector2(beam_reach * _reach_mult / 2.0, 0.0)

func _is_daytime() -> bool:
	return _darkness < 0.5

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	## Phase 5: energy sim is host-only; clients keep sweeping (pure visual —
	## covers()/vision only matter on the host) but never touch the pool.
	## Known cosmetic gap (accepted): the client sweep phase drifts from the
	## host's on pause/late-join — covers() never runs on clients, so nothing
	## gameplay-visible depends on it. See documentation/reference/
	## multiplayer_net_seam.md.
	if _is_daytime():
		return
	if Net.is_online() and not Net.is_host():
		_sweep(delta)
		return
	# Starved: beam dark, sweep paused; retry the spend every frame.
	if not _powered:
		if grid_powered() and GameState.try_spend_energy(energy_per_interval):
			set_powered(true)
			_energy_accum = 0.0
		else:
			return
	_energy_accum += delta
	if _energy_accum >= energy_interval:
		_energy_accum -= energy_interval
		if not grid_powered() or not GameState.try_spend_energy(energy_per_interval):
			set_powered(false)
			return
	_sweep(delta)

# Ping-pong the sweep: flip direction at the arc bounds.
func _sweep(delta: float) -> void:
	_head.rotation += sweep_speed * _sweep_dir * delta
	var off := _head.rotation - facing
	if absf(off) >= sweep_half_arc:
		_head.rotation = facing + clampf(off, -sweep_half_arc, sweep_half_arc)
		_sweep_dir = -_sweep_dir

func set_powered(p: bool) -> void:
	super.set_powered(p)
	# Unpowered: beam goes dark; covers() gates on _powered.
	if _cone:
		_cone.visible = p and _darkness > 0.02

## Vision check used by Util.is_lit: inside the beam cone while powered.
func covers(pos: Vector2) -> bool:
	if not _powered:
		return false
	var to := pos - global_position
	if to.length() > beam_reach * _reach_mult:
		return false
	return absf(wrapf(to.angle() - _head.global_rotation, -PI, PI)) <= beam_half_angle

## The beam is a PointLight2D with a script-built cone alpha texture:
## apex at left-center of the Image, soft-edged wedge opening along +X
## (fades over the outer 15% of angle and radius). The light sits at
## BEAM_REACH/2 on the head so the apex lands on the tower and the cone
## sweeps with the head. Neutral white at energy 1.0 ≈ cancels the
## near-black CanvasModulate — the cone shows the world at normal
## brightness rather than as a visible glow.
func _build_cone_light() -> void:
	var img := Image.create(CONE_TEX_SIZE, CONE_TEX_SIZE, false, Image.FORMAT_RGBA8)
	var half := CONE_TEX_SIZE / 2.0
	for y in CONE_TEX_SIZE:
		for x in CONE_TEX_SIZE:
			var v := Vector2(x + 0.5, y + 0.5 - half)
			var r := v.length() / float(CONE_TEX_SIZE)
			if r > 1.0:
				continue
			var a := smoothstep(beam_half_angle, beam_half_angle * 0.85, absf(atan2(v.y, v.x)))
			a *= smoothstep(1.0, 0.85, r)
			if a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, a))
	_cone = PointLight2D.new()
	_cone.texture = ImageTexture.create_from_image(img)
	_cone.texture_scale = beam_reach / float(CONE_TEX_SIZE)
	_cone.position = Vector2(beam_reach / 2.0, 0.0)
	_cone.color = Color(1, 1, 1)
	_cone.energy = 1.0
	_head.add_child(_cone)
