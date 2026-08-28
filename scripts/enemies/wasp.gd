extends "res://scripts/enemy.gd"
## Flying wasp: flies over walls and rocks, swooping at its target (a nearby
## building or the player) with a sinusoidal weave, then stinging in melee.

const WEAVE_FREQUENCY := 6.0
const WEAVE_AMPLITUDE := 90.0

var _weave_time: float = randf() * TAU

func _behave(delta) -> void:
	var to_target: Vector2 = _target.global_position - global_position
	if to_target.length() > _target_reach():
		_weave_time += delta
		var dir := to_target.normalized()
		velocity = dir * speed + dir.orthogonal() * sin(_weave_time * WEAVE_FREQUENCY) * WEAVE_AMPLITUDE
		rotation = velocity.angle()
		move_and_slide()
	else:
		rotation = to_target.angle()
		velocity = Vector2.ZERO
		_attack_cooldown -= delta
		if _attack_cooldown <= 0.0:
			_target.take_damage(damage)
			_attack_cooldown = attack_interval
