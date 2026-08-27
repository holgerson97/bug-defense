extends StaticBody2D
## Farmable crystal block. Bullets chip crystal off it; a Miner placed
## next to it drains it over time.

var crystal: int = 0
var has_miner: bool = false

@onready var _body: Polygon2D = $Body
@onready var _core: Polygon2D = $Core
@onready var _amount_label: Label = $AmountLabel

func _ready() -> void:
	if crystal <= 0:
		crystal = randi_range(40, 80)
	_update_visual()

## Bullet hits chip off 2 crystal directly into the player's stash.
func take_damage(_amount: int) -> void:
	var taken := extract(2)
	if taken > 0:
		GameState.add_resource("crystal", taken)

## Remove up to `amount` crystal and return how much was actually removed.
func extract(amount: int) -> int:
	if crystal <= 0:
		return 0
	var taken: int = mini(amount, crystal)
	crystal -= taken
	_update_visual()
	if crystal <= 0 and not has_miner:
		queue_free()
	return taken

func _update_visual() -> void:
	_amount_label.text = str(crystal)
	if crystal <= 0:
		# Depleted but kept alive for an attached miner: dim and inert.
		_body.modulate = Color(0.4, 0.4, 0.4, 0.5)
		_core.modulate = Color(0.4, 0.4, 0.4, 0.5)
		_amount_label.text = "empty"
