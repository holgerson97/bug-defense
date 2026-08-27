extends Area2D

const Effects = preload("res://scripts/effects.gd")

const TRAIL_LENGTH := 8

@export var speed: float = 700.0
@export var damage: int = 1
@export var lifetime: float = 1.5

@onready var _trail: Line2D = $Trail

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_trail.add_point(global_position)

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
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
