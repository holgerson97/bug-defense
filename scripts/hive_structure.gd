extends StaticBody2D
## Damageable hive-site structure: the hive body itself, a spore mound or a
## bile spire. NOT spawner-replicated — hive_site builds these deterministically
## inside the seeded chunk stream, so every peer holds an identical node at an
## identical path; combat state is host-owned and mirrored via the site's RPCs
## (building-HP pattern). Layer 16 like rocks/deposits: player bullets hit and
## call take_damage, players/enemies collide, the build controller's placement
## query (mask includes 16) rejects ghosts on top. NavGrid cells register as
## KIND_ROCK so enemies path around and never stop to gnaw.

## Purple-tinted blood burst = organic ichor (the red base ramp modulated;
## reads as dark violet spray on the shipped blood particles).
const ICHOR_TINT := Color(0.75, 0.5, 1.5)

var kind: String = "hive"          ## "hive" | "spore_mound" | "bile_spire"
var body_radius: float = 30.0
var max_health: int = 200
var health: int = 0
var site = null                    ## owning hive_site
var site_index: int = -1           ## -1 = hive body, >= 0 = satellite slot

var _bar: ProgressBar
var _bar_size := Vector2(48.0, 6.0)
var _bar_offset_y: float = -60.0

func _ready() -> void:
	collision_layer = 16
	collision_mask = 0
	health = max_health
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = body_radius
	shape.shape = circle
	add_child(shape)
	_make_bar()
	_register_nav()

## Boss-style top_level bar, visible only while damaged. Statics never move,
## so the world position is set once — no per-frame tracking.
func _make_bar() -> void:
	if kind == "hive":
		_bar_size = Vector2(120.0, 10.0)
		_bar_offset_y = -150.0
	elif kind == "bile_spire":
		_bar_offset_y = -125.0
	_bar = ProgressBar.new()
	_bar.top_level = true
	_bar.z_index = 20
	_bar.show_percentage = false
	_bar.max_value = max_health
	_bar.value = health
	_bar.size = _bar_size
	_bar.visible = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	_bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.62, 0.85, 0.35, 1.0)
	_bar.add_theme_stylebox_override("fill", fill)
	add_child(_bar)
	_bar.global_position = global_position + Vector2(-_bar_size.x / 2.0, _bar_offset_y)

## Impassable footprint (KIND_ROCK: enemies route around, never gnaw);
## released on tree exit like rocks/deposits, so a cleared site frees its cells
## on every peer.
func _register_nav() -> void:
	var rect := Rect2(global_position, Vector2.ZERO).grow(body_radius)
	var cells := NavGrid.cells_in_rect(rect)
	NavGrid.occupy_cells(cells, NavGrid.KIND_ROCK)
	tree_exited.connect(func(): NavGrid.release_cells(cells))

## Player bullets land here (bullet mask includes layer 16). Host-owned like
## building HP; client hits are cosmetic tracers and no-op.
func take_damage(amount) -> void:
	if Net.is_online() and not Net.is_host():
		return
	if health <= 0 or site == null or not is_instance_valid(site):
		return
	health = maxi(health - int(amount), 0)
	_refresh_bar()
	if health > 0:
		hit_fx()
	site.on_structure_damaged(self)

## Client mirror: absolute HP from the host's RPC (death arrives separately).
func set_health(value: int) -> void:
	var dropped := value < health
	health = clampi(value, 0, max_health)
	_refresh_bar()
	if dropped and health > 0:
		hit_fx()

func _refresh_bar() -> void:
	_bar.value = health
	_bar.visible = health < max_health and health > 0

## Organic hit feedback: the existing blood burst, ichor-tinted.
func hit_fx() -> void:
	var burst = Effects.BLOOD_SCENE.instantiate()
	burst.modulate = ICHOR_TINT
	burst.position = global_position + Vector2.from_angle(randf() * TAU) * body_radius * 0.45
	burst.rotation = randf() * TAU
	var scene = get_tree().current_scene
	if scene != null:
		scene.add_child(burst)
	else:
		burst.free()
