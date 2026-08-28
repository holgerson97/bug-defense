extends StaticBody2D
## Shared base for placeable buildings: health bar, enemy gnaw damage,
## healing, and a debris burst on destruction. Towers extend this script.


const GNAW_DPS := 4.0

@export var max_health: int = 60
@export var health_bar_offset: Vector2 = Vector2(-18, -30)

## Placement direction in radians, set by the build controller before the
## building enters the tree. Directional towers only attack inside their arc
## around it; the searchlight starts its sweep here.
var facing: float = 0.0

## Consumers (towers, searchlight, command center) set this in _ready so they
## show the blinking off-grid bolt even while idle, not only on a failed spend.
var energy_consumer := false

var health: int
var _gnaw_accum: float = 0.0
var _destroyed: bool = false
var _powered: bool = true
var _grid_ok: bool = true
var _grid_accum: float = 0.0

@onready var _health_bar: ProgressBar = $HealthBar
@onready var _sense: Area2D = $Sense

func _ready() -> void:
	max_health = int(ceil(max_health * GameState.building_hp_mult()))
	health = max_health
	_update_health_bar()
	_register_nav()

## Mark the lattice cells under the collision rect as gnawable NavGrid
## obstacles; freed when destroyed or sold. grow(2) guards cell centers
## landing exactly on the rect edge (32px wall case).
func _register_nav() -> void:
	var rect: Rect2 = ($CollisionShape2D as CollisionShape2D).shape.get_rect().grow(2.0)
	rect.position += global_position
	var cells := NavGrid.cells_in_rect(rect)
	NavGrid.occupy_cells(cells, NavGrid.KIND_BUILDING)
	tree_exited.connect(func(): NavGrid.release_cells(cells))

func _physics_process(delta: float) -> void:
	_health_bar.global_position = global_position + health_bar_offset
	# Off-grid consumers dim + bolt immediately; _grid_ok remembers the dim was
	# grid-caused so we never clear an energy-starvation dim from spend paths.
	if energy_consumer:
		_grid_accum += delta
		if _grid_accum >= 0.5:
			_grid_accum = 0.0
			if not grid_powered():
				_grid_ok = false
				set_powered(false)
			elif not _grid_ok and GameState.resources.get("energy", 0) > 0:
				## Spend paths stay the authority for starvation dims; the
				## watchdog only handles grid-caused dims.
				_grid_ok = true
				set_powered(true)
	## Online, building HP is host-simulated only; clients receive it via
	## _rpc_set_health (their local enemy sims must not double-gnaw).
	if Net.is_online() and not Net.is_host():
		return
	# Each touching enemy gnaws GNAW_DPS HP per second.
	var gnawers := 0
	for body in _sense.get_overlapping_bodies():
		if body.is_in_group("enemies"):
			gnawers += 1
	if gnawers > 0:
		_gnaw_accum += gnawers * GNAW_DPS * delta
		if _gnaw_accum >= 1.0:
			var dmg := int(_gnaw_accum)
			_gnaw_accum -= dmg
			take_damage(dmg)

## True when this building sits in grid coverage: near a connected power pole
## or any power source. Energy consumers check this before spending.
func grid_powered() -> bool:
	return PowerGrid.covered(global_position)

## Energy-starved towers dim blue until their next successful spend.
func set_powered(p: bool) -> void:
	if p == _powered:
		return
	_powered = p
	Util.apply_power_tint(self, p)

func take_damage(amount: int) -> void:
	## Client-side sims (enemies/towers until Phase 5) no-op: HP is host-owned.
	if Net.is_online() and not Net.is_host():
		return
	if _destroyed:
		return
	health = maxi(health - amount, 0)
	_update_health_bar()
	if Net.is_online():
		_rpc_set_health.rpc(health)
	if health == 0:
		_destroyed = true
		Effects.debris_burst(self, global_position)
		Sfx.play("explosion", global_position, -8.0)
		queue_free()

func heal(amount: int) -> void:
	## Same authority rule as take_damage: client sims (repair towers) no-op.
	if Net.is_online() and not Net.is_host():
		return
	if _destroyed:
		return
	var prev := health
	health = mini(health + amount, max_health)
	_update_health_bar()
	if health != prev and Net.is_online():
		_rpc_set_health.rpc(health)

## Client-AUTHORITATIVE heal intents (the player's heal beam) route to the
## host here; local sims keep calling heal() directly and no-op on clients.
func request_heal(amount: int) -> void:
	if Net.is_online() and not Net.is_host():
		_rpc_heal.rpc_id(1, amount)
	else:
		heal(amount)
		## Phase 6: relay the host player's beam to clients (the healing peer
		## itself is excluded — it already draws its own beam).
		FxEvents.heal_beam(self, 1)

## Client -> host: heal-beam intent.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_heal(amount: int) -> void:
	if multiplayer.is_server() and amount > 0 and amount <= 1000:
		heal(amount)
		FxEvents.heal_beam(self, multiplayer.get_remote_sender_id())

## Host -> clients: authoritative HP. Event-driven (per damage/heal tick),
## reliable — cheap enough, no per-building synchronizer needed. Death FX
## play here; the actual free arrives as a spawner despawn from the host.
@rpc("authority", "call_remote", "reliable")
func _rpc_set_health(value: int) -> void:
	health = clampi(value, 0, max_health)
	_update_health_bar()
	if health == 0 and not _destroyed:
		_destroyed = true
		Effects.debris_burst(self, global_position)
		Sfx.play("explosion", global_position, -8.0)

func _update_health_bar() -> void:
	_health_bar.max_value = max_health
	_health_bar.value = health
	_health_bar.visible = health < max_health
