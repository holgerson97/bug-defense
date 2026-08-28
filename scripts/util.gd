class_name Util
extends RefCounted
## Small shared helpers used across entities.

const UNPOWERED_TINT := Color(0.6, 0.7, 1.0, 0.85)

## Nearest member of `group` to `from` within `max_dist`, skipping `exclude`.
## With `require_lit`, members standing in darkness are invisible to the caller.
static func nearest_in_group(node, group: String, from: Vector2, max_dist: float, exclude: Array = [], require_lit := false):
	var nearest = null
	var best := max_dist
	for member in node.get_tree().get_nodes_in_group(group):
		if member in exclude:
			continue
		var dist: float = member.global_position.distance_to(from)
		if dist <= best:
			if require_lit and not is_lit(node, member.global_position):
				continue
			best = dist
			nearest = member
	return nearest

## True when any light source (light pools, searchlight beams) reveals `pos`.
static func is_lit(node, pos: Vector2) -> bool:
	for source in node.get_tree().get_nodes_in_group("light_sources"):
		if source.covers(pos):
			return true
	return false

## Compact cost string like "120s 40c" from a cost dictionary.
static func cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for kind in cost:
		parts.append("%d%s" % [cost[kind], kind.substr(0, 1)])
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
