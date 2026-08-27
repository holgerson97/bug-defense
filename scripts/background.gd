extends Node2D

const GRID_STEP := 128.0

func _draw() -> void:
	var size := GameState.WORLD_SIZE
	var grid_color := Color(1, 1, 1, 0.05)
	var border_color := Color(1, 1, 1, 0.3)
	var x := GRID_STEP
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid_color, 2.0)
		x += GRID_STEP
	var y := GRID_STEP
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), grid_color, 2.0)
		y += GRID_STEP
	draw_rect(Rect2(Vector2.ZERO, size), border_color, false, 4.0)
