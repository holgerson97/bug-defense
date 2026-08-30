extends Control
## Minimap (bottom-right): player-centered tactical view. Red dots = enemies
## (clamped to the rim when beyond range, so off-map attacks still show their
## direction), teal = buildings, green = players, violet = hives, cyan =
## crystal, gold = gold. Redraws a few times a second — dot counts are small.

const WORLD_RADIUS := 2200.0    ## world distance mapped to the map radius
const REDRAW_INTERVAL := 0.2

const COL_BG := Color(0.07, 0.08, 0.12, 0.82)
const COL_RIM := Color(0.3, 0.5, 0.7, 0.5)
const COL_ENEMY := Color(0.95, 0.25, 0.25, 0.95)
const COL_AIR := Color(1.0, 0.55, 0.3, 0.95)
const COL_BUILDING := Color(0.35, 0.8, 0.75, 0.9)
const COL_PLAYER := Color(0.4, 1.0, 0.5, 1.0)
const COL_HIVE := Color(0.75, 0.4, 1.0, 0.95)
const COL_CRYSTAL := Color(0.6, 0.45, 1.0, 0.8)
const COL_GOLD := Color(0.95, 0.8, 0.3, 0.8)

var _redraw_accum := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_redraw_accum += delta
	if _redraw_accum >= REDRAW_INTERVAL:
		_redraw_accum = 0.0
		queue_redraw()

func _center() -> Vector2:
	var player = get_tree().get_first_node_in_group("player")
	return player.global_position if player != null else Vector2.ZERO

func _draw() -> void:
	var half := size / 2.0
	var radius := minf(half.x, half.y) - 2.0
	draw_circle(half, radius, COL_BG)
	draw_arc(half, radius, 0.0, TAU, 48, COL_RIM, 2.0)
	var center := _center()
	var map_scale := radius / WORLD_RADIUS
	## Beyond-range dots clamp to the rim: "the attack comes from there".
	for group_info in [
		["gold_deposits", COL_GOLD, 1.6, false],
		["deposits", COL_CRYSTAL, 1.6, false],
		["buildings", COL_BUILDING, 2.0, false],
		["hive_sites", COL_HIVE, 3.2, true],
		["enemies", COL_ENEMY, 2.2, true],
		["player", COL_PLAYER, 3.0, false],
	]:
		var color: Color = group_info[1]
		var dot: float = group_info[2]
		var clamp_rim: bool = group_info[3]
		for node in get_tree().get_nodes_in_group(group_info[0]):
			var off: Vector2 = (node.global_position - center) * map_scale
			var dist := off.length()
			if dist > radius:
				if not clamp_rim:
					continue
				off = off / dist * (radius - 2.0)
			var draw_color := color
			if group_info[0] == "enemies" and node.is_in_group("air_enemies"):
				draw_color = COL_AIR
			draw_circle(half + off, dot, draw_color)
