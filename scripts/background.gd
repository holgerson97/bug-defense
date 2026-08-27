extends Node2D
## Endless grid: redraws only the lines covering the camera's view each frame.

const GRID_STEP := 128.0

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var grid_color := Color(1, 1, 1, 0.05)
	var world_rect: Rect2 = get_viewport().get_canvas_transform().affine_inverse() * get_viewport_rect()
	var x := floorf(world_rect.position.x / GRID_STEP) * GRID_STEP
	while x <= world_rect.end.x:
		draw_line(Vector2(x, world_rect.position.y), Vector2(x, world_rect.end.y), grid_color, 2.0)
		x += GRID_STEP
	var y := floorf(world_rect.position.y / GRID_STEP) * GRID_STEP
	while y <= world_rect.end.y:
		draw_line(Vector2(world_rect.position.x, y), Vector2(world_rect.end.x, y), grid_color, 2.0)
		y += GRID_STEP
