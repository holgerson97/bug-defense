extends StaticBody2D
## Indestructible organic rock mass: one jagged polygon per formation.
## Silhouettes come from coarse 96px cell templates (block/L/U/S) traced into
## a closed outline. Collision uses the raw trace — straight, axis-aligned,
## every corner on a 32px multiple — so walls snapped to the build lattice
## butt against rock with zero gap. Visuals subdivide + jitter INWARD only,
## staying organic without ever crossing the collider.
## Layer 16, mask 0 — blocks placement, enemies, player and bullets like ore,
## but has no health, no mining, and stays out of the "deposits" group.

const CELL := 96.0
const SUB_LEN := 40.0
const JITTER := 10.0

## Palette lifted from assets/sprites/rock.svg (no longer used as a texture).
const FILL := Color("6b6f78")
const EDGE := Color("3a3d44")
const FACET_LIGHT := Color("8a8f99")
const FACET_MID := Color("5d616a")
const FACET_DARK := Color("4c4f56")

## Coarse silhouettes as cell offsets; spun + mirrored per instance. None of
## these touch diagonally-only, so the boundary trace is a single loop.
const SHAPES := [
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], # 2x2 block
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)], # 3x2 block
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)], # 4x3 block
	[Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3)], # L
	[Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 1), Vector2i(3, 0)], # U
	[Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)], # S
]
## U template index; its opening faces up at spin 0, then right/down/left.
const SHAPE_U := 4

## Cell-count bbox of a template (before spin/mirror); spawners use it to
## check which shapes fit a chunk at a given cell_scale.
static func shape_cell_dims(idx: int) -> Vector2i:
	var mn := Vector2i(SHAPES[idx][0])
	var mx := mn
	for c in SHAPES[idx]:
		mn = Vector2i(mini(mn.x, c.x), mini(mn.y, c.y))
		mx = Vector2i(maxi(mx.x, c.x), maxi(mx.y, c.y))
	return mx - mn + Vector2i.ONE

var outline := PackedVector2Array()
## Raw traced silhouette: straight segments, corners on 32px multiples.
var collider := PackedVector2Array()
## 32px lattice cell offsets covered by the silhouette (each template cell is
## an exact (3*cell_scale)^2 block); _register_nav shifts them to world cells.
var nav_local: Array[Vector2i] = []
## Local-space bbox of the collider; spawner reads it for placement checks.
var bounds := Rect2()

## Spawner calls this before add_child, then checks `bounds` before placing.
## `shape_index`/`spin` >= 0 force a template and orientation (starter U
## pocket); a forced spin skips the mirror so the opening maps predictably.
## `cell_scale` (int, 1 = 96px, 2 = 192px per template cell) grows the whole
## silhouette; integer multiples keep every corner on a 32px multiple, so the
## lattice invariant holds at any size. Visual subdivide/jitter is unchanged.
func generate(shape_index := -1, spin := -1, cell_scale := 1) -> void:
	cell_scale = maxi(1, cell_scale)
	var shape: Array = SHAPES[shape_index if shape_index >= 0 else randi() % SHAPES.size()]
	var mirror := spin < 0 and randf() < 0.5
	if spin < 0:
		spin = randi() % 4
	var cells := {}
	for c in shape:
		var v: Vector2i = c
		if mirror:
			v = Vector2i(-v.x, v.y)
		for r in spin:
			v = Vector2i(-v.y, v.x)
		cells[v] = true
	collider = _trace(cells, CELL * cell_scale)
	outline = _jitter(_subdivide(collider))
	nav_local.clear()
	var lat := 3 * cell_scale
	for c in cells:
		for dy in lat:
			for dx in lat:
				nav_local.append(Vector2i(c) * lat + Vector2i(dx, dy))
	bounds = Rect2(collider[0], Vector2.ZERO)
	for p in collider:
		bounds = bounds.expand(p)

func _ready() -> void:
	if outline.is_empty():
		generate()
	var poly := Polygon2D.new()
	poly.polygon = outline
	poly.color = FILL
	add_child(poly)
	_add_facets()
	var edge := Line2D.new()
	edge.points = outline
	edge.closed = true
	edge.width = 3.0
	edge.default_color = EDGE
	edge.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(edge)
	var col := CollisionPolygon2D.new()
	col.polygon = collider
	add_child(col)
	_register_nav()

