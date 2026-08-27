extends Area2D

const Effects = preload("res://scripts/effects.gd")

const TRAIL_LENGTH := 8

@export var speed: float = 700.0
@export var damage: int = 1
@export var lifetime: float = 1.5

var crit: bool = false

@onready var _trail: Line2D = $Trail

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_trail.add_point(global_position)
	if crit:
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
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body) -> void:
	Effects.impact(self, global_position, rotation + PI)
	Sfx.play("hit", global_position, -12.0)
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
