extends "res://scripts/building.gd"
## Battery: passive storage building — each standing one raises the shared
## energy cap (GameState counts the "batteries" group). No production.

func _ready() -> void:
	super._ready()
	PowerGrid.register_source(self)
	GameState.energy_cap_changed()
	# Leaving the tree (destroyed or sold) drops the cap and re-clamps energy.
	tree_exited.connect(GameState.energy_cap_changed)
