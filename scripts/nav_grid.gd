extends Node
## NavGrid autoload: 32px occupancy lattice + windowed A* for ground enemies.
## Buildings register as gnawable cells (walkable at a heavy cost so bugs chew
## through when walled in), rocks as impassable. Occupancy updates are
## event-driven (register on _ready, release on tree exit); path searches are
## on-demand and rationed by a global per-physics-frame budget so 350 alive
## enemies can never stampede the solver.

const CELL := 32.0
const KIND_BUILDING := 1
const KIND_ROCK := 2
const BUILDING_COST := 8.0     ## step multiplier through gnawable cells
const FRAME_BUDGET := 8        ## A* searches allowed per physics frame
const MAX_WINDOW := 64         ## hard search window side cap, in cells
const GOAL_SPAN := 26          ## far goals clamp the window anchor to this
const WINDOW_MARGIN := 6       ## cells padded around the from/anchor bbox
const MAX_POPS := 1200         ## hard cap on expanded nodes per search
const MIN_GAIN := 3.0          ## best-effort path must close >= this many cells

## 4 orthogonal steps first, 4 diagonals last (order gates corner cutting).
const STEPS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

## Vector2i cell -> [kind, count]. Refcounted: flush 48px walls share
## boundary cells, so one occupant dying must not clear a still-shared cell.
var _cells := {}
## Formation id -> [lo, hi] cell bounds of each rock mass. The A* window grows
## over every formation it clips, so a route AROUND a large rock always fits.
var _rock_rects := {}
var _budget: int = FRAME_BUDGET

func _physics_process(_delta: float) -> void:
	_budget = FRAME_BUDGET

func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))

func center_of(c: Vector2i) -> Vector2:
	return Vector2(c) * CELL + Vector2(CELL * 0.5, CELL * 0.5)

func occupy_cells(cells: Array[Vector2i], kind: int) -> void:
	for c in cells:
		var entry = _cells.get(c)
		if entry == null:
			_cells[c] = [kind, 1]
		else:
			## Highest severity wins when kinds mix (ROCK over BUILDING).
			entry[0] = maxi(entry[0], kind)
			entry[1] += 1

func release_cells(cells: Array[Vector2i]) -> void:
	for c in cells:
		var entry = _cells.get(c)
		if entry == null:
			continue
		entry[1] -= 1
		if entry[1] <= 0:
			_cells.erase(c)

func register_rock_rect(key: int, lo: Vector2i, hi: Vector2i) -> void:
	_rock_rects[key] = [lo, hi]

func release_rock_rect(key: int) -> void:
	_rock_rects.erase(key)

## Occupancy kind at a cell; 0 when free.
func _kind_at(c: Vector2i) -> int:
	var entry = _cells.get(c)
	return 0 if entry == null else entry[0]

