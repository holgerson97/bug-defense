class_name Util
extends RefCounted
## Small shared helpers used across entities.

const UNPOWERED_TINT := Color(0.6, 0.7, 1.0, 0.85)

## Nearest member of `group` to `from` within `max_dist`, skipping `exclude`.
static func nearest_in_group(node, group: String, from: Vector2, max_dist: float, exclude: Array = []):
	var nearest = null
	var best := max_dist
	for member in node.get_tree().get_nodes_in_group(group):
		if member in exclude:
			continue
		var dist: float = member.global_position.distance_to(from)
		if dist <= best:
			best = dist
			nearest = member
	return nearest

## Energy-starved consumers dim blue until their next successful spend.
static func apply_power_tint(node, powered: bool) -> void:
	node.modulate = Color(1, 1, 1, 1) if powered else UNPOWERED_TINT
