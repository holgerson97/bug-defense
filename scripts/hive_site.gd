extends Node2D
## Permanent hive nest: creep field + hive body + 2-4 satellites (spore
## mounds, bile spires). Generated with the world (main._seed_chunk end) —
## every draw runs inside the seeded per-chunk RNG stream, so all peers build
## an identical site at an identical node path ("Hives/Hive_x_y"), the same
## mechanism that keeps rocks/deposits in sync. Sites persist the whole run
## and are not part of waves.
##
## Combat is host-authoritative: the host simulates provocation, defender
## squads and spire globs; clients mirror HP/provoked/death through small
## reliable RPCs (building-HP / boss-bar pattern). Dormant hives are inert —
## only damage provokes them, never proximity.

const STRUCTURE := preload("res://scripts/hive_structure.gd")
const BILE_GLOB := preload("res://scripts/bile_glob.gd")
const HIVE_VISUAL := preload("res://scenes/hive/hive.tscn")
const SPORE_VISUAL := preload("res://scenes/hive/spore_mound.tscn")
const SPIRE_VISUAL := preload("res://scenes/hive/bile_spire.tscn")
const CREEP_TEX := preload("res://assets/sprites/hive/creep.svg")

const PROVOKED_TINT := Color(1.0, 0.72, 0.66)

## Balance knobs (fallbacks = shipped values).
var provoke_time: float = Balance.num("hive/provoke_time", 25.0)
var squad_interval: float = Balance.num("hive/squad_interval", 3.0)
var squad_grunts: int = Balance.inum("hive/squad_grunts", 6)
var brute_divisor: int = maxi(Balance.inum("hive/squad_brute_wave_divisor", 5), 1)
var spore_bonus: float = Balance.num("hive/spore_squad_bonus", 0.5)
var max_defenders: int = Balance.inum("hive/max_defenders", 40)
var spire_range: float = Balance.num("hive/spire_range", 380.0)
var spire_interval: float = Balance.num("hive/spire_interval", 2.5)
var satellite_bounty: int = Balance.inum("hive/satellite_bounty", 20)
var bounty_scrap: int = Balance.inum("hive/hive_bounty_scrap", 400)
var bounty_gold: int = Balance.inum("hive/hive_bounty_gold", 150)
var bounty_crystal: int = Balance.inum("hive/hive_bounty_crystal", 100)
var hive_points: int = Balance.inum("hive/hive_points", 500)
var creep_radius: float = Balance.num("hive/creep_radius", 350.0)
var creep_fade: float = Balance.num("hive/creep_fade", 3.0)

var _hive = null                  ## the central hive_structure
var _hive_visual: Node2D = null
var _satellites: Array = []       ## hive_structure nodes (freed entries linger)
var _creep: Node2D
var _provoke_left: float = 0.0
var _squad_accum: float = 0.0
var _spire_accum: float = 0.0
var _defenders: Array = []        ## live defender enemies (cap enforcement)
var _dead: bool = false

func _ready() -> void:
	add_to_group("hive_sites")
	_generate()

## All randf draws below run synchronously inside main._seed_chunk's seeded
## stream — identical layout on every peer, like rock.generate.
func _generate() -> void:
	## Creep field: 5-8 mats blended into one blob, below every gameplay node
	## (the whole Hives container sits right after Background in tree order).
	_creep = Node2D.new()
	add_child(_creep)
	for i in randi_range(5, 8):
		var mat := Sprite2D.new()
		mat.texture = CREEP_TEX
		mat.rotation = randf() * TAU
		var s := randf_range(0.55, 0.95)
		mat.scale = Vector2(s, s)
		var reach := maxf(creep_radius - s * 256.0, 0.0)
		mat.position = Vector2.from_angle(randf() * TAU) * randf_range(0.0, reach)
		_creep.add_child(mat)
	## Hive body at the center.
	_hive = _make_structure("hive", Vector2.ZERO,
		Balance.num("hive/hive_radius", 90.0), Balance.inum("hive/hive_hp", 2000),
		HIVE_VISUAL, -1)
	## 2-4 satellites on the creep; keep them apart and off the hive body.
	var count := randi_range(Balance.inum("hive/satellites_min", 2), Balance.inum("hive/satellites_max", 4))
	var placed: Array = []
	for i in count:
		var pos := Vector2.ZERO
		for attempt in 8:
			var p := Vector2.from_angle(randf() * TAU) * randf_range(150.0, 255.0)
			var ok := true
			for q in placed:
				if p.distance_to(q) < 95.0:
					ok = false
					break
			if ok:
				pos = p
				break
		if pos == Vector2.ZERO:
			continue
		placed.append(pos)
		if randf() < 0.5:
			_satellites.append(_make_structure("spore_mound", pos, Balance.num("hive/spore_mound_radius", 30.0),
				Balance.inum("hive/spore_mound_hp", 200), SPORE_VISUAL, _satellites.size()))
		else:
			_satellites.append(_make_structure("bile_spire", pos, Balance.num("hive/bile_spire_radius", 24.0),
				Balance.inum("hive/bile_spire_hp", 150), SPIRE_VISUAL, _satellites.size()))

