extends Node2D
## Endless ground: redraws only what covers the camera's view each frame.
## The ground is a real canvas rect so CanvasModulate darkens it and
## PointLight2Ds carve light pools out of it (the raw clear color is
## unaffected by both and sits near-black behind this rect).
## World-themed (main.gd calls set_world): base ground color, cheap
## deterministic per-cell variation — hash-seeded meadow patches and grass
## tufts, stable as the camera moves and identical on every peer, no per-frame
## randomness — plus the subtle grid lines building placement aligns to.
## Worlds whose ground_detail equals ground_color (midnight) skip the
## decoration entirely and look exactly like the classic flat ground.

const GRID_STEP := 128.0
const GROUND_MARGIN := 256.0
## Decoration per 128px cell: chance of one soft accent patch, tuft count.
const PATCH_CHANCE := 0.6
const TUFTS_PER_CELL := 3

var ground_color := Color(0.08, 0.09, 0.13)
var detail_color := Color(0.08, 0.09, 0.13)
var grid_color := Color(1, 1, 1, 0.05)
var _decorated := false
var _tuft_color := Color(0.05, 0.06, 0.09)
## Reused per cell, reseeded from the cell hash: deterministic decoration.
var _rng := RandomNumberGenerator.new()

func _process(_delta: float) -> void:
	queue_redraw()

## World theme hookup; missing keys keep the classic midnight look.
func set_world(def: Dictionary) -> void:
	ground_color = Util.color_arr(def.get("ground_color"), ground_color)
	detail_color = Util.color_arr(def.get("ground_detail"), ground_color)
	grid_color = Util.color_arr(def.get("grid_color"), grid_color)
	_decorated = detail_color != ground_color
	_tuft_color = ground_color.darkened(0.35)
	queue_redraw()

func _draw() -> void:
	var world_rect: Rect2 = get_viewport().get_canvas_transform().affine_inverse() * get_viewport_rect()
	## Ground first, then decoration, grid lines on top.
	draw_rect(world_rect.grow(GROUND_MARGIN), ground_color)
	if _decorated:
		_draw_detail(world_rect)
	var x := floorf(world_rect.position.x / GRID_STEP) * GRID_STEP
	while x <= world_rect.end.x:
		draw_line(Vector2(x, world_rect.position.y), Vector2(x, world_rect.end.y), grid_color, 2.0)
		x += GRID_STEP
	var y := floorf(world_rect.position.y / GRID_STEP) * GRID_STEP
	while y <= world_rect.end.y:
		draw_line(Vector2(world_rect.position.x, y), Vector2(world_rect.end.x, y), grid_color, 2.0)
		y += GRID_STEP

## Per-cell hash-seeded variation over the visible cells only (~100 cells at
## 720p): one soft off-center accent patch in ~60% of cells and a few grass
## tufts. Seeding the shared RNG from the cell coords keeps every value stable
## per cell — no shimmer while the camera moves, identical on all peers.
func _draw_detail(world_rect: Rect2) -> void:
	var x0 := int(floorf(world_rect.position.x / GRID_STEP))
	var x1 := int(floorf(world_rect.end.x / GRID_STEP))
	var y0 := int(floorf(world_rect.position.y / GRID_STEP))
	var y1 := int(floorf(world_rect.end.y / GRID_STEP))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			_rng.seed = hash(Vector2i(cx, cy))
			var base := Vector2(cx, cy) * GRID_STEP
			if _rng.randf() < PATCH_CHANCE:
				var patch := ground_color.lerp(detail_color, _rng.randf_range(0.6, 1.0))
				patch.a = _rng.randf_range(0.4, 0.75)
				var center := base + Vector2(_rng.randf_range(20.0, GRID_STEP - 20.0), _rng.randf_range(20.0, GRID_STEP - 20.0))
				draw_circle(center, _rng.randf_range(26.0, 58.0), patch)
			## Occasional darker patch: depth so the meadow isn't only
			## lighter-dotted.
			if _rng.randf() < 0.3:
				var shade := ground_color.darkened(_rng.randf_range(0.08, 0.16))
				shade.a = _rng.randf_range(0.35, 0.6)
				var scenter := base + Vector2(_rng.randf_range(16.0, GRID_STEP - 16.0), _rng.randf_range(16.0, GRID_STEP - 16.0))
				draw_circle(scenter, _rng.randf_range(18.0, 40.0), shade)
			for i in TUFTS_PER_CELL:
				_draw_tuft(base + Vector2(_rng.randf() * GRID_STEP, _rng.randf() * GRID_STEP))

## One grass tuft: three short blades fanning up from a point (pure vector —
## cheaper and endless-map-friendlier than sprite scatter).
func _draw_tuft(p: Vector2) -> void:
	var h := _rng.randf_range(7.0, 13.0)
	var sway := _rng.randf_range(-2.5, 2.5)
	var col := _tuft_color
	col.a = _rng.randf_range(0.5, 0.85)
	draw_multiline(PackedVector2Array([
		p, p + Vector2(sway, -h),
		p, p + Vector2(sway - 4.0, -h * 0.65),
		p, p + Vector2(sway + 4.0, -h * 0.65),
	]), col, 1.5)
