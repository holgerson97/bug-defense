extends "res://scripts/enemy.gd"
## Kites the player at range and periodically summons runners beside it.

const RUNNER_SCENE = preload("res://scenes/enemies/runner.tscn")
const KITE_DISTANCE := 400.0
const APPROACH_DISTANCE := 500.0
const SUMMON_INTERVAL := 5.0
const MAX_SUMMONS := 6

var _summon_timer: float = 0.0
var _summons: Array = []

func _behave(delta) -> void:
	var to_player: Vector2 = _target.global_position - global_position
	var dist := to_player.length()
	var move := Vector2.ZERO
	if dist < KITE_DISTANCE:
		move = -to_player.normalized()
	elif dist > APPROACH_DISTANCE:
		move = to_player.normalized()
	velocity = move * speed
	rotation = to_player.angle()
	move_and_slide()

	_summon_timer += delta
	if _summon_timer >= SUMMON_INTERVAL:
		_summon_timer = 0.0
		_summon()

func _summon() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	_summons = _summons.filter(func(s): return is_instance_valid(s))
	var wm = get_tree().get_first_node_in_group("wave_manager")
	for i in randi_range(2, 3):
		if _summons.size() >= MAX_SUMMONS:
			return
		var runner = RUNNER_SCENE.instantiate()
		runner.global_position = global_position + Vector2.from_angle(randf() * TAU) * 40.0
		_summons.append(runner)
		if wm != null and wm.has_method("register_enemy"):
			wm.register_enemy(runner)
		scene.add_child(runner)
