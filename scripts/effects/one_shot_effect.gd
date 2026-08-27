extends Node2D
## Generic self-freeing effect: starts any CPUParticles2D children,
## fades an optional "Flash" child, frees itself after `life` seconds.

@export var life: float = 0.5
@export var flash_time: float = 0.08

var _time: float = 0.0
var _flash

func _ready() -> void:
	_flash = get_node_or_null("Flash")
	for child in get_children():
		if child is CPUParticles2D:
			child.emitting = true

func _process(delta: float) -> void:
	_time += delta
	if _flash != null:
		var fade: float = 1.0 - _time / flash_time
		if fade <= 0.0:
			_flash.visible = false
		else:
			_flash.modulate.a = fade
	if _time >= life:
		queue_free()
