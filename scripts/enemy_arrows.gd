extends Node2D
## Straggler hunt aid: when 5 or fewer enemies remain, small triangles ring
## the player pointing at each far-away one so the wave tail is easy to find.
## Complements the off-screen teleport-back in enemy.gd.

const MAX_ARROWS := 5
const RING_RADIUS := 70.0
## Enemies closer than this are on screen anyway; no arrow.
const NEAR_CUTOFF := 250.0
const ARROW_COLOR := Color(1.0, 0.5, 0.15, 0.8)

var _arrows: Array[Polygon2D] = []

func _ready() -> void:
	## Night's CanvasModulate would swallow the arrows; a follow-viewport
	## CanvasLayer keeps them in world coordinates on an unmodulated canvas.
	var layer := CanvasLayer.new()
	layer.follow_viewport_enabled = true
	add_child(layer)
	for i in MAX_ARROWS:
		var arrow := Polygon2D.new()
		arrow.polygon = PackedVector2Array([Vector2(12, 0), Vector2(-7, -7), Vector2(-7, 7)])
		arrow.color = ARROW_COLOR
		arrow.z_index = 55
		arrow.visible = false
		layer.add_child(arrow)
		_arrows.append(arrow)

func _physics_process(_delta: float) -> void:
	## Polling the group beats signal plumbing: .size() is trivial per frame.
	var enemies := get_tree().get_nodes_in_group("enemies")
	var idx := 0
	if enemies.size() > 0 and enemies.size() <= MAX_ARROWS:
		var center := global_position
		for enemy in enemies:
			if idx >= MAX_ARROWS:
				break
			var offset: Vector2 = enemy.global_position - center
			var dist := offset.length()
			if dist <= NEAR_CUTOFF:
				continue
			var arrow := _arrows[idx]
			idx += 1
			arrow.position = center + offset * (RING_RADIUS / dist)
			arrow.rotation = offset.angle()
			## Slightly smaller when far: cheap distance hint.
			arrow.scale = Vector2.ONE * clampf(1.2 - dist / 1600.0, 0.7, 1.2)
			arrow.visible = true
	for i in range(idx, MAX_ARROWS):
		_arrows[i].visible = false
