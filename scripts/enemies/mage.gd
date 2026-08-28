extends "res://scripts/enemy.gd"
## Kites the player at range and periodically summons a swarm of runners.

const KITE_DISTANCE := 440.0
const APPROACH_DISTANCE := 540.0
const RETREAT_SPEED_MULT := 1.35
const CAST_INTERVAL := 8.0
const FIRST_CAST_DELAY := 2.0
const MAX_ALIVE_SUMMONS := 40
const SUMMON_COUNT := 20
const FAN_HALF_ARC := 1.4

var _cast_timer: float = CAST_INTERVAL - FIRST_CAST_DELAY
var _summons: Array = []

## The mage kites the nearest PLAYER specifically; buildings never distract it.
func _pick_target():
	return Util.nearest_in_group(self, "player", global_position, INF)

func _behave(delta) -> void:
	var to_player: Vector2 = _target.global_position - global_position
	var dist := to_player.length()
	var move := Vector2.ZERO
	var spd := speed
	if dist < KITE_DISTANCE:
		## Panic retreat: the mage stays behind its swarm.
		move = -to_player.normalized()
		spd *= RETREAT_SPEED_MULT
	elif dist > APPROACH_DISTANCE:
		move = to_player.normalized()
	rotation = to_player.angle()
	if move != Vector2.ZERO:
		_steered_move(move, spd, delta)
	else:
		velocity = Vector2.ZERO
		move_and_slide()
		_steering_reset()

	_cast_timer += delta
	if _cast_timer >= CAST_INTERVAL:
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
	for i in SUMMON_COUNT:
		if _summons.size() >= MAX_ALIVE_SUMMONS:
			return
		var a: float = toward + lerpf(-FAN_HALF_ARC, FAN_HALF_ARC, float(i) / float(SUMMON_COUNT - 1))
		var ring: float = 60.0 + float(i % 3) * 45.0
		var pos: Vector2 = global_position + Vector2.from_angle(a) * (ring + randf_range(-10.0, 10.0))
		var runner = wm.spawn_summon(pos, 1 + wave / 10, wave * 2.0)
		if runner != null:
			_summons.append(runner)
