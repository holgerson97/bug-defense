extends Node2D
## Timed-fuse flak shell: flies fast to a preset burst point, then detonates
## in a smoke puff, damaging all air enemies near the burst.

const FLAK_BURST_SCENE = preload("res://scenes/effects/flak_burst.tscn")

const SPEED := 600.0
const BURST_RADIUS := 70.0
const BURST_DAMAGE := 4

var burst_point: Vector2

func _ready() -> void:
	rotation = (burst_point - global_position).angle()

func _physics_process(delta: float) -> void:
	var to_burst := burst_point - global_position
	var step := SPEED * delta
	if to_burst.length() <= step:
		global_position = burst_point
		_detonate()
		return
	global_position += to_burst / to_burst.length() * step

func _detonate() -> void:
	var damage := BURST_DAMAGE + GameState.tower_damage_bonus()
	for enemy in get_tree().get_nodes_in_group("air_enemies"):
		if enemy.global_position.distance_to(global_position) <= BURST_RADIUS and enemy.has_method("take_damage"):
			enemy.take_damage(damage)
	var scene = get_tree().current_scene
	if scene != null:
		var burst = FLAK_BURST_SCENE.instantiate()
		burst.position = global_position
		scene.add_child(burst)
	Sfx.play("flak", global_position, -6.0)
	queue_free()
