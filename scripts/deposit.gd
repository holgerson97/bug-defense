extends StaticBody2D
## Ore deposit: a FINITE mineral block. Crystal chips into the shared pool
## when shot and feeds Miners; gold ignores bullets and is mined only by
## Harvesters trained at the Command Center. At 0 the block dims to a husk
## (label "empty"), stops yielding and stays in the world — collision and
## NavGrid registration unchanged — as visible depletion history.
##
## CO-OP: spawn amounts are deterministic world gen (identical on every
## peer); DEPLETION is runtime state owned by the HOST. Clients never
## decrement — the host batches remaining amounts through main.gd's
## position-keyed deposit mirror (mark_deposit_dirty -> _rpc_sync_deposits),
## and a client bullet chip routes up as a position-keyed intent
## (main._rpc_chip_deposit). Position-keyed because deposit node paths are
## chunk-seeding-order dependent and can't carry RPCs themselves — same
## reasoning as build_controller's miner placement RPC.

@export var kind: String = "crystal"
## Hand-minable with the player's mining beam (gold stays harvester-only).
@export var hand_minable: bool = true

const EMPTY_TINT := Color(0.42, 0.42, 0.48, 0.9)

## --- Ambient glow (plain PointLight2D — NOT a light_source: it must never
## grant tower vision, it only makes the ore read as precious). ---
const GLOW_RADIUS := 80.0
const GLOW_TEXTURE_SIZE := 64
## Peak idle energy per kind at full deposit, full darkness. Violet needs a
## little more juice than warm gold to read equally at night.
const GLOW_ENERGY_CRYSTAL := 1.0
const GLOW_ENERGY_GOLD := 0.75
const GLOW_COLOR_CRYSTAL := Color(0.66, 0.5, 1.0)
const GLOW_COLOR_GOLD := Color(1.0, 0.78, 0.35)
## Near-empty deposits keep a faint ember of glow until the last unit.
const GLOW_MIN_RATIO := 0.15
## Idle pulse: slow sine on energy, phase derived from position so fields
## shimmer organically instead of breathing in lockstep.
const PULSE_SPEED := 1.4
const PULSE_DEPTH := 0.14
## Daylight floor: the glow mostly washes out at noon, blooms at night.
const GLOW_DAY_MIN := 0.3
## Mining reaction: energy spike decaying over FLARE_TIME.
const FLARE_ENERGY := 1.3
const FLARE_TIME := 0.3

## One radial texture for every deposit glow; tinted per-light via color.
static var _glow_texture: GradientTexture2D
static var _sparkle_gradients: Dictionary = {}

var has_miner: bool = false
## Remaining ore. Spawners may assign a share BEFORE add_child (starter
## patches); -1 resolves to the per-kind chunk default on ready.
var amount: int = -1
## Spawn-time amount; the late-join mirror only replays changed deposits.
var initial_amount: int = 0

var _glow: PointLight2D
var _sparkles: CPUParticles2D
var _punch_tween: Tween
var _body_scale := Vector2.ONE
var _pulse_phase: float = 0.0
var _flare: float = 0.0
## Cached day/night controller (may not exist yet when chunks spawn).
var _day_night = null

func _ready() -> void:
	if amount < 0:
		amount = maxi(Balance.inum("resources/chunk_%s_amount" % kind,
			800 if kind == "crystal" else 500), 1)
	initial_amount = amount
	_body_scale = ($Body as Sprite2D).scale
	## NOT randf(): world gen is deterministic across peers and deposits spawn
	## mid-generation — consuming the global RNG here could desync the stream.
	_pulse_phase = fposmod(global_position.x * 0.173 + global_position.y * 0.131, TAU)
	_build_glow()
	_build_sparkles()
	_refresh()
	_register_nav()

static func _get_glow_texture() -> GradientTexture2D:
	if _glow_texture == null:
		_glow_texture = Effects.radial_light_texture(
			Color(1, 1, 1, 1), Color(1, 1, 1, 0), GLOW_TEXTURE_SIZE)
	return _glow_texture

static func _get_sparkle_gradient(for_kind: String) -> Gradient:
	if not _sparkle_gradients.has(for_kind):
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		gradient.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 1.0),
			Color(0.85, 0.72, 1.0, 0.9) if for_kind == "crystal"
				else Color(1.0, 0.88, 0.55, 0.9),
			Color(0.6, 0.4, 1.0, 0.0) if for_kind == "crystal"
				else Color(1.0, 0.7, 0.2, 0.0),
		])
		_sparkle_gradients[for_kind] = gradient
	return _sparkle_gradients[for_kind]

func _build_glow() -> void:
	_glow = PointLight2D.new()
	_glow.texture = _get_glow_texture()
	_glow.texture_scale = GLOW_RADIUS * 2.0 / GLOW_TEXTURE_SIZE
	_glow.color = GLOW_COLOR_CRYSTAL if kind == "crystal" else GLOW_COLOR_GOLD
	_glow.energy = 0.0
	add_child(_glow)

func _build_sparkles() -> void:
	_sparkles = CPUParticles2D.new()
	_sparkles.emitting = false
	_sparkles.one_shot = true
	_sparkles.explosiveness = 1.0
	_sparkles.amount = 4
	_sparkles.lifetime = 0.35
	_sparkles.direction = Vector2.UP
	_sparkles.spread = 180.0
	_sparkles.gravity = Vector2(0, 60)
	_sparkles.initial_velocity_min = 40.0
	_sparkles.initial_velocity_max = 90.0
	_sparkles.scale_amount_min = 1.2
	_sparkles.scale_amount_max = 2.4
	_sparkles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_sparkles.emission_sphere_radius = 14.0
	_sparkles.color_ramp = _get_sparkle_gradient(kind)
	_sparkles.z_index = 5
	add_child(_sparkles)

