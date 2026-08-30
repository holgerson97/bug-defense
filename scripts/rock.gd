extends StaticBody2D
## Indestructible organic rock mass: one jagged polygon per formation.
## Silhouettes are procedural blobs grown on a coarse 96px cell lattice —
## seeded accretion with a compactness bias plus an optional carved notch —
## traced into a closed outline. Collision uses the raw trace — straight,
## axis-aligned, every corner on a 32px multiple — so walls snapped to the
## build lattice butt against rock with zero gap. Visuals subdivide + jitter
## INWARD only, staying organic without ever crossing the collider.
## Layer 16, mask 0 — blocks placement, enemies, player and bullets like ore,
## but has no health, no mining, and stays out of the "deposits" group.

const CELL := 96.0
const SUB_LEN := 40.0
const JITTER := 10.0

## Accretion weighting: frontier candidates score pow(GROW_BIAS, filled
## neighbors), so pockets fill before tips extend — no long thin strands.
const GROW_BIAS := 2.6
## Chance to chew a notch into blobs big enough to take one (concavity).
const NOTCH_CHANCE := 0.65

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Palette lifted from assets/sprites/rock.svg (no longer used as a texture).
const FILL := Color("6b6f78")
const EDGE := Color("3a3d44")
const FACET_LIGHT := Color("8a8f99")
const FACET_MID := Color("5d616a")
const FACET_DARK := Color("4c4f56")

var outline := PackedVector2Array()
## Raw traced silhouette: straight segments, corners on 32px multiples.
var collider := PackedVector2Array()
## 32px lattice cell offsets covered by the silhouette (each blob cell is an
## exact 3x3 block); _register_nav shifts them to world cells.
var nav_local: Array[Vector2i] = []
## Local-space bbox of the collider; spawner reads it for placement checks.
var bounds := Rect2()

## Spawner calls this before add_child, then checks `bounds` before placing.
## `cell_budget` is the number of 96px lattice cells the blob grows toward
## (the size classes under balance "terrain"). Every draw comes from the
## GLOBAL RNG, so the caller's seeded stream (main._seed_chunk / the starter
## seed) makes each blob deterministic per run seed while every rock stays
## unique. The blob is healed to a single boundary loop (holes filled,
## diagonal-only contacts bridged — the trace's invariant), and all corners
## stay on the 96px (a multiple of 32px) lattice, so the wall-butting
## invariant holds at any size. A bbox span cap of ~sqrt(budget)+2 cells
## keeps blobs compact enough for the spawner's chunk-fit check.
func generate(cell_budget := 10) -> void:
	var cells := _grow_blob(maxi(2, cell_budget))
	_carve_notch(cells)
	collider = _trace(cells, CELL)
	outline = _jitter(_subdivide(collider))
	nav_local.clear()
	for c in cells:
		for dy in 3:
			for dx in 3:
				nav_local.append(Vector2i(c) * 3 + Vector2i(dx, dy))
	bounds = Rect2(collider[0], Vector2.ZERO)
	for p in collider:
		bounds = bounds.expand(p)

## Seeded accretion on the cell lattice: start at the origin and repeatedly
## claim a frontier cell, weighted toward candidates already hugged by filled
## neighbors. Candidates that would stretch the bbox past the span cap score
## zero (kept in place so weight indices stay aligned with the frontier).
func _grow_blob(budget: int) -> Dictionary:
	var span := int(ceil(sqrt(float(budget)))) + 2
	var cells := {Vector2i.ZERO: true}
	var lo := Vector2i.ZERO
	var hi := Vector2i.ZERO
	var frontier: Array[Vector2i] = DIRS.duplicate()
	while cells.size() < budget:
		var weights := PackedFloat64Array()
		var total := 0.0
		for c in frontier:
			var w := pow(GROW_BIAS, float(_filled_neighbors(cells, c)))
			if maxi(hi.x, c.x) - mini(lo.x, c.x) >= span or maxi(hi.y, c.y) - mini(lo.y, c.y) >= span:
				w = 0.0
			weights.append(w)
			total += w
		if total <= 0.0:
			break
		var roll := randf() * total
		var idx := -1
		for i in frontier.size():
			if weights[i] <= 0.0:
				continue
			idx = i
			roll -= weights[i]
			if roll <= 0.0:
				break
		var pick := frontier[idx]
		frontier.remove_at(idx)
		cells[pick] = true
		lo = Vector2i(mini(lo.x, pick.x), mini(lo.y, pick.y))
		hi = Vector2i(maxi(hi.x, pick.x), maxi(hi.y, pick.y))
		for d in DIRS:
			var nb := pick + d
			if not cells.has(nb) and not frontier.has(nb):
				frontier.append(nb)
	_heal(cells)
	return cells

func _filled_neighbors(cells: Dictionary, c: Vector2i) -> int:
	var n := 0
	for d in DIRS:
		if cells.has(c + d):
			n += 1
	return n

## Post-growth repair until stable: bridge diagonal-only contacts and fill
## enclosed holes — either would split the boundary into multiple loops and
## break the single-walk trace. Each fix only ADDS cells, so it terminates.
func _heal(cells: Dictionary) -> void:
	for i in 4:
		var changed := _bridge_diagonals(cells)
		changed = _fill_holes(cells) or changed
		if not changed:
			return

