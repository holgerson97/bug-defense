extends Area2D


const TRAIL_LENGTH := 8

@export var speed: float = 700.0
@export var damage: int = 1
@export var lifetime: float = 1.5

var crit: bool = false
## Flame globs (Heavy's flamethrower): short-lived, fade out, and pierce
## through enemies (each victim burned once); walls and rocks still stop them.
var flame: bool = false
var pierce: bool = false

var _max_life: float = 1.5
var _burned: Dictionary = {}

@onready var _trail: Line2D = $Trail

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_trail.add_point(global_position)
	_max_life = lifetime
	if flame:
		$Body.color = Color(1.0, 0.55, 0.15, 0.95) if not crit else Color(1.0, 0.8, 0.3, 1.0)
		$Body.scale = Vector2(2.4, 2.4)
		_trail.width = 7.0
		_trail.default_color = Color(1.0, 0.45, 0.1, 0.5)
	elif crit:
		# Crits read as bigger, hotter shots.
		$Body.color = Color(1, 0.62, 0.2, 1)
		$Body.scale = Vector2(1.7, 1.7)
		_trail.width = 5.0

func _physics_process(delta: float) -> void:
	position += transform.x * speed * delta
	_trail.add_point(global_position)
	if _trail.get_point_count() > TRAIL_LENGTH:
		_trail.remove_point(0)
	lifetime -= delta
	if flame:
		modulate.a = clampf(lifetime / _max_life, 0.2, 1.0)
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body) -> void:
	if body.has_method("take_damage"):
		if pierce:
			if _burned.has(body):
				return
			_burned[body] = true
			body.take_damage(damage)
			Sfx.play("hit", global_position, -14.0)
			return
		body.take_damage(damage)
	Effects.impact(self, global_position, rotation + PI)
	Sfx.play("hit", global_position, -12.0)
	queue_free()