## Anchors snap to the 32px lattice, so the template's 3x3 lattice blocks map
## straight onto NavGrid cells — arithmetic, no polygon sampling. One-time per
## formation; freed on tree exit so map regens stay clean.
func _register_nav() -> void:
	var base := NavGrid.cell_of(global_position)
	var cells: Array[Vector2i] = []
	var lo := base + nav_local[0]
	var hi := lo
	for v in nav_local:
		var c := base + v
		cells.append(c)
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	NavGrid.occupy_cells(cells, NavGrid.KIND_ROCK)
	## Formation bounds let the A* window grow to contain a route around us.
	var key := get_instance_id()
	NavGrid.register_rock_rect(key, lo, hi)
	tree_exited.connect(func():
		NavGrid.release_cells(cells)
		NavGrid.release_rock_rect(key))

## Walk the cell-set boundary clockwise; corners tracked in cell-corner space
## so dictionary keys match exactly. Each corner starts at most one edge.
## `cell_px` is the world size of one template cell (CELL * cell_scale).
func _trace(cells: Dictionary, cell_px: float) -> PackedVector2Array:
	var next := {}
	for c in cells:
		var v: Vector2i = c
		if not cells.has(v + Vector2i.UP):
			next[v] = v + Vector2i(1, 0)
		if not cells.has(v + Vector2i.RIGHT):
			next[v + Vector2i(1, 0)] = v + Vector2i(1, 1)
		if not cells.has(v + Vector2i.DOWN):
			next[v + Vector2i(1, 1)] = v + Vector2i(0, 1)
		if not cells.has(v + Vector2i.LEFT):
			next[v + Vector2i(0, 1)] = v
	var pts := PackedVector2Array()
	var start: Vector2i = next.keys()[0]
	var cur := start
	while true:
		pts.append(Vector2(cur) * cell_px)
		cur = next[cur]
		if cur == start:
			break
	return pts

## Split long segments so jitter reads as jagged rock, not skewed rectangles.
func _subdivide(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var n := maxi(1, int(round(a.distance_to(b) / SUB_LEN)))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	return out

## Inward-only displacement (0..JITTER along the local inward normal): keeps
## the organic look while the drawn rock never crosses the straight collider.
func _jitter(pts: PackedVector2Array) -> PackedVector2Array:
	var n := pts.size()
	var out := PackedVector2Array()
	for i in n:
		var dir: Vector2 = (pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized()
		out.append(pts[i] + Vector2(-dir.y, dir.x) * randf_range(0.0, JITTER))
	return out

## Offset every vertex inward along the local normal. CW winding + y-down means
## inward is the +90° rotation of travel direction. `reach` widens the tangent
## window to smooth over jitter (3+ = soft facet bands).
func _inset(pts: PackedVector2Array, amount: float, reach: int = 1) -> PackedVector2Array:
	var n := pts.size()
	var out := PackedVector2Array()
	for i in n:
		var dir: Vector2 = (pts[(i + reach) % n] - pts[(i - reach + n) % n]).normalized()
		out.append(pts[i] + Vector2(-dir.y, dir.x) * amount)
	return out

## Faceted look from the old SVG: light band along the top edge, dark band
## along the bottom, one random mid band, plus a couple of crack strokes.
func _add_facets() -> void:
	var n := outline.size()
	var top := 0
	var bottom := 0
	for i in n:
		if outline[i].y < outline[top].y:
			top = i
		if outline[i].y > outline[bottom].y:
			bottom = i
	_facet(top, FACET_LIGHT)
	_facet(bottom, FACET_DARK)
	_facet(randi() % n, FACET_MID)
	var inner := _inset(outline, 34.0, 3)
	for i in 2:
		var idx := randi() % n
		var crack := Line2D.new()
		crack.points = PackedVector2Array([
			outline[idx].lerp(inner[idx], 0.25),
			inner[(idx + 2) % n],
		])
		crack.width = 2.0
		crack.default_color = EDGE
		crack.default_color.a = 0.6
		add_child(crack)

## Band between an outline arc and its normal-inset copy — follows concave
## shapes, so U/L interiors never get stray patches.
func _facet(center: int, color: Color) -> void:
	var n := outline.size()
	var span := maxi(4, n / 5)
	var inner := _inset(outline, randf_range(22.0, 42.0), 3)
	var poly := PackedVector2Array()
	for k in range(-span / 2, span / 2 + 1):
		poly.append(outline[(center + k + n) % n])
	for k in range(span / 2, -span / 2 - 1, -1):
		poly.append(inner[(center + k + n) % n])
	var facet := Polygon2D.new()
	facet.polygon = poly
	facet.color = color
	add_child(facet)
