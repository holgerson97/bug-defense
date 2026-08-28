extends Node2D
## Timed-fuse flak shell: flies fast to a preset burst point, then detonates
## in a smoke puff, damaging all air enemies near the burst.

const FLAK_BURST_SCENE = preload("res://scenes/effects/flak_burst.tscn")

var speed: float = Balance.num("towers/aa_tower/shell_speed", 600.0)
var burst_radius: float = Balance.num("towers/aa_tower/burst_radius", 130.0)
var burst_damage: int = Balance.inum("towers/aa_tower/burst_damage", 4)

var burst_point: Vector2
## Phase 6 client replay: cosmetic shells fly the host's route but free
## silently at the fuse point — the FLAK_BURST event carries burst FX + sfx.
var cosmetic := false

func _ready() -> void:
	rotation = (burst_point - global_position).angle()

func _physics_process(delta: float) -> void:
	var to_burst := burst_point - global_position
	var step := speed * delta
	if to_burst.length() <= step:
		global_position = burst_point
		_detonate()
		return
	global_position += to_burst / to_burst.length() * step

func _detonate() -> void:
	if cosmetic:
		queue_free()
		return
	var damage := GameState.tower_damage_roll(burst_damage)
	for enemy in get_tree().get_nodes_in_group("air_enemies"):
		if enemy.global_position.distance_to(global_position) <= burst_radius and enemy.has_method("take_damage"):
			enemy.take_damage(damage)
	var scene = get_tree().current_scene
	if scene != null:
		var burst = FLAK_BURST_SCENE.instantiate()
		burst.position = global_position
		scene.add_child(burst)
	Sfx.play("flak", global_position, -2.0)
	FxEvents.flak_burst(self, global_position)
	queue_free()
