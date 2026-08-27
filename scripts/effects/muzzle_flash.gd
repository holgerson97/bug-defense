extends Node2D
## Brief muzzle flash: PointLight2D energy pulse plus a fading flash polygon.

const DURATION := 0.08

var _time: float = 0.0

@onready var _light: PointLight2D = $Light
@onready var _flash: Polygon2D = $Flash

func _process(delta: float) -> void:
	_time += delta
	var fade := 1.0 - _time / DURATION
	if fade <= 0.0:
		queue_free()
		return
	_light.energy = 1.8 * fade
	_flash.modulate.a = fade
	_flash.scale = Vector2.ONE * (0.7 + 0.5 * fade)
