extends Node
## Autoload: power distribution grid. Sources (solar, battery, command center,
## intake station) seed a BFS; a pole is connected when within LINK_RANGE of a
## source or another connected pole. Consumers ask covered(): within
## COVER_RANGE of a connected pole or SOURCE_COVER of any source. Rebuilds
## lazily — poles/sources dirty the grid on enter/exit, recompute at most once
## per physics frame (or on first query that frame).

signal grid_changed

var LINK_RANGE: float = Balance.num("buildings/power_grid/link_range", 250.0)
## Mirrors GameState.BUILDINGS["power_pole"]["range"] (the ghost's circle).
var COVER_RANGE: float = Balance.num("buildings/power_pole/range", 160.0)
var SOURCE_COVER: float = Balance.num("buildings/power_grid/source_cover", 120.0)
## The player's suit carries a small reactor: towers near the player run
## without pole coverage. Mobile, so never part of the cached BFS.
var PLAYER_COVER: float = Balance.num("player/reactor/cover_range", 150.0)

var _dirty := true
var _links: Dictionary = {}
var _pole_positions := PackedVector2Array()
var _source_positions := PackedVector2Array()

## Sources and poles register on ready; joining or dying dirties the grid.
func register_source(node: Node) -> void:
	node.add_to_group("power_sources")
	node.tree_exited.connect(mark_dirty)
	mark_dirty()

func register_pole(node: Node) -> void:
	node.add_to_group("power_poles")
	node.tree_exited.connect(mark_dirty)
	mark_dirty()

func mark_dirty() -> void:
	_dirty = true

func _physics_process(_delta: float) -> void:
	if _dirty:
		_rebuild()

## True when pos can draw grid power: near a connected pole, any source,
## or a player (walking reactor aura).
func covered(pos: Vector2) -> bool:
	if _dirty:
		_rebuild()
	for p in _source_positions:
		if p.distance_squared_to(pos) <= SOURCE_COVER * SOURCE_COVER:
			return true
	for p in _pole_positions:
		if p.distance_squared_to(pos) <= COVER_RANGE * COVER_RANGE:
			return true
	## Reactor Aura research widens the walking-reactor radius.
	var cover := PLAYER_COVER * GameState.player_cover_mult()
	for player in get_tree().get_nodes_in_group("player"):
		if player.global_position.distance_squared_to(pos) <= cover * cover:
			return true
	return false

func is_pole_connected(pole: Node) -> bool:
	if _dirty:
		_rebuild()
	return _links.has(pole)

## The BFS tree parent (source or pole) this pole cables to; null if orphaned.
func link_parent(pole: Node):
	return _links.get(pole)

## BFS from all sources: each frontier node adopts every unlinked pole within
## LINK_RANGE. Cached positions make covered() a flat distance scan.
func _rebuild() -> void:
	_dirty = false
	_links.clear()
	_pole_positions = PackedVector2Array()
	_source_positions = PackedVector2Array()
	var tree := get_tree()
	if tree == null:
		return
	var queue: Array = tree.get_nodes_in_group("power_sources")
	for source in queue:
		_source_positions.append(source.global_position)
	var pending: Array = tree.get_nodes_in_group("power_poles")
	while not queue.is_empty():
		var node = queue.pop_front()
		var rest: Array = []
		for pole in pending:
			if pole.global_position.distance_squared_to(node.global_position) <= LINK_RANGE * LINK_RANGE:
				_links[pole] = node
				_pole_positions.append(pole.global_position)
				queue.append(pole)
			else:
				rest.append(pole)
		pending = rest
	grid_changed.emit()
