extends StaticBody2D
## Ore deposit: an infinite mineral block. Crystal chips into the player's
## stash when shot and feeds Miners; gold ignores bullets and is mined only
## by Harvesters trained at the Command Center.

@export var kind: String = "crystal"
@export var chips_on_bullet: bool = true

var has_miner: bool = false

func _ready() -> void:
	$AmountLabel.text = "∞"

func take_damage(_amount: int) -> void:
	if chips_on_bullet:
		GameState.add_resource(kind, extract(2))

## Infinite for now: always yields the full requested amount.
func extract(amount: int) -> int:
	return amount
