extends "res://scripts/building.gd"
## Wall piece. Beyond the shared building behavior it keeps a peer-local
## registry of wall positions and, once the Wall Lanterns upgrade
## ("b/wall/lanterns") is owned, auto-mounts free lamp posts:
##   - on every CORNER (a wall whose neighbor set is not a straight line:
##     perpendicular pair, T- or X-junction), and
##   - on every 5th piece of each maximal straight run, counted from the
##     run's low-coordinate end.
## Lamp assignment derives purely from the wall layout (positions replicate
## exactly via the building spawner) plus the research mirror, with zero
## randomness — every peer computes the identical lamp set. Placement or
## destruction recomputes ONLY the touched connected component (4-neighbor
## adjacency at the 48px wall pitch), never the whole map.

const LIGHT_SOURCE := preload("res://scripts/light_source.gd")
const LANTERN_ID := "b/wall/lanterns"
## Wall pitch: BUILDING_FOOTPRINT["wall"] in build_controller (flush walls
## sit exactly this far apart; positions are exact multiples of 8, so the
## rounded integer keys below are float-safe on every peer).
const STEP := 48
const RUN_EVERY := 5

## Peer-local registry: Vector2i(round(global_position)) -> wall node.
## Static (class-wide); every wall unregisters in _exit_tree, so scene
## teardown drains it naturally.
static var _registry: Dictionary = {}
## Cached "lanterns owned" so a purchase flips lamps exactly once (the first
## wall whose upgrades_changed handler sees the change recomputes for all).
static var _lanterns_owned := false

var _cell := Vector2i.ZERO
var _lamp: Node2D = null

func _ready() -> void:
	super._ready()
	_cell = Vector2i(global_position.round())
	_registry[_cell] = self
	_lanterns_owned = _lanterns_available()
	GameState.upgrades_changed.connect(_on_upgrades_changed)
	## Deferred: a drag row registers several walls this frame — recompute
	## once they are all in the registry.
	if _lanterns_owned:
		call_deferred("_recompute_component")

func _exit_tree() -> void:
	if _registry.get(_cell) == self:
		_registry.erase(_cell)
	if _lamp != null:
		_lamp = null
	## Removal can split a component: recompute from every ex-neighbor (the
	## deferred call is dropped safely if that neighbor got freed too, e.g.
	## on scene teardown).
	if _lanterns_available():
		for nkey in _neighbor_keys(_cell):
			var wall = _registry.get(nkey)
			if wall != null and is_instance_valid(wall):
				wall.call_deferred("_recompute_component")

static func _lanterns_available() -> bool:
	return GameState.upgrade_level(LANTERN_ID) > 0

## Purchase watcher: the first wall to observe the flip updates every
## component once; the rest see no change and no-op.
func _on_upgrades_changed() -> void:
	var owned := _lanterns_available()
	if owned == _lanterns_owned:
		return
	_lanterns_owned = owned
	var seen := {}
	for cell in _registry.keys():
		if seen.has(cell):
			continue
		for c in _component(cell):
			seen[c] = true
		var wall = _registry.get(cell)
		if wall != null and is_instance_valid(wall):
			wall._recompute_component()

static func _neighbor_keys(cell: Vector2i) -> Array:
	return [cell + Vector2i(STEP, 0), cell - Vector2i(STEP, 0),
		cell + Vector2i(0, STEP), cell - Vector2i(0, STEP)]

## Connected component (4-neighborhood at the wall pitch) containing `seed`.
static func _component(seed_cell: Vector2i) -> Array:
	if not _registry.has(seed_cell):
		return []
	var seen := {seed_cell: true}
	var queue := [seed_cell]
	var out := []
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		out.append(cell)
		for nkey in _neighbor_keys(cell):
			if _registry.has(nkey) and not seen.has(nkey):
				seen[nkey] = true
				queue.append(nkey)
	return out

## Deterministic lamp set for one component: corners + every RUN_EVERY-th
## piece of each maximal straight run (counted from the min-x / min-y end).
static func _lamp_cells(cells: Array) -> Dictionary:
	var set := {}
	for c in cells:
		set[c] = true
	var lamps := {}
	var right := Vector2i(STEP, 0)
	var down := Vector2i(0, STEP)
	for c in cells:
		var h: bool = set.has(c + right) or set.has(c - right)
		var v: bool = set.has(c + down) or set.has(c - down)
		# Corner/junction: neighbors in both axes = not a straight line.
		if h and v:
			lamps[c] = true
	for c in cells:
		# Horizontal run start: no wall to the left, at least one to the right.
		if set.has(c + right) and not set.has(c - right):
			var i := 1
			var cur: Vector2i = c
			while set.has(cur):
				if i % RUN_EVERY == 0:
					lamps[cur] = true
				cur += right
				i += 1
		# Vertical run start (top end).
		if set.has(c + down) and not set.has(c - down):
			var i := 1
			var cur: Vector2i = c
			while set.has(cur):
				if i % RUN_EVERY == 0:
					lamps[cur] = true
				cur += down
				i += 1
	return lamps

## Recompute lamp assignment for THIS wall's connected component.
func _recompute_component() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var cells := _component(_cell)
	var lamps := _lamp_cells(cells) if _lanterns_available() else {}
	for cell in cells:
		var wall = _registry.get(cell)
		if wall != null and is_instance_valid(wall) and not wall.is_queued_for_deletion():
			wall.set_lamp(lamps.has(cell))

## Mount/remove the free lamp: a small code-drawn pole (matching the light
## pole palette) plus a LightSource pool that fades with day/night on its own.
func set_lamp(on: bool) -> void:
	if on == (_lamp != null):
		return
	if not on:
		_lamp.queue_free()
		_lamp = null
		return
	_lamp = Node2D.new()
	_lamp.name = "WallLamp"
	_lamp.z_index = 5
	var post := Polygon2D.new()
	post.polygon = PackedVector2Array([
		Vector2(-1.5, 4), Vector2(1.5, 4), Vector2(1.0, -13), Vector2(-1.0, -13)])
	post.color = Color(0.22, 0.25, 0.32)
	_lamp.add_child(post)
	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-4, 5), Vector2(4, 5), Vector2(3, 2), Vector2(-3, 2)])
	base.color = Color(0.28, 0.31, 0.38)
	_lamp.add_child(base)
	var head := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 10:
		pts.append(Vector2(0, -15) + Vector2.from_angle(TAU * i / 10.0) * 3.5)
	head.polygon = pts
	head.color = Color(1.0, 0.87, 0.55)
	_lamp.add_child(head)
	var light = LIGHT_SOURCE.new()
	light.radius = Balance.num("building_upgrades/wall/lanterns/radius", 170.0)
	light.position = Vector2(0, -15)
	_lamp.add_child(light)
	## Slightly above wall center so the pole reads as standing on the piece.
	_lamp.position = Vector2(0, -4)
	add_child(_lamp)
