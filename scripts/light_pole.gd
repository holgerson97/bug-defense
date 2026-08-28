extends "res://scripts/building.gd"
## Light pole: cheap, fragile lamp post. All the work happens in its
## LightSource child — a free static pool of vision for nearby towers.

func _ready() -> void:
	super._ready()
	## Balance override for the lamp radius (the LightSource child already ran
	## its _ready, so re-derive its texture scale from the new radius).
	var light = $LightSource
	light.radius = Balance.num("buildings/light_pole/radius", light.radius)
	light.texture_scale = light.radius * 2.0 / light.TEXTURE_SIZE
