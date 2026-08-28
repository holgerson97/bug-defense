extends PointLight2D
## Reusable warm light pool: builds its own radial texture from `radius`
## and joins "light_sources" so towers can check what the night reveals.

const TEXTURE_SIZE := 256

@export var radius: float = 120.0

func _ready() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.95, 0.82, 1.0),
		Color(1.0, 0.9, 0.7, 0.55),
		Color(1.0, 0.85, 0.6, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = TEXTURE_SIZE
	tex.height = TEXTURE_SIZE
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	texture = tex
	texture_scale = radius * 2.0 / TEXTURE_SIZE
	color = Color(1.0, 0.93, 0.8)
	energy = 1.1
	add_to_group("light_sources")

## Vision check used by Util.is_lit: anything inside the pool is visible.
func covers(pos: Vector2) -> bool:
	return global_position.distance_to(pos) <= radius
