extends StaticBody2D
## Ore deposit: an infinite mineral block. Crystal chips into the player's
## stash when shot and feeds Miners; gold ignores bullets and is mined only
## by Harvesters trained at the Command Center.

@export var kind: String = "crystal"
@export var chips_on_bullet: bool = true

var has_miner: bool = false

func _ready() -> void:
	$AmountLabel.text = "∞"
	_register_nav()

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

func take_damage(_amount: int) -> void:
	if chips_on_bullet:
		GameState.add_resource(kind, extract(2))

## Infinite for now: always yields the full requested amount.
func extract(amount: int) -> int:
	return amount
