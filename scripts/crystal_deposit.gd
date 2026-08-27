extends StaticBody2D
## Crystal block. Bullets chip crystal off it; a Miner placed next to it
## extracts continuously. Crystal is infinite for now.

var crystal: int = 1
var has_miner: bool = false

@onready var _amount_label: Label = $AmountLabel

func _ready() -> void:
	_amount_label.text = "∞"

## Bullet hits chip crystal directly into the player's stash.
func take_damage(_amount: int) -> void:
	GameState.add_resource("crystal", extract(2))

## Infinite for now: always yields the full requested amount.
func extract(amount: int) -> int:
	return amount
