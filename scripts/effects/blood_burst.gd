extends Node2D
## One-shot blood particle burst. `amount` can be set before add_child
## (bigger burst on death). Frees itself after `life` seconds.

@export var life: float = 0.8

var amount: int = 12

@onready var _particles: CPUParticles2D = $Particles

func _ready() -> void:
	_particles.amount = amount
	_particles.emitting = true

func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
