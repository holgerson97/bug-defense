extends Sprite2D
## Spore mound breathing: a squishy asymmetric pulse — the sacs inflate a
## touch slower than they deflate, with per-instance phase so a cluster of
## mounds never breathes in sync.

const RATE := 0.45              ## breaths per second
const AMOUNT := 0.05            ## +-5% scale

var _t: float = 0.0
var _phase: float = 0.0
var _base_scale := Vector2.ONE

func _ready() -> void:
	_phase = randf() * TAU
	_base_scale = scale

func _process(delta: float) -> void:
	_t += delta
	var wave := sin(_t * RATE * TAU + _phase)
	## Sharpen the exhale: bias the sine so inflation lingers.
	wave = signf(wave) * pow(absf(wave), 0.7)
	## Squash-and-stretch: x and y counter-phase for the fleshy feel.
	scale = Vector2(
		_base_scale.x * (1.0 + wave * AMOUNT),
		_base_scale.y * (1.0 - wave * AMOUNT * 0.7)
	)
