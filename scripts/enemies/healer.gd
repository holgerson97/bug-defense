extends "res://scripts/enemy.gd"
## Support enemy: never attacks. Keeps its distance from the player,
## drifts toward the nearest other enemy, and pulses a heal periodically.

const KEEP_DISTANCE := 250.0
const HEAL_RADIUS := 150.0
const HEAL_INTERVAL := 1.5
const HEAL_AMOUNT := 2
const PULSE_TIME := 0.4

var _heal_timer: float = 0.0

func _behave(delta) -> void:
	var to_player: Vector2 = _target.global_position - global_position
	var move := Vector2.ZERO
	if to_player.length() < KEEP_DISTANCE:
		move = -to_player.normalized()
	else:
		var ally = _nearest_ally()
		if ally != null:
			var to_ally: Vector2 = ally.global_position - global_position
			if to_ally.length() > 40.0:
				move = to_ally.normalized()
	velocity = move * speed
	rotation = move.angle() if move != Vector2.ZERO else to_player.angle()
	move_and_slide()

	_heal_timer += delta
	if _heal_timer >= HEAL_INTERVAL:
		_heal_timer = 0.0
		_heal_pulse()

func _nearest_ally():
	var best = null
	var best_dist := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not is_instance_valid(e):
			continue
		var dist: float = e.global_position.distance_to(global_position)
		if dist < best_dist:
			best_dist = dist
			best = e
	return best

func _heal_pulse() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not e.has_method("heal"):
			continue
		if e.global_position.distance_to(global_position) <= HEAL_RADIUS:
			e.heal(HEAL_AMOUNT)
	_spawn_pulse_ring()

## Short-lived expanding ring; the tween frees it (and it dies with us).
func _spawn_pulse_ring() -> void:
	var ring := Line2D.new()
	var pts := PackedVector2Array()
	for i in 25:
		pts.append(Vector2.from_angle(TAU * i / 24.0) * 20.0)
	ring.points = pts
	ring.width = 3.0
	ring.default_color = Color(0.4, 1.0, 0.55, 0.8)
	add_child(ring)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector2.ONE * (HEAL_RADIUS / 20.0), PULSE_TIME)
	tween.tween_property(ring, "modulate:a", 0.0, PULSE_TIME)
	tween.chain().tween_callback(ring.queue_free)
