extends CharacterBody2D
## Gold harvester drone trained by a Command Center. Drives to the nearest
## gold block, mines for a moment, hauls the cargo home and repeats. Ignores
## all collision (layer/mask 0) and dies with its command center.

const Effects = preload("res://scripts/effects.gd")

enum State { TO_MINE, MINING, TO_BASE }

const SPEED := 120.0
const STOP_DIST := 40.0
const MINE_TIME := 2.0
const MINE_AMOUNT := 10
const SEARCH_RANGE := 1200.0
const RESCAN_INTERVAL := 1.0
const ORBIT_RADIUS := 70.0
const ORBIT_SPEED := 0.9

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
	# Cached target; only re-scan the group about once a second when we have none.
	if _target_deposit == null or not is_instance_valid(_target_deposit):
		_target_deposit = null
		_rescan_accum += delta
		if _rescan_accum >= RESCAN_INTERVAL:
			_rescan_accum = 0.0
			_target_deposit = _nearest_deposit()
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
	if _target_deposit == null or not is_instance_valid(_target_deposit):
		_sprite.position = Vector2.ZERO
		_state = State.TO_MINE
		return
	_mine_accum += delta
	# Slight dig shake while chewing on the block.
	_sprite.position = Vector2(randf_range(-1.4, 1.4), randf_range(-1.4, 1.4))
	if _mine_accum >= MINE_TIME:
		_sprite.position = Vector2.ZERO
		cargo = _target_deposit.extract(MINE_AMOUNT)
		_state = State.TO_BASE

func _to_base() -> void:
	if global_position.distance_to(command_center.global_position) <= STOP_DIST:
		velocity = Vector2.ZERO
		if cargo > 0:
			GameState.add_resource("gold", cargo)
			Sfx.play("place", global_position, -10.0)
			cargo = 0
		_state = State.TO_MINE
		return
	_drive_toward(command_center.global_position)

## No gold in range: slow lazy circle around the command center.
func _idle_orbit(delta: float) -> void:
	_orbit_angle += ORBIT_SPEED * delta
	var point: Vector2 = command_center.global_position + Vector2.from_angle(_orbit_angle) * ORBIT_RADIUS
	if global_position.distance_to(point) < 6.0:
		velocity = Vector2.ZERO
		return
	_drive_toward(point)

func _drive_toward(point: Vector2) -> void:
	velocity = (point - global_position).normalized() * SPEED
	rotation = velocity.angle()
	move_and_slide()

func _nearest_deposit():
	var nearest = null
	var best := SEARCH_RANGE
	for deposit in get_tree().get_nodes_in_group("gold_deposits"):
		var dist: float = deposit.global_position.distance_to(command_center.global_position)
		if dist <= best:
			best = dist
			nearest = deposit
	return nearest
