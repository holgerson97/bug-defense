extends Node2D
## Hive body animation: tentacles sway and stretch, the dome breathes, the
## birthing maw glows with an uneasy flicker. Pure visuals — the gameplay
## layer (HP, defenders, provocation) mounts on top of this scene.

const SWAY_AMP := 0.16          ## radians of tentacle sway
const SWAY_SPEED := 0.9
const STRETCH_AMP := 0.05       ## tentacle length breathing
const DOME_BREATH := 0.015      ## +-1.5% dome scale
const DOME_RATE := 0.55
const GLOW_BASE := 1.1

const TENT_A := preload("res://assets/sprites/hive/tentacle_a.svg")
const TENT_B := preload("res://assets/sprites/hive/tentacle_b.svg")

var _t: float = 0.0
var _tentacle_base: Array = []
var _glow: PointLight2D

@onready var _tentacles: Node2D = $Tentacles
@onready var _body: Sprite2D = $Body

func _ready() -> void:
	for tent in _tentacles.get_children():
		_tentacle_base.append({"node": tent, "rot": tent.rotation, "scale": tent.scale, "phase": randf() * TAU})
	_glow = PointLight2D.new()
	_glow.texture = Effects.radial_light_texture(Color(1.0, 0.55, 0.3, 1.0), Color(1.0, 0.55, 0.3, 0.0), 128)
	_glow.color = Color(1.0, 0.6, 0.35)
	_glow.texture_scale = 1.1
	_glow.energy = GLOW_BASE
	add_child(_glow)

func _process(delta: float) -> void:
	_t += delta
	for entry in _tentacle_base:
		var tent = entry["node"]
		var phase: float = entry["phase"]
		tent.rotation = entry["rot"] + sin(_t * SWAY_SPEED + phase) * SWAY_AMP
		## Length breathing on a different rhythm so it reads organic.
		var stretch: float = 1.0 + sin(_t * SWAY_SPEED * 0.7 + phase * 1.7) * STRETCH_AMP
		tent.scale = Vector2(entry["scale"].x * stretch, entry["scale"].y)
	var breath := 1.0 + sin(_t * DOME_RATE * TAU * 0.5) * DOME_BREATH
	_body.scale = Vector2.ONE * 0.5 * breath
	## Maw glow: slow pulse with nervous jitter layered on top.
	_glow.energy = GLOW_BASE + sin(_t * 1.3) * 0.25 + sin(_t * 7.1) * 0.08

## Growth (hive_site stage-ups): sprout a tentacle at `angle`, registered in
## _tentacle_base so the sway loop above animates it like the authored seven.
## Draws only from the caller's rng — deterministic across peers per stage.
func add_tentacle(angle: float, rng: RandomNumberGenerator) -> void:
	var use_a: bool = rng.randf() < 0.5
	var tent := Sprite2D.new()
	tent.texture = TENT_A if use_a else TENT_B
	tent.centered = false
	## Root at left-center of the texture, like the scene-authored tentacles.
	tent.offset = Vector2(0, -32) if use_a else Vector2(0, -28)
	tent.position = Vector2.from_angle(angle) * rng.randf_range(56.0, 64.0)
	tent.rotation = angle
	var s := rng.randf_range(0.42, 0.5)
	tent.scale = Vector2(s, s)
	_tentacles.add_child(tent)
	_tentacle_base.append({"node": tent, "rot": tent.rotation, "scale": tent.scale, "phase": rng.randf() * TAU})
