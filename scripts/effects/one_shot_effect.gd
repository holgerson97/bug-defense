extends Node2D
## Generic self-freeing effect: starts any CPUParticles2D children,
## fades an optional "Flash" child, frees itself after `life` seconds.

@export var life: float = 0.5
@export var flash_time: float = 0.08
@export var light_time: float = 0.25

var _time: float = 0.0
var _flash
var _light
var _light_energy: float = 0.0

func _ready() -> void:
	_flash = get_node_or_null("Flash")
	_light = get_node_or_null("Light")
	if _light != null:
		_light_energy = _light.energy
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
	if _light != null:
		var light_fade: float = 1.0 - _time / light_time
		if light_fade <= 0.0:
			_light.visible = false
		else:
			_light.energy = _light_energy * light_fade
	if _time >= life:
		queue_free()
