extends "res://scripts/enemy.gd"
## Flying drone tank: an armored air brute. Lumbers over walls and buildings
## in a slow, near-straight line, soaking AA fire while wasp swarms slip past,
## then delivers heavy gnawing bites in melee range.

const DRIFT_FREQUENCY := 1.4
const DRIFT_AMPLITUDE := 16.0

var _drift_time: float = randf() * TAU

func _behave(delta) -> void:
	var to_target: Vector2 = _target.global_position - global_position
	if to_target.length() > _target_reach():
		## Gentle drift only — a fat slow target the flak can track.
		_drift_time += delta
		var dir := to_target.normalized()
		velocity = dir * speed + dir.orthogonal() * sin(_drift_time * DRIFT_FREQUENCY) * DRIFT_AMPLITUDE
		rotation = velocity.angle()
		move_and_slide()
	else:
		rotation = to_target.angle()
		velocity = Vector2.ZERO
		_attack_cooldown -= delta
		if _attack_cooldown <= 0.0:
			_target.take_damage(damage)
			_attack_cooldown = attack_interval