func _make_structure(kind: String, pos: Vector2, radius: float, hp: int, visual: PackedScene, idx: int):
	var s = STRUCTURE.new()
	s.kind = kind
	s.body_radius = radius
	s.max_health = hp
	s.site = self
	s.site_index = idx
	s.position = pos
	var vis = visual.instantiate()
	s.add_child(vis)
	add_child(s)
	if kind == "hive":
		_hive_visual = vis
	return s

## Host simulation only (offline counts as host); clients are event-driven.
## Delta-accumulated, so pause freezes provocation and eruption for free.
func _physics_process(delta: float) -> void:
	if _dead or (Net.is_online() and not Net.is_host()):
		return
	if _provoke_left <= 0.0:
		return
	_provoke_left -= delta
	if _provoke_left <= 0.0:
		## Calm returns: remaining defenders stay, no new ones spawn.
		_set_provoked(false)
		if Net.is_online():
			_rpc_provoked.rpc(false)
		return
	_squad_accum += delta
	if _squad_accum >= squad_interval:
		_squad_accum = 0.0
		_spawn_squad()
	_spire_accum += delta
	if _spire_accum >= spire_interval:
		_spire_accum = 0.0
		_spire_attack()

## Host: any damage to the hive or a satellite lands here (hive_structure).
## Mirrors HP, provokes/refreshes the site, and resolves deaths.
func on_structure_damaged(s) -> void:
	if _dead:
		return
	if Net.is_online():
		_rpc_struct_health.rpc(s.site_index, s.health)
	_provoke()
	if s.health > 0:
		return
	if s.site_index < 0:
		_award_bounty()
		_die()
		if Net.is_online():
			_rpc_site_died.rpc()
	else:
		GameState.add_scrap_bounty(satellite_bounty)
		_destroy_satellite(s.site_index)
		if Net.is_online():
			_rpc_struct_died.rpc(s.site_index)

## Damage-only trigger (never proximity). Refreshes on further damage; a
## fresh provocation erupts almost immediately (first squad next frame).
func _provoke() -> void:
	if _dead:
		return
	var fresh := _provoke_left <= 0.0
	_provoke_left = provoke_time
	if fresh:
		_squad_accum = squad_interval
		_spire_accum = spire_interval * 0.5
		_set_provoked(true)
		if Net.is_online():
			_rpc_provoked.rpc(true)

## Defender squad from the maw: base grunts + wave-scaled brutes, the whole
## count multiplied per living spore mound. Spawned through the wave manager's
## replicated NO-COUNT path — clients see them, wave clearing ignores them.
func _spawn_squad() -> void:
	_defenders = _defenders.filter(func(d): return is_instance_valid(d))
	var wm = get_tree().get_first_node_in_group("wave_manager")
	if wm == null:
		return
	var wave: int = maxi(wm.wave, 1)
	var mult := 1.0 + spore_bonus * float(_living_count("spore_mound"))
	var queue: Array = []
	for i in int(ceil(squad_grunts * mult)):
		queue.append("grunt")
	@warning_ignore("integer_division")
	var brutes: int = wave / brute_divisor
	for i in int(ceil(brutes * mult)):
		queue.append("brute")
	for kind in queue:
		if _defenders.size() >= max_defenders:
			return
		var pos: Vector2 = global_position + Vector2.from_angle(randf() * TAU) * randf_range(110.0, 150.0)
		var ov := {}
		if kind == "brute":
			ov = {"max_health": int(ceil(Balance.num("enemies/brute/hp", 15.0) * pow(wm.hp_scale_factor, wave - 1))), "speed_delta": wave * 2.0}
		else:
			ov = {"max_health": int(ceil(Balance.num("enemies/grunt/hp", 2.0) * pow(wm.chaff_hp_scale_factor, wave - 1))), "speed_delta": wave * 2.0}
		var d = wm.spawn_hive_defender(kind, pos, ov)
		if d != null:
			_defenders.append(d)

