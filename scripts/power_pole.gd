extends "res://scripts/building.gd"
## Power pole: relays grid power. Connected poles (BFS from sources in
## PowerGrid) extend coverage and draw a straight cable to their link parent;
## orphaned poles show the standard starved visual (dim + bolt) and stay inert.

const CABLE_COLOR := Color(0.16, 0.14, 0.12, 0.95)
const CABLE_CORE_COLOR := Color(0.85, 0.62, 0.3, 0.9)
## Cables run from near the pole top, not the base.
const CABLE_ANCHOR := Vector2(0.0, -14.0)

## Spark pulse: travel time along the cable and glow color.
const SPARK_TIME := 1.1
const SPARK_COLOR := Color(1.0, 0.95, 0.55, 0.95)

var _cable: Line2D
var _cable_core: Line2D
var _spark: Polygon2D
var _spark_t: float = 0.0

func _ready() -> void:
	super._ready()
	## Two-layer cable: dark sheath + bright copper core so the run stays
	## readable against pitch-black nights. Above ground, under sprites.
	_cable = Line2D.new()
	_cable.width = 3.5
	_cable.default_color = CABLE_COLOR
	_cable.z_index = 1
	add_child(_cable)
	_cable_core = Line2D.new()
	_cable_core.width = 1.2
	_cable_core.default_color = CABLE_CORE_COLOR
	_cable_core.z_index = 1
	add_child(_cable_core)
	## Tiny diamond spark sliding parent -> pole: power visibly flowing.
	_spark = Polygon2D.new()
	_spark.polygon = PackedVector2Array([Vector2(3, 0), Vector2(0, 3), Vector2(-3, 0), Vector2(0, -3)])
	_spark.color = SPARK_COLOR
	_spark.z_index = 2
	_spark.visible = false
	add_child(_spark)
	_spark_t = randf()
	PowerGrid.grid_changed.connect(_refresh_link)
	PowerGrid.register_pole(self)

func _process(delta: float) -> void:
	if _cable.points.size() < 2:
		_spark.visible = false
		return
	_spark.visible = true
	_spark_t = fmod(_spark_t + delta / SPARK_TIME, 1.0)
	## Straight run, travelling parent -> pole.
	_spark.position = _cable.points[1].lerp(_cable.points[0], _spark_t)
	## Fade in/out at the ends so loops don't pop.
	_spark.modulate.a = clampf(minf(_spark_t, 1.0 - _spark_t) * 8.0, 0.0, 1.0)

## Redraw the cable to the BFS parent (pole, battery, solar, any source) on
## every grid change: a direct line, anchored near the top at both ends.
func _refresh_link() -> void:
	var link = PowerGrid.link_parent(self)
	if link == null or not is_instance_valid(link):
		_cable.points = PackedVector2Array()
		_cable_core.points = PackedVector2Array()
		set_powered(false)
		return
	set_powered(true)
	var points := PackedVector2Array([CABLE_ANCHOR, to_local(link.global_position) + CABLE_ANCHOR])
	_cable.points = points
	_cable_core.points = points
