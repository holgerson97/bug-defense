class_name Util
extends RefCounted
## Small shared helpers used across entities.

const UNPOWERED_TINT := Color(0.6, 0.7, 1.0, 0.85)

## Nearest member of `group` to `from` within `max_dist`, skipping `exclude`.
## With `require_lit`, members standing in darkness are invisible to the caller.
## With `half_arc` < PI, only members inside the wedge around `facing` count.
## `exclude_group` skips members of another group entirely (ground towers
## pass "air_enemies": only the AA flak cannon may engage air units).
static func nearest_in_group(node, group: String, from: Vector2, max_dist: float, exclude: Array = [], require_lit := false, facing := 0.0, half_arc := PI, exclude_group := ""):
	var nearest = null
	var best := max_dist
	for member in node.get_tree().get_nodes_in_group(group):
		if member in exclude:
			continue
		if exclude_group != "" and member.is_in_group(exclude_group):
			continue
		var dist: float = member.global_position.distance_to(from)
		if dist <= best:
			if require_lit and not is_lit(node, member.global_position):
				continue
			if not in_arc(from, facing, half_arc, member.global_position):
				continue
			best = dist
			nearest = member
	return nearest

## True when no terrain (rocks, ore deposits — layer 16) blocks the line from
## `from` to `to`. Player buildings never block sight: towers shoot over walls.
static func has_los(node, from: Vector2, to: Vector2) -> bool:
	var params := PhysicsRayQueryParameters2D.create(from, to, 16)
	return node.get_world_2d().direct_space_state.intersect_ray(params).is_empty()

## nearest_in_group filtered by terrain line of sight from `from`: tries up to
## 4 nearest candidates before giving up (used on target acquisition only).
static func nearest_visible_in_group(node, group: String, from: Vector2, max_dist: float, exclude: Array = [], require_lit := false, facing := 0.0, half_arc := PI, exclude_group := ""):
	var tried: Array = exclude.duplicate()
	for i in 4:
		var target = nearest_in_group(node, group, from, max_dist, tried, require_lit, facing, half_arc, exclude_group)
		if target == null or has_los(node, from, target.global_position):
			return target
		tried.append(target)
	return null

## True when `pos` lies inside the wedge of `half_arc` radians around `facing`.
## A half arc of PI or more means omnidirectional.
static func in_arc(from: Vector2, facing: float, half_arc: float, pos: Vector2) -> bool:
	if half_arc >= PI:
		return true
	return absf(Vector2.from_angle(facing).angle_to(pos - from)) <= half_arc

## True when any light source (light pools, searchlight beams) reveals `pos` —
## or when the world is currently in (mostly) daylight, where towers see
## everything. The day/night controller (scripts/day_night.gd, group
## "day_night") owns the darkness factor; no controller = classic permanent
## night, gated by lights only.
static func is_lit(node, pos: Vector2) -> bool:
	var day_night = node.get_tree().get_first_node_in_group("day_night")
	if day_night != null and day_night.darkness_factor() < 0.5:
		return true
	for source in node.get_tree().get_nodes_in_group("light_sources"):
		if source.covers(pos):
			return true
	return false

## Color from a balance-style [r, g, b] / [r, g, b, a] array; anything else
## returns `fallback` (world params degrade to the classic midnight look).
static func color_arr(v, fallback: Color) -> Color:
	if v is Array and v.size() >= 3:
		var c := Color(float(v[0]), float(v[1]), float(v[2]))
		if v.size() >= 4:
			c.a = float(v[3])
		return c
	return fallback

## Display suffix per resource kind; "scrap" renders as bug hearts.
const DISPLAY_SUFFIX := {"scrap": "h", "crystal": "c", "gold": "g"}

## Compact cost string like "120h 40c" from a cost dictionary.
static func cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for kind in cost:
		parts.append("%d%s" % [cost[kind], DISPLAY_SUFFIX.get(kind, kind.substr(0, 1))])
	return " ".join(parts)

## Energy-starved consumers dim blue and show a blinking bolt icon until
## their next successful spend.
static func apply_power_tint(node, powered: bool) -> void:
	node.modulate = Color(1, 1, 1, 1) if powered else UNPOWERED_TINT
	var icon = node.get_node_or_null("NoPowerIcon")
	if powered:
		if icon != null:
			icon.queue_free()
		return
	if icon != null:
		return
	icon = Sprite2D.new()
	icon.name = "NoPowerIcon"
	icon.texture = load("res://assets/icons/energy.svg")
	icon.scale = Vector2(0.4, 0.4)
	icon.top_level = true
	icon.z_index = 60
	node.add_child(icon)
	icon.global_position = node.global_position + Vector2(0, -36)
	var tween = icon.create_tween().set_loops()
	tween.tween_property(icon, "modulate:a", 0.25, 0.4)
	tween.tween_property(icon, "modulate:a", 1.0, 0.4)