func _living_count(kind: String) -> int:
	var n := 0
	for s in _satellites:
		if is_instance_valid(s) and not s.is_queued_for_deletion() and s.kind == kind and s.health > 0:
			n += 1
	return n

## While provoked every living spire lobs a bile glob at the nearest player
## or player building in range; clients get a cosmetic replay.
func _spire_attack() -> void:
	for s in _satellites:
		if not is_instance_valid(s) or s.is_queued_for_deletion() or s.kind != "bile_spire" or s.health <= 0:
			continue
		var target = _nearest_glob_target(s.global_position)
		if target == null:
			continue
		var from: Vector2 = s.global_position + Vector2(0, -60)
		_launch_glob(from, target.global_position, false)
		if Net.is_online():
			_rpc_spire_glob.rpc(from, target.global_position)

func _nearest_glob_target(from: Vector2):
	var best = null
	var best_sq := spire_range * spire_range
	for group in ["player", "buildings"]:
		for node in get_tree().get_nodes_in_group(group):
			var sq: float = from.distance_squared_to(node.global_position)
			if sq < best_sq:
				best_sq = sq
				best = node
	return best

func _launch_glob(from: Vector2, to: Vector2, cosmetic: bool) -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	var glob = BILE_GLOB.new()
	glob.position = from
	glob.target_point = to
	glob.cosmetic = cosmetic
	scene.add_child(glob)

## Host only: one-time reward into the shared pool + score (points ride the
## wave manager's batched mirror so client scores follow, boss-kill style).
func _award_bounty() -> void:
	GameState.add_resource("scrap", bounty_scrap)
	GameState.add_resource("gold", bounty_gold)
	GameState.add_resource("crystal", bounty_crystal)
	var wm = get_tree().get_first_node_in_group("wave_manager")
	if wm != null:
		wm.enemy_killed.emit(hive_points)
		if Net.is_online():
			wm._points_pending += hive_points

## Shared host/client death path: big burst, satellites collapse, creep fades
## out then the site frees (NavGrid cells release on each structure's exit).
func _die() -> void:
	if _dead:
		return
	_dead = true
	var center := global_position
	if is_instance_valid(_hive):
		Effects.explosion(self, center)
		for i in 4:
			Effects.debris_burst(self, center + Vector2.from_angle(randf() * TAU) * randf_range(10.0, 70.0))
		for i in 4:
			_hive.hit_fx()
		Sfx.play("explosion", center, 0.0)
		_hive.queue_free()
	for s in _satellites:
		if is_instance_valid(s) and not s.is_queued_for_deletion():
			Effects.debris_burst(self, s.global_position)
			s.queue_free()
	var tw := create_tween()
	tw.tween_property(_creep, "modulate:a", 0.0, creep_fade)
	tw.tween_callback(queue_free)

## Satellite death (host + client mirror): debris + ichor, small collapse.
func _destroy_satellite(idx: int) -> void:
	for s in _satellites:
		if is_instance_valid(s) and not s.is_queued_for_deletion() and s.site_index == idx:
			Effects.debris_burst(self, s.global_position)
			s.hit_fx()
			Sfx.play("explosion", s.global_position, -8.0)
			s.queue_free()
			return

## Dormant-vs-erupting read: the hive flushes angry red while provoked.
func _set_provoked(on: bool) -> void:
	if _hive_visual != null and is_instance_valid(_hive_visual):
		_hive_visual.modulate = PROVOKED_TINT if on else Color.WHITE

func _structure_by_index(idx: int):
	if idx < 0:
		return _hive if is_instance_valid(_hive) else null
	for s in _satellites:
		if is_instance_valid(s) and not s.is_queued_for_deletion() and s.site_index == idx:
			return s
	return null

## -- host -> clients: combat state mirror --

@rpc("authority", "call_remote", "reliable")
func _rpc_struct_health(idx: int, value: int) -> void:
	var s = _structure_by_index(idx)
	if s != null:
		s.set_health(value)

@rpc("authority", "call_remote", "reliable")
func _rpc_struct_died(idx: int) -> void:
	_destroy_satellite(idx)

@rpc("authority", "call_remote", "reliable")
func _rpc_site_died() -> void:
	_die()

@rpc("authority", "call_remote", "reliable")
func _rpc_provoked(on: bool) -> void:
	_set_provoked(on)

@rpc("authority", "call_remote", "reliable")
func _rpc_spire_glob(from: Vector2, to: Vector2) -> void:
	_launch_glob(from, to, true)
