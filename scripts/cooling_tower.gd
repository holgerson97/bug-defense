extends "res://scripts/building.gd"
## Cooling tower: passive part of the power-plant complex. While its intake
## station burns it animates: billowing steam, a rotor spinning in the tower
## mouth, and a gentle breathing pulse. set_running pings decay on a timer so
## a dead or stalled intake lets it all wind down on its own.

const RUN_WINDOW := 6.0
const BASE_SCALE := 1.5
const FAN_SPEED := 3.2          ## rad/s at full spin
const FAN_EASE := 1.6           ## spin-up/down responsiveness
const BREATH_RATE := 2.2        ## breathing pulses per second (rad/s factor)
const BREATH_AMOUNT := 0.02     ## +-2% sprite scale while running

var _run_timer: float = 0.0
var _fan: Node2D
var _fan_speed: float = 0.0
var _breath_time: float = 0.0

@onready var _steam: CPUParticles2D = $Steam
@onready var _sprite: Sprite2D = $Sprite

func _ready() -> void:
	super._ready()
	add_to_group("cooling_towers")
	_build_fan()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_run_timer = maxf(_run_timer - delta, 0.0)
	var running := _run_timer > 0.0
	_steam.emitting = running
	## Rotor eases up to speed and coasts to a stop instead of snapping.
	_fan_speed = move_toward(_fan_speed, FAN_SPEED if running else 0.0, FAN_EASE * delta)
	_fan.rotation += _fan_speed * delta
	## Breathing: subtle scale pulse that settles back to rest when idle.
	if running:
		_breath_time += delta
		var pulse := 1.0 + sin(_breath_time * BREATH_RATE * TAU * 0.5) * BREATH_AMOUNT
		_sprite.scale = Vector2.ONE * BASE_SCALE * pulse
	elif _sprite.scale.x != BASE_SCALE:
		_sprite.scale = _sprite.scale.move_toward(Vector2.ONE * BASE_SCALE, delta * 0.2)

## The intake station pings this every burn cycle while the complex runs.
func set_running(running: bool) -> void:
	_run_timer = RUN_WINDOW if running else 0.0

## Code-built rotor visible in the tower's mouth under the steam: a hub and
## four semi-transparent blades, dark against the pale sprite.
func _build_fan() -> void:
	_fan = Node2D.new()
	_fan.z_index = 1
	for i in 4:
		var blade := Polygon2D.new()
		blade.polygon = PackedVector2Array([
			Vector2(3, -2.5), Vector2(17, -5.5), Vector2(19, 0), Vector2(17, 5.5), Vector2(3, 2.5)
		])
		blade.color = Color(0.25, 0.3, 0.36, 0.85)
		blade.rotation = TAU * i / 4.0
		_fan.add_child(blade)
	var hub := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 10:
		pts.append(Vector2.from_angle(TAU * i / 10.0) * 4.5)
	hub.polygon = pts
	hub.color = Color(0.42, 0.48, 0.55, 1.0)
	_fan.add_child(hub)
	add_child(_fan)