## Cells whose center lies inside a world-space rect (building footprints).
func cells_in_rect(rect: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo := cell_of(rect.position)
	var hi := cell_of(rect.end)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var c := Vector2i(x, y)
			if rect.has_point(center_of(c)):
				out.append(c)
	return out

## Cells whose center lies inside a polygon at world offset (rock outlines).
func cells_in_polygon(poly: PackedVector2Array, offset: Vector2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var bbox := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		bbox = bbox.expand(p)
	var lo := cell_of(bbox.position + offset)
	var hi := cell_of(bbox.end + offset)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var c := Vector2i(x, y)
			if Geometry2D.is_point_in_polygon(center_of(c) - offset, poly):
				out.append(c)
	return out

## Budgeted path request. Returns null when this frame's budget is spent
## (caller retries next frame), else a PackedVector2Array of cell-center
## waypoints — empty when the goal is out of window or walled off by rock.
func request_path(from: Vector2, to: Vector2) -> Variant:
	if _budget <= 0:
		return null
	_budget -= 1
	return _find_path(cell_of(from), cell_of(to))

## Windowed 8-directional A* over the occupancy map. Rock cells are hard
## walls; building cells cost BUILDING_COST x (path around when reasonable,
## through when sealed in). Diagonals never cut past an occupied side cell,
## so every waypoint pair stays physically walkable.
func _find_path(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	if _kind_at(to) == KIND_ROCK:
		return PackedVector2Array()
	## Far goals: the window anchors at a clamped point toward the goal and the
	## search returns a best-effort leg (caller re-requests after walking it) —
	## v2 refused outright whenever the from/to bbox outgrew the window cap.
	var anchor := Vector2i(clampi(to.x, from.x - GOAL_SPAN, from.x + GOAL_SPAN),
			clampi(to.y, from.y - GOAL_SPAN, from.y + GOAL_SPAN))
	var lo := Vector2i(mini(from.x, anchor.x), mini(from.y, anchor.y)) - Vector2i(WINDOW_MARGIN, WINDOW_MARGIN)
	var hi := Vector2i(maxi(from.x, anchor.x), maxi(from.y, anchor.y)) + Vector2i(WINDOW_MARGIN, WINDOW_MARGIN)
	## Grow over every rock formation the window clips (+1 keeps the walkable
	## rim inside): a fixed margin cannot contain a scale-2 formation's flank.
	var grew := true
	while grew:
		grew = false
		for k in _rock_rects:
			var b: Array = _rock_rects[k]
			var blo: Vector2i = b[0] - Vector2i.ONE
			var bhi: Vector2i = b[1] + Vector2i.ONE
			if blo.x > hi.x or bhi.x < lo.x or blo.y > hi.y or bhi.y < lo.y:
				continue
			if blo.x < lo.x or blo.y < lo.y or bhi.x > hi.x or bhi.y > hi.y:
				lo = Vector2i(mini(lo.x, blo.x), mini(lo.y, blo.y))
				hi = Vector2i(maxi(hi.x, bhi.x), maxi(hi.y, bhi.y))
				grew = true
	## Hard cap; trim keeps `from` inside (goal side may fall to best-effort).
	if hi.x - lo.x >= MAX_WINDOW:
		lo.x = maxi(lo.x, from.x - MAX_WINDOW + 1)
		hi.x = mini(hi.x, lo.x + MAX_WINDOW - 1)
	if hi.y - lo.y >= MAX_WINDOW:
		lo.y = maxi(lo.y, from.y - MAX_WINDOW + 1)
		hi.y = mini(hi.y, lo.y + MAX_WINDOW - 1)
	var open: Array[Vector2i] = [from]
	var g := {from: 0.0}
	var f := {from: _octile(from, to)}
	var came := {}
	var closed := {}
	var pops := 0
	var best := from
	var best_h := _octile(from, to)
	while not open.is_empty() and pops < MAX_POPS:
		pops += 1
		## Linear min-f pop; windows are small enough to skip a heap.
		var bi := 0
		for i in range(1, open.size()):
			if f[open[i]] < f[open[bi]]:
				bi = i
		var cur: Vector2i = open[bi]
		open.remove_at(bi)
		if cur == to:
			return _rebuild(came, cur)
		if closed.has(cur):
			continue
		closed[cur] = true
		var cur_h: float = f[cur] - g[cur]
		if cur_h < best_h:
			best_h = cur_h
			best = cur
		for k in 8:
			var step: Vector2i = STEPS[k]
			var nxt := cur + step
			if nxt.x < lo.x or nxt.y < lo.y or nxt.x > hi.x or nxt.y > hi.y:
				continue
			var kind: int = _kind_at(nxt)
			if kind == KIND_ROCK or closed.has(nxt):
				continue
			if k >= 4 and (_kind_at(Vector2i(cur.x + step.x, cur.y)) != 0 \
					or _kind_at(Vector2i(cur.x, cur.y + step.y)) != 0):
				continue
			var cost: float = 1.414 if k >= 4 else 1.0
			if kind == KIND_BUILDING:
				cost *= BUILDING_COST
			var ng: float = g[cur] + cost
			if ng < g.get(nxt, INF):
				g[nxt] = ng
				f[nxt] = ng + _octile(nxt, to)
				came[nxt] = cur
				open.append(nxt)
	## Goal unreached (out of window, walled off, or pops spent): hand back the
	## leg toward the closest-approach node when it meaningfully closes in.
	if _octile(from, to) - best_h >= MIN_GAIN:
		return _rebuild(came, best)
	return PackedVector2Array()

func _octile(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return maxi(dx, dy) + 0.414 * mini(dx, dy)

## Grid LOS for path smoothing: true when every cell the segment touches is
## free (buildings block too, so smoothing never cuts a planned gnaw leg).
## Supercover DDA — corner crossings require BOTH side cells free, which
## leaves half-cell clearance for the 16px enemy radius. Allocation-free.
func line_clear(a: Vector2, b: Vector2) -> bool:
	var c := cell_of(a)
	var end := cell_of(b)
	var d := b - a
	var step := Vector2i(1 if d.x > 0.0 else -1, 1 if d.y > 0.0 else -1)
	var tdx: float = INF if d.x == 0.0 else absf(CELL / d.x)
	var tdy: float = INF if d.y == 0.0 else absf(CELL / d.y)
	var fx := a.x / CELL - floorf(a.x / CELL)
	var fy := a.y / CELL - floorf(a.y / CELL)
	var tx: float = (1.0 - fx if d.x > 0.0 else fx) * tdx
	var ty: float = (1.0 - fy if d.y > 0.0 else fy) * tdy
	var guard := absi(end.x - c.x) + absi(end.y - c.y) + 4
	for i in guard:
		if _kind_at(c) != 0:
			return false
		if c == end:
			return true
		if absf(tx - ty) < 0.0001:
			if _kind_at(c + Vector2i(step.x, 0)) != 0 or _kind_at(c + Vector2i(0, step.y)) != 0:
				return false
			c += step
			tx += tdx
			ty += tdy
		elif tx < ty:
			c.x += step.x
			tx += tdx
		else:
			c.y += step.y
			ty += tdy
	return c == end and _kind_at(c) == 0

## Walk parents back to the start; start cell itself is excluded.
func _rebuild(came: Dictionary, cur: Vector2i) -> PackedVector2Array:
	var out := PackedVector2Array()
	while came.has(cur):
		out.append(_safe_center(cur))
		cur = came[cur]
	out.reverse()
	return out

## Corner-safe waypoint: a raw cell center sits only 16px from an adjacent
## rock face — exactly the enemy radius — so bodies clip outer corners and
## wedge on the vertex. Push the point off neighboring rock by 10px.
func _safe_center(c: Vector2i) -> Vector2:
	var push := Vector2.ZERO
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if (dx != 0 or dy != 0) and _kind_at(Vector2i(c.x + dx, c.y + dy)) == KIND_ROCK:
				push -= Vector2(dx, dy)
	if push == Vector2.ZERO:
		return center_of(c)
	return center_of(c) + push.normalized() * 10.0
