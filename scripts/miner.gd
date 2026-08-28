extends Node2D
## Placed next to a crystal block; extracts 2 crystal every 2 seconds until empty.

const EXTRACT_INTERVAL := 2.0
const EXTRACT_AMOUNT := 2
const SIDE_OFFSET := 44.0
const ENERGY_PER_CYCLE := 1
const BOB_PIXELS := 2.5
const WOBBLE_RAD := 0.05
const BOBS_PER_CYCLE := 3.0
const SPRITE_SCALE := 0.5

var deposit

var _accum: float = 0.0
var _powered: bool = true
var _strike_tween: Tween

@onready var _sprite: Sprite2D = $Sprite
@onready var _fog: CPUParticles2D = $Fog

func _ready() -> void:
	# Snap to the side of the block facing the nearest player (the one placing).
	var dir := Vector2.DOWN
	var player = Util.nearest_in_group(self, "player", global_position, INF)
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
		_fog.emitting = false
		return
	_accum += delta
	while _accum >= EXTRACT_INTERVAL:
		_accum -= EXTRACT_INTERVAL
		# Each extraction cycle drinks energy; starved miners skip the cycle.
		if not GameState.try_spend_energy(ENERGY_PER_CYCLE):
			_set_powered(false)
			continue
		_set_powered(true)
		var taken = deposit.extract(EXTRACT_AMOUNT + GameState.miner_yield_bonus())
		if taken > 0:
			## Host banks the crystal; replicated miners keep the visuals only
			## (client try_spend_energy above is a mirror check, no spend).
			if Net.is_host():
				GameState.add_resource("crystal", taken)
			_strike()
	_animate()

## Drill bob + rotation wobble synced to the extraction cycle; freezes when starved.
func _animate() -> void:
	_fog.emitting = _powered
	if not _powered:
		_sprite.position.y = 0.0
		_sprite.rotation = 0.0
		return
	var phase := _accum / EXTRACT_INTERVAL * TAU * BOBS_PER_CYCLE
	_sprite.position.y = -absf(sin(phase)) * BOB_PIXELS
	_sprite.rotation = sin(phase * 0.5) * WOBBLE_RAD

## Quick scale punch when the yield tick lands.
func _strike() -> void:
	if _strike_tween != null and _strike_tween.is_valid():
		_strike_tween.kill()
	_sprite.scale = Vector2.ONE * SPRITE_SCALE
	_strike_tween = create_tween()
	_strike_tween.tween_property(_sprite, "scale", Vector2.ONE * SPRITE_SCALE * 1.16, 0.06)
	_strike_tween.tween_property(_sprite, "scale", Vector2.ONE * SPRITE_SCALE, 0.18)

func _set_powered(p: bool) -> void:
	if p == _powered:
		return
	_powered = p
	Util.apply_power_tint(self, p)