func _bridge_diagonals(cells: Dictionary) -> bool:
	var changed := false
	var again := true
	while again:
		again = false
		for c in cells.keys():
			var v: Vector2i = c
			for d in [Vector2i(1, 1), Vector2i(1, -1)]:
				if cells.has(v + d) and not cells.has(v + Vector2i(d.x, 0)) and not cells.has(v + Vector2i(0, d.y)):
					cells[v + Vector2i(d.x, 0)] = true
					again = true
					changed = true
	return changed

## Flood the OUTSIDE of the padded bbox over empty cells; whatever empty cell
## the flood can't reach is an enclosed hole and gets filled.
func _fill_holes(cells: Dictionary) -> bool:
	var lo: Vector2i = cells.keys()[0]
	var hi := lo
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	lo -= Vector2i.ONE
	hi += Vector2i.ONE
	var outside := {lo: true}
	var stack: Array[Vector2i] = [lo]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in DIRS:
			var nb := c + d
			if nb.x < lo.x or nb.y < lo.y or nb.x > hi.x or nb.y > hi.y:
				continue
			if cells.has(nb) or outside.has(nb):
				continue
			outside[nb] = true
			stack.append(nb)
	var changed := false
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var c := Vector2i(x, y)
			if not cells.has(c) and not outside.has(c):
				cells[c] = true
				changed = true
	return changed

## Concavity variety: from a random boundary face, chew a straight line of
## cells inward. Every removal is validated (blob must stay one 4-connected
## mass with no diagonal-only contacts); an invalid bite reverts and stops.
func _carve_notch(cells: Dictionary) -> void:
	if cells.size() < 8 or randf() >= NOTCH_CHANCE:
		return
	var dir: Vector2i = DIRS[randi() % DIRS.size()]
	var faces: Array[Vector2i] = []
	for c in cells:
		var v: Vector2i = c
		if not cells.has(v - dir):
			faces.append(v)
	if faces.is_empty():
		return
	var cur: Vector2i = faces[randi() % faces.size()]
	@warning_ignore("integer_division")
	var depth := maxi(1, cells.size() / 6)
	for i in depth:
		if not cells.has(cur):
			return
		cells.erase(cur)
		if not _valid_cells(cells):
			cells[cur] = true
			return
		cur += dir

## Single 4-connected mass with no diagonal-only contact — the invariant the
## one-loop boundary trace needs.
func _valid_cells(cells: Dictionary) -> bool:
	if cells.is_empty():
		return false
	var start: Vector2i = cells.keys()[0]
	var seen := {start: true}
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in DIRS:
			var nb := c + d
			if cells.has(nb) and not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	if seen.size() != cells.size():
		return false
	for c in cells:
		var v: Vector2i = c
		for d in [Vector2i(1, 1), Vector2i(1, -1)]:
			if cells.has(v + d) and not cells.has(v + Vector2i(d.x, 0)) and not cells.has(v + Vector2i(0, d.y)):
				return false
	return true

func _ready() -> void:
	if outline.is_empty():
		generate()
	## Per-rock grey variety: each formation leans a shade lighter/darker and
	## faintly warmer/cooler, so a field of rocks reads as varied stone, not
	## copies. Deterministic — drawn from the same seeded stream as the shape.
	var shade := randf_range(0.82, 1.14)
	var warm := randf_range(-0.03, 0.03)
	self_modulate = Color(shade + warm, shade, shade - warm, 1.0)
	var poly := Polygon2D.new()
	poly.polygon = outline
	poly.color = FILL
	add_child(poly)
	_add_facets()
	_add_detail()
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

## Anchors snap to the 32px lattice, so the blob's 3x3 lattice blocks map
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
## so dictionary keys match exactly. Each corner starts at most one edge
## (guaranteed by _heal: no holes, no diagonal-only contacts).
## `cell_px` is the world size of one blob cell (CELL).
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

## Surface detail: speckle chips and small shade blotches scattered inside
## the silhouette (deterministic; counts scale with rock size).
func _add_detail() -> void:
	var rect := bounds
	var count := clampi(int(rect.get_area() / 9000.0), 3, 14)
	for i in count:
		var p := Vector2(randf_range(rect.position.x + 14.0, rect.end.x - 14.0),
			randf_range(rect.position.y + 14.0, rect.end.y - 14.0))
		if not Geometry2D.is_point_in_polygon(p, outline):
			continue
		if i % 2 == 0:
			## Shade blotch: irregular dark patch.
			var blotch := Polygon2D.new()
			var pts := PackedVector2Array()
			var r := randf_range(7.0, 16.0)
			for k in 6:
				pts.append(p + Vector2.from_angle(TAU * k / 6.0) * r * randf_range(0.6, 1.3))
			blotch.polygon = pts
			blotch.color = FACET_DARK
			blotch.color.a = randf_range(0.25, 0.45)
			add_child(blotch)
		else:
			## Chip fleck: tiny light triangle.
			var fleck := Polygon2D.new()
			var fr := randf_range(2.5, 5.0)
			fleck.polygon = PackedVector2Array([
				p + Vector2(-fr, fr * 0.6), p + Vector2(fr, fr * 0.3), p + Vector2(0, -fr)])
			fleck.color = FACET_LIGHT
			fleck.color.a = randf_range(0.5, 0.8)
			add_child(fleck)

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
