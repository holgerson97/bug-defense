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

var has_miner: bool = false
## Remaining ore. Spawners may assign a share BEFORE add_child (starter
## patches); -1 resolves to the per-kind chunk default on ready.
var amount: int = -1
## Spawn-time amount; the late-join mirror only replays changed deposits.
var initial_amount: int = 0

func _ready() -> void:
	if amount < 0:
		amount = maxi(Balance.inum("resources/chunk_%s_amount" % kind,
			800 if kind == "crystal" else 500), 1)
	initial_amount = amount
	_refresh()
	_register_nav()

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
	amount = value
	_refresh()
	## Host: queue this deposit for the batched remaining-amount mirror.
	if Net.is_online() and Net.is_host():
		var main = get_tree().current_scene
		if main != null and main.has_method("mark_deposit_dirty"):
			main.mark_deposit_dirty(self)

## Client: authoritative remainder from the host's mirror.
func set_remote_amount(value: int) -> void:
	amount = maxi(value, 0)
	_refresh()

## Label + husk dimming. Only the Body sprite dims: an attached miner is a
## CHILD of this node, so a whole-node modulate would swallow its power tint.
func _refresh() -> void:
	$AmountLabel.text = str(amount) if amount > 0 else "empty"
	$Body.modulate = EMPTY_TINT if amount <= 0 else Color(1, 1, 1)
