extends "res://scripts/enemy.gd"
## Kites the player at range and periodically summons a swarm of runners.

const RETREAT_SPEED_MULT := 1.35
const FIRST_CAST_DELAY := 2.0
const FAN_HALF_ARC := 1.4

var kite_distance: float = Balance.num("enemies/mage/kite_distance", 440.0)
var approach_distance: float = Balance.num("enemies/mage/approach_distance", 540.0)
var cast_interval: float = Balance.num("enemies/mage/cast_interval", 8.0)
var max_alive_summons: int = Balance.inum("enemies/mage/max_alive_summons", 40)
var summon_count: int = Balance.inum("enemies/mage/summon_count", 20)

var _cast_timer: float = cast_interval - FIRST_CAST_DELAY
var _summons: Array = []

## The mage kites the nearest PLAYER specifically; buildings never distract it.
func _pick_target():
	return Util.nearest_in_group(self, "player", global_position, INF)

func _behave(delta) -> void:
	var to_player: Vector2 = _target.global_position - global_position
	var dist := to_player.length()
	var move := Vector2.ZERO
	var spd := speed
	if dist < kite_distance:
		## Panic retreat: the mage stays behind its swarm.
		move = -to_player.normalized()
		spd *= RETREAT_SPEED_MULT
	elif dist > approach_distance:
		move = to_player.normalized()
	if move != Vector2.ZERO:
		_steered_move(move, spd, delta)
		## Face the walk direction while moving; only stare at the player
		## when standing to cast (no x-ray glares through rocks).
		if velocity.length_squared() > 100.0:
			rotation = velocity.angle()
	else:
		rotation = to_player.angle()
		velocity = Vector2.ZERO
		move_and_slide()
		_steering_reset()

	_cast_timer += delta
	if _cast_timer >= cast_interval:
		_cast_timer = 0.0
		_summon_swarm()

## One cast births 20 runners fanned toward the player in a wide arc across
## three distance rings, so the swarm screens the mage without clumping.
## Alive summons are capped to avoid runaway. Host-only by construction (AI
## is puppet-gated); spawns route through the wave manager's replicated path.
@warning_ignore("integer_division")
func _summon_swarm() -> void:
	var wm = get_tree().get_first_node_in_group("wave_manager")
	if wm == null:
		return
	_summons = _summons.filter(func(s): return is_instance_valid(s))
	var wave: int = wm.wave
	var toward: float = (_target.global_position - global_position).angle()
	for i in summon_count:
		if _summons.size() >= max_alive_summons:
			return
		var a: float = toward + lerpf(-FAN_HALF_ARC, FAN_HALF_ARC, float(i) / float(summon_count - 1))
		var ring: float = 60.0 + float(i % 3) * 45.0
		var pos: Vector2 = global_position + Vector2.from_angle(a) * (ring + randf_range(-10.0, 10.0))
		var runner = wm.spawn_summon(pos, Balance.inum("enemies/runner/hp", 1) + wave / 10, wave * 2.0, counted)
		if runner != null:
			_summons.append(runner)
