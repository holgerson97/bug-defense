extends StaticBody2D
## Gold ore block. Bullets can't chip it — only Harvesters trained at the
## Command Center can mine gold. Infinite for now.

func _ready() -> void:
	$AmountLabel.text = "∞"

## Absorbs bullets without yielding anything.
func take_damage(_amount: int) -> void:
	pass

## Harvester mining entry point: always yields the full requested amount.
func extract(amount: int) -> int:
	return amount