## Idle pulse + flare decay + day/night fade, all funneled into glow energy.
## Cheap (one sin per frame per deposit) and pause-safe: _process halts with
## the tree, so tweens/particles/glow all freeze together.
func _process(delta: float) -> void:
	_pulse_phase = fposmod(_pulse_phase + delta * PULSE_SPEED, TAU)
	if _flare > 0.0:
		_flare = maxf(_flare - delta * FLARE_ENERGY / FLARE_TIME, 0.0)
	if _day_night == null or not is_instance_valid(_day_night):
		_day_night = get_tree().get_first_node_in_group("day_night")
	var dark: float = _day_night.darkness_factor() if _day_night != null else 1.0
	var ratio := clampf(float(amount) / maxf(float(initial_amount), 1.0), 0.0, 1.0)
	var idle := (GLOW_ENERGY_CRYSTAL if kind == "crystal" else GLOW_ENERGY_GOLD) \
		* lerpf(GLOW_MIN_RATIO, 1.0, ratio) \
		* (1.0 + PULSE_DEPTH * sin(_pulse_phase)) \
		* lerpf(GLOW_DAY_MIN, 1.0, dark)
	_glow.energy = idle + _flare

func is_empty() -> bool:
	return amount <= 0

## Deposits block enemies physically (layer 16), so their cells must be
## impassable in the NavGrid too or A* paths straight through mineral lines.
## Mirrors building.gd's register/release contract: grow(2) guards cell
## centers landing exactly on the shape rect's edge.
func _register_nav() -> void:
	var rect: Rect2 = ($CollisionShape2D as CollisionShape2D).shape.get_rect().grow(2.0)
	rect.position += global_position
	var cells := NavGrid.cells_in_rect(rect)
	NavGrid.occupy_cells(cells, NavGrid.KIND_ROCK)
	tree_exited.connect(func(): NavGrid.release_cells(cells))

## Bullets no longer chip ore — mining is the player's beam (right-click).
## The method stays so stray projectiles are absorbed without errors.
func take_damage(_damage: int) -> void:
	pass

## Mining-beam tick. Host/offline extracts directly; a client only sends the
## intent (a local decrement would double-bank and drift off the mirror).
func mine_tick() -> void:
	if not hand_minable or is_empty():
		return
	if Net.is_online() and not Net.is_host():
		var main = get_tree().current_scene
		if main != null and main.has_method("_rpc_chip_deposit"):
			main._rpc_chip_deposit.rpc_id(1, global_position)
		return
	GameState.add_resource(kind, extract(GameState.player_mine_amount()))

## Yields min(requested, remaining). Only the host (or offline) decrements;
## clients read their mirrored remainder so visuals stay sane between syncs.
func extract(requested: int) -> int:
	if is_empty():
		return 0
	var taken := mini(requested, amount)
	if Net.is_online() and not Net.is_host():
		return taken
	_set_amount(amount - taken)
	return taken

func _set_amount(value: int) -> void:
	value = maxi(value, 0)
	if value == amount:
		return
	var extracted := value < amount
	amount = value
	_refresh()
	## Any decrease is ore leaving the block — flare regardless of who took it
	## (player beam, miner strike, harvester); they all funnel through here.
	if extracted:
		_play_extract_fx()
	## Host: queue this deposit for the batched remaining-amount mirror.
	if Net.is_online() and Net.is_host():
		var main = get_tree().current_scene
		if main != null and main.has_method("mark_deposit_dirty"):
			main.mark_deposit_dirty(self)

## Client: authoritative remainder from the host's mirror. A drop in the
## mirrored value is the client's extraction signal — fire the same reaction
## so co-op peers see deposits flare when someone else mines them.
func set_remote_amount(value: int) -> void:
	value = maxi(value, 0)
	if value == amount:
		return
	var extracted := value < amount
	amount = value
	_refresh()
	if extracted:
		_play_extract_fx()

## Label + husk dimming. Only the Body sprite dims: an attached miner is a
## CHILD of this node, so a whole-node modulate would swallow its power tint.
## Also the glow gate: empty husks go dark and stop pulsing entirely.
func _refresh() -> void:
	$AmountLabel.text = str(amount) if amount > 0 else "empty"
	$Body.modulate = EMPTY_TINT if amount <= 0 else Color(1, 1, 1)
	if _glow == null:
		return
	var empty := amount <= 0
	if empty:
		_flare = 0.0
		_glow.energy = 0.0
	_glow.visible = not empty
	set_process(not empty)

## Shared mining reaction: glow flare (decays in _process), quick sprite
## scale punch (miner-strike tween pattern) and a tiny shard-sparkle burst.
## Can fire a couple of times per second per deposit — everything here is
## reused, no allocations beyond the tween.
func _play_extract_fx() -> void:
	if amount > 0:
		_flare = FLARE_ENERGY
	if _punch_tween != null and _punch_tween.is_valid():
		_punch_tween.kill()
	var body := $Body as Sprite2D
	body.scale = _body_scale
	_punch_tween = create_tween()
	_punch_tween.tween_property(body, "scale", _body_scale * 1.12, 0.06)
	_punch_tween.tween_property(body, "scale", _body_scale, 0.18)
	_sparkles.restart()
