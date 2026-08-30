extends PointLight2D
## Reusable warm light pool: builds its own radial texture from `radius`
## and joins "light_sources" so towers can check what the night reveals.

const TEXTURE_SIZE := 256

## One texture for every pool: the gradient is instance-independent, only
## texture_scale differs per light.
static var _shared_texture: GradientTexture2D

@export var radius: float = 120.0

static func _get_shared_texture() -> GradientTexture2D:
	if _shared_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		gradient.colors = PackedColorArray([
			Color(1.0, 0.95, 0.82, 1.0),
			Color(1.0, 0.9, 0.7, 0.55),
			Color(1.0, 0.85, 0.6, 0.0),
		])
		_shared_texture = GradientTexture2D.new()
		_shared_texture.gradient = gradient
		_shared_texture.width = TEXTURE_SIZE
		_shared_texture.height = TEXTURE_SIZE
		_shared_texture.fill = GradientTexture2D.FILL_RADIAL
		_shared_texture.fill_from = Vector2(0.5, 0.5)
		_shared_texture.fill_to = Vector2(0.5, 0.0)
	return _shared_texture

const BASE_ENERGY := 1.1

func _ready() -> void:
	texture = _get_shared_texture()
	texture_scale = radius * 2.0 / TEXTURE_SIZE
	color = Color(1.0, 0.93, 0.8)
	energy = BASE_ENERGY
	add_to_group("light_sources")
	## Lights born mid-day start faded (worlds with day/night broadcast the
	## factor on change; a fresh spawn must not pop in at full glow at noon).
	var dn = get_tree().get_first_node_in_group("day_night")
	set_darkness(dn.darkness_factor() if dn != null else 1.0)

## Day/night: fade with the darkness — off in daylight, full at night.
func set_darkness(f: float) -> void:
	energy = BASE_ENERGY * f
	visible = f > 0.02

## Vision check used by Util.is_lit: anything inside the pool is visible.
## Hidden lights (e.g. an unpowered searchlight spot) reveal nothing.
func covers(pos: Vector2) -> bool:
	if not is_visible_in_tree():
		return false
	return global_position.distance_to(pos) <= radius
