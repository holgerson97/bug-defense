extends "res://scripts/building.gd"
## Searchlight: the head ping-pongs across a 140° arc centered on the
## placement facing, casting a beam cone that restores normal visibility —
## a neutral-white cone light that cancels the night CanvasModulate instead
## of glowing. covers() gives matching cone vision. Reach/angle mirror
## GameState.BUILDINGS["searchlight"] "range" / "cone".

const SWEEP_SPEED := 0.5
const SWEEP_HALF_ARC := deg_to_rad(70.0)
const ENERGY_INTERVAL := 2.0
const ENERGY_PER_INTERVAL := 1
const BEAM_REACH := 500.0
const BEAM_HALF_ANGLE := deg_to_rad(18.0)
const CONE_TEX_SIZE := 256

var _energy_accum: float = 0.0
var _sweep_dir := 1.0
var _cone: PointLight2D

@onready var _head: Node2D = $Head

func _ready() -> void:
	super._ready()
	energy_consumer = true
	_head.rotation = facing
	_build_cone_light()
	add_to_group("light_sources")

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	## Phase 5: energy sim is host-only; clients keep sweeping (pure visual —
	## covers()/vision only matter on the host) but never touch the pool.
	## Known cosmetic gap (accepted): the client sweep phase drifts from the
	## host's on pause/late-join — covers() never runs on clients, so nothing
	## gameplay-visible depends on it. See documentation/reference/
	## multiplayer_net_seam.md.
	if Net.is_online() and not Net.is_host():
		_sweep(delta)
		return
	# Starved: beam dark, sweep paused; retry the spend every frame.
	if not _powered:
		if grid_powered() and GameState.try_spend_energy(ENERGY_PER_INTERVAL):
			set_powered(true)
			_energy_accum = 0.0
		else:
			return
	_energy_accum += delta
	if _energy_accum >= ENERGY_INTERVAL:
		_energy_accum -= ENERGY_INTERVAL
		if not grid_powered() or not GameState.try_spend_energy(ENERGY_PER_INTERVAL):
			set_powered(false)
			return
	_sweep(delta)

# Ping-pong the sweep: flip direction at the arc bounds.
func _sweep(delta: float) -> void:
	_head.rotation += SWEEP_SPEED * _sweep_dir * delta
	var off := _head.rotation - facing
	if absf(off) >= SWEEP_HALF_ARC:
		_head.rotation = facing + clampf(off, -SWEEP_HALF_ARC, SWEEP_HALF_ARC)
		_sweep_dir = -_sweep_dir

func set_powered(p: bool) -> void:
	super.set_powered(p)
	# Unpowered: beam goes dark; covers() gates on _powered.
	if _cone:
		_cone.visible = p

## Vision check used by Util.is_lit: inside the beam cone while powered.
func covers(pos: Vector2) -> bool:
	if not _powered:
		return false
	var to := pos - global_position
	if to.length() > BEAM_REACH:
		return false
	return absf(wrapf(to.angle() - _head.global_rotation, -PI, PI)) <= BEAM_HALF_ANGLE

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
			var a := smoothstep(BEAM_HALF_ANGLE, BEAM_HALF_ANGLE * 0.85, absf(atan2(v.y, v.x)))
			a *= smoothstep(1.0, 0.85, r)
			if a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, a))
	_cone = PointLight2D.new()
	_cone.texture = ImageTexture.create_from_image(img)
	_cone.texture_scale = BEAM_REACH / float(CONE_TEX_SIZE)
	_cone.position = Vector2(BEAM_REACH / 2.0, 0.0)
	_cone.color = Color(1, 1, 1)
	_cone.energy = 1.0
	_head.add_child(_cone)
