extends "res://scripts/enemy.gd"
## Boss (every 10th wave): giant cockroach that births runner broods while
## alive — and spits out bugs when wounded. Crossing 75/50/25% HP triggers a
## rage brood: a full ring at once. Each appearance hits harder (wave manager
## scales HP; damage scales here per boss number).

const RAGE_THRESHOLDS := [0.75, 0.5, 0.25]

var birth_interval: float = Balance.num("enemies/boss/birth_interval", 4.5)
var max_alive_brood: int = Balance.inum("enemies/boss/max_alive_brood", 16)
var max_per_brood: int = Balance.inum("enemies/boss/max_per_brood", 8)
## On-hit brood: taking damage spawns bugs, throttled so rapid-fire weapons
## (MG bursts, flame ticks) can't turn the boss into a runner faucet.
var hit_spawn_count: int = Balance.inum("enemies/boss/hit_spawn_count", 2)
var hit_spawn_cooldown: float = Balance.num("enemies/boss/hit_spawn_cooldown", 1.5)
var damage_growth: float = Balance.num("enemies/boss/damage_growth", 1.25)
## Phase 6: enemy HP isn't replicated, but the boss bar must move on clients
## — a tiny periodic host RPC keeps puppet bars honest.
const HP_SYNC_INTERVAL := 1.0

var _birth_timer: float = 0.0
var _brood: Array = []
var _rage_index: int = 0
var _hp_sync_accum: float = 0.0
var _hit_spawn_timer: float = 0.0

@onready var _health_bar: ProgressBar = $HealthBar

func _ready() -> void:
	super()
	## Stronger every appearance: melee damage compounds per boss number
	## (HP already compounds in the wave manager's spawn override).
	var wm = get_tree().get_first_node_in_group("wave_manager")
	if wm != null and wm.boss_every > 0:
		@warning_ignore("integer_division")
		var boss_number: int = maxi(wm.wave / wm.boss_every, 1)
		damage = int(ceil(damage * pow(damage_growth, boss_number - 1)))
	_health_bar.max_value = max_health
	_health_bar.value = health

func _physics_process(delta: float) -> void:
	_health_bar.global_position = global_position + Vector2(-60, -80)
	super(delta)
	## Puppet: bar tracking above is all; broods are host-simulated.
	if _is_puppet():
		return
	## Host-online: mirror HP to the puppets' bars at 1 Hz.
	if Net.is_online():
		_hp_sync_accum += delta
		if _hp_sync_accum >= HP_SYNC_INTERVAL:
			_hp_sync_accum = 0.0
			_rpc_boss_health.rpc(health)
	if _target == null or not is_instance_valid(_target):
		return
	_birth_timer += delta
	if _birth_timer >= birth_interval:
		_birth_timer = 0.0
		_birth(_brood_count())

func take_damage(amount, hit_fx := true) -> void:
	# The roach bleeds hard on death: extra bursts around the body.
	if not _dead and health - int(amount) <= 0:
		for i in 4:
			var off := Vector2.from_angle(randf() * TAU) * randf_range(8.0, 32.0)
			Effects.blood_death(self, global_position + off, Vector2.from_angle(randf() * TAU))
	super(amount, hit_fx)
	_health_bar.value = health
	## Wounded roach spits bugs: every hit (throttled) births a small brood.
	if not _dead and not _is_puppet():
		var now := Time.get_ticks_msec() / 1000.0
		if now - _hit_spawn_timer >= hit_spawn_cooldown:
			_hit_spawn_timer = now
			_birth(hit_spawn_count)
	## Rage broods at HP thresholds; while-loop catches big hits crossing several.
	while not _dead and _rage_index < RAGE_THRESHOLDS.size() and health <= int(max_health * RAGE_THRESHOLDS[_rage_index]):
		_rage_index += 1
		_birth(max_per_brood)

## Host -> clients: puppet health-bar update (spawn overrides made
## max_health identical on every peer, so the ratio matches).
@rpc("authority", "call_remote", "reliable")
func _rpc_boss_health(value: int) -> void:
	health = clampi(value, 0, max_health)
	_health_bar.value = health

## Regular brood size scales with wave: 4 at wave 10 up to 8 at wave 50.
@warning_ignore("integer_division")
func _brood_count() -> int:
	var wm = get_tree().get_first_node_in_group("wave_manager")
	var wave: int = wm.wave if wm != null else 10
	return clampi(3 + wave / 10, 4, max_per_brood)

## Births runners in a ring; alive brood is capped to avoid runaway.
## Host-only by construction (AI is puppet-gated); spawns route through the
## wave manager's replicated spawn path so clients see the brood too.
@warning_ignore("integer_division")
func _birth(count: int) -> void:
	var wm = get_tree().get_first_node_in_group("wave_manager")
	if wm == null:
		return
	_brood = _brood.filter(func(s): return is_instance_valid(s))
	var wave: int = wm.wave
	for i in count:
		if _brood.size() >= max_alive_brood:
			return
		var a := TAU * float(i) / float(count) + randf_range(-0.2, 0.2)
		var pos: Vector2 = global_position + Vector2.from_angle(a) * randf_range(50.0, 70.0)
		var runner = wm.spawn_summon(pos, Balance.inum("enemies/runner/hp", 1) + wave / 10, wave * 2.0, counted)
		if runner != null:
			_brood.append(runner)
