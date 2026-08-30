extends Node
## Wave-driven day/night controller, owned by main. Intermission = day; night
## falls as a wave arrives and lifts once it's cleared. Dusk starts DUSK_LEAD
## seconds before the wave countdown ends, so darkness lands WITH the bugs.
## always_night worlds (and the missing-worlds fallback) pin night_modulate and
## never process. The fade is delta-driven in _process — pause-safe for free
## (the node pauses with the tree, like the wave timers it mirrors).
## Towers query darkness_factor() through Util.is_lit: below 0.5 the world
## counts as lit everywhere and light-gating is off.

const DUSK_LEAD := 3.0

var day_color := Color(1, 1, 1)
var night_color := Color(0.06, 0.06, 0.1)
var transition := 4.0
var always_night := true

## 0 = full day, 1 = full night.
var _factor := 1.0
var _target := 1.0
var _darkness: CanvasModulate
## Local mirror of the intermission countdown (same pattern as the HUD's wave
## timer) driving the dusk pre-roll; runs on every peer off the local signals.
var _intermission_left := 0.0

func _ready() -> void:
	add_to_group("day_night")
	set_process(false)

## Wire up from main with the world def, the Darkness node and the wave
## manager. Empty def (unknown/missing world) = permanent night, exactly the
## scene's authored darkness.
func setup(def: Dictionary, darkness: CanvasModulate, wave_manager) -> void:
	_darkness = darkness
	always_night = bool(def.get("always_night", true))
	night_color = Util.color_arr(def.get("night_modulate"), darkness.color)
	transition = maxf(float(def.get("night_transition", 4.0)), 0.01)
	if always_night:
		_factor = 1.0
		_target = 1.0
		_darkness.color = night_color
		return
	day_color = Util.color_arr(def.get("day_modulate"), Color(1, 1, 1))
	## Runs start in the first intermission: full day until the bugs come.
	_factor = 0.0
	_target = 0.0
	_darkness.color = day_color
	wave_manager.wave_started.connect(_on_wave_started)
	wave_manager.intermission_started.connect(_on_intermission_started)
	set_process(true)

## 0..1 for Util.is_lit and anyone else scaling by darkness.
func darkness_factor() -> float:
	return _factor

func _on_wave_started(_wave: int) -> void:
	_intermission_left = 0.0
	_target = 1.0

func _on_intermission_started(seconds: float) -> void:
	_intermission_left = seconds
	_target = 0.0

func _process(delta: float) -> void:
	## Dusk pre-roll: flip to night while the countdown's last seconds tick.
	if _intermission_left > 0.0:
		_intermission_left = maxf(_intermission_left - delta, 0.0)
		if _intermission_left <= DUSK_LEAD:
			_target = 1.0
	if _factor != _target:
		_factor = move_toward(_factor, _target, delta / transition)
		_darkness.color = day_color.lerp(night_color, smoothstep(0.0, 1.0, _factor))
		## Lamps have no business glowing in daylight: every light source
		## fades with the darkness (they query the current factor at spawn).
		get_tree().call_group("light_sources", "set_darkness", _factor)
