extends CharacterBody2D
## Gold harvester drone trained by a Command Center. Drives to the nearest
## gold block, mines for a moment, hauls the cargo home and repeats. Ignores
## all collision (layer/mask 0) and dies with its command center.


enum State { TO_MINE, MINING, TO_BASE }

const STOP_DIST := 40.0
const SEARCH_RANGE := 1200.0
const RESCAN_INTERVAL := 1.0
const ORBIT_RADIUS := 70.0
const ORBIT_SPEED := 0.9

var speed: float = Balance.num("buildings/harvester/speed", 120.0)
var mine_time: float = Balance.num("buildings/harvester/mine_time", 2.0)
var mine_amount: int = Balance.inum("buildings/harvester/mine_amount", 10)

var command_center
var cargo: int = 0

var _state: int = State.TO_MINE
var _target_deposit
var _mine_accum: float = 0.0
var _rescan_accum: float = RESCAN_INTERVAL
var _orbit_angle: float = randf() * TAU

@onready var _sprite: Sprite2D = $Sprite

func _physics_process(delta: float) -> void:
	if command_center == null or not is_instance_valid(command_center):
		Effects.debris_burst(self, global_position)
		Sfx.play("explosion", global_position, -12.0)
		queue_free()
		return
	match _state:
		State.TO_MINE:
			_to_mine(delta)
		State.MINING:
			_mining(delta)
		State.TO_BASE:
			_to_base()

func _to_mine(delta: float) -> void:
	# Cached target; dropped when gone OR mined dry, re-scan about once a second.
	if _target_deposit == null or not is_instance_valid(_target_deposit) or _target_deposit.is_empty():
		_target_deposit = null
		_rescan_accum += delta
		if _rescan_accum >= RESCAN_INTERVAL:
			_rescan_accum = 0.0
			_target_deposit = _nearest_gold()
	if _target_deposit == null:
		_idle_orbit(delta)
		return
	if global_position.distance_to(_target_deposit.global_position) <= STOP_DIST:
		velocity = Vector2.ZERO
		_mine_accum = 0.0
		_state = State.MINING
		return
	_drive_toward(_target_deposit.global_position)

func _mining(delta: float) -> void:
	velocity = Vector2.ZERO
	if _target_deposit == null or not is_instance_valid(_target_deposit) or _target_deposit.is_empty():
		_sprite.position = Vector2.ZERO
		_target_deposit = null
		_state = State.TO_MINE
		return
	_mine_accum += delta
	# Slight dig shake while chewing on the block.
	_sprite.position = Vector2(randf_range(-1.4, 1.4), randf_range(-1.4, 1.4))
	if _mine_accum >= mine_time:
		_sprite.position = Vector2.ZERO
		cargo = _target_deposit.extract(mine_amount)
		# The bite that emptied the block: haul what we got, hunt elsewhere next.
		if _target_deposit.is_empty():
			_target_deposit = null
		_state = State.TO_BASE

func _to_base() -> void:
	if global_position.distance_to(command_center.global_position) <= STOP_DIST:
		velocity = Vector2.ZERO
		if cargo > 0:
			## Silent delivery: a hauler chorus next to the base got annoying.
			## Client drones are visual-only; the host's bank the real gold.
			if Net.is_host():
				GameState.add_resource("gold", cargo)
			cargo = 0
		_state = State.TO_MINE
		return
	_drive_toward(command_center.global_position)

## Nearest gold block with ore left; empty husks are invisible to harvesters.
func _nearest_gold():
	var best = null
	var best_dist := SEARCH_RANGE
	for dep in get_tree().get_nodes_in_group("gold_deposits"):
		if dep.is_empty():
			continue
		var dist: float = dep.global_position.distance_to(command_center.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = dep
	return best

## No gold in range: slow lazy circle around the command center.
func _idle_orbit(delta: float) -> void:
	_orbit_angle += ORBIT_SPEED * delta
	var point: Vector2 = command_center.global_position + Vector2.from_angle(_orbit_angle) * ORBIT_RADIUS
	if global_position.distance_to(point) < 6.0:
		velocity = Vector2.ZERO
		return
	_drive_toward(point)

func _drive_toward(point: Vector2) -> void:
	velocity = (point - global_position).normalized() * speed
	rotation = velocity.angle()
	move_and_slide()
