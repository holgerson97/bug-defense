extends Node2D
## Placed next to a crystal block; extracts 2 crystal every 2 seconds until empty.

const EXTRACT_INTERVAL := 2.0
const EXTRACT_AMOUNT := 2
const SIDE_OFFSET := 44.0

var deposit

var _accum: float = 0.0

func _ready() -> void:
	# Snap to the side of the block facing the player, drill pointing at it.
	var dir := Vector2.DOWN
	var player = get_tree().get_first_node_in_group("player")
	if player != null:
		var to_player: Vector2 = player.global_position - global_position
		if to_player.length() > 1.0:
			dir = to_player.normalized()
	if absf(dir.x) > absf(dir.y):
		dir = Vector2(signf(dir.x), 0)
	else:
		dir = Vector2(0, signf(dir.y))
	position = dir * SIDE_OFFSET
	rotation = (-dir).angle() + PI / 2.0

func _process(delta: float) -> void:
	if deposit == null or not is_instance_valid(deposit):
		return
	if deposit.crystal <= 0:
		return
	_accum += delta
	while _accum >= EXTRACT_INTERVAL:
		_accum -= EXTRACT_INTERVAL
		var taken = deposit.extract(EXTRACT_AMOUNT)
		if taken > 0:
			GameState.add_resource("crystal", taken)
