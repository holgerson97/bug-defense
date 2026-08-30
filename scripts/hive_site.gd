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
##
## Growth: sites age in WAVES survived (host counts wave_started; clients get
## the stage via _rpc_stage). Each stage adds rim creep + tentacles, drawn
## from an RNG seeded off the site NAME + stage so peers agree given the same
## stage number. Every waves_per_expansion waves an unprovoked site sends an
## expansion drone (scripts/enemies/expansion_drone.gd) that founds a YOUNG
## site nearby: runtime host decision, mirrored by the drone's RPCs. Young
## sites reseed the global RNG from their name in _ready, so their layout is
## deterministic on every CURRENT peer; late joiners miss grown sites (the
## seeded-chunk replay doesn't know them) — accepted caveat.

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
var waves_per_expansion: int = maxi(Balance.inum("hive/waves_per_expansion", 5), 1)
var expansion_min: float = Balance.num("hive/expansion_range_min", 500.0)
var expansion_max: float = Balance.num("hive/expansion_range_max", 900.0)
var hive_spacing: float = Balance.num("hive/hive_spacing", 700.0)
var max_grown_hives: int = Balance.inum("hive/max_grown_hives", 6)
var growth_stage_waves: int = maxi(Balance.inum("hive/growth_stage_waves", 5), 1)
var growth_stage_cap: int = Balance.inum("hive/growth_stage_cap", 4)
var creep_growth: float = Balance.num("hive/creep_growth_per_stage", 0.15)
var young_hp_mult: float = Balance.num("hive/young_hp_mult", 0.5)

## Clearance a drone target keeps from player buildings / the spawn fan.
const EXPANSION_BUILD_CLEAR := 400.0

## Set BEFORE add_child by the founder (expansion drone): reduced-HP profile,
## small creep, 0-1 satellites, halved bounty; counts against max_grown_hives.
var young: bool = false

var _age_waves: int = 0           ## host: wave_started events survived
var _stage: int = 0               ## growth stage (host decides, RPC-mirrored)

var _hive = null                  ## the central hive_structure
var _hive_visual: Node2D = null
var _satellites: Array = []       ## hive_structure nodes (freed entries linger)
var _creep: Node2D
var _provoke_left: float = 0.0
var _squad_accum: float = 0.0
var _last_hit_spawn: float = -999.0
var _boss_spawned: bool = false
var _spire_accum: float = 0.0
var _defenders: Array = []        ## live defender enemies (cap enforcement)
var _dead: bool = false

func _ready() -> void:
	add_to_group("hive_sites")
	if young:
		## Runtime-founded site: reseed the global stream from the (replicated)
		## node name so _generate below draws identically on every peer — the
		## same trick main._seed_chunk plays with chunk hashes. Halved rewards.
		seed(hash(String(name)))
		add_to_group("grown_hives")
		var bm := Balance.num("hive/young_bounty_mult", 0.5)
		bounty_scrap = int(ceil(bounty_scrap * bm))
		bounty_gold = int(ceil(bounty_gold * bm))
		bounty_crystal = int(ceil(bounty_crystal * bm))
		hive_points = int(ceil(hive_points * bm))
		satellite_bounty = int(ceil(satellite_bounty * bm))
		creep_radius *= 0.6
	_generate()
	## Age/growth/expansion ride the wave counter; deferred so a site born
	## mid-frame never races the wave manager's group registration.
	call_deferred("_hook_waves")

func _hook_waves() -> void:
	var wm = get_tree().get_first_node_in_group("wave_manager")
	if wm != null and not wm.wave_started.is_connected(_on_wave_started):
		wm.wave_started.connect(_on_wave_started)

## All randf draws below run synchronously inside main._seed_chunk's seeded
## stream — identical layout on every peer, like rock.generate.
func _generate() -> void:
	## Creep field: 5-8 mats blended into one blob, below every gameplay node
	## (the whole Hives container sits right after Background in tree order).
	_creep = Node2D.new()
	add_child(_creep)
	for i in (randi_range(3, 4) if young else randi_range(5, 8)):
		var mat := Sprite2D.new()
		mat.texture = CREEP_TEX
		mat.rotation = randf() * TAU
		var s := randf_range(0.55, 0.95)
		mat.scale = Vector2(s, s)
		var reach := maxf(creep_radius - s * 256.0, 0.0)
		mat.position = Vector2.from_angle(randf() * TAU) * randf_range(0.0, reach)
		_creep.add_child(mat)
	## Hive body at the center (young sites rise at reduced HP).
	var hive_hp := Balance.inum("hive/hive_hp", 2000)
	if young:
		hive_hp = maxi(int(ceil(hive_hp * young_hp_mult)), 1)
	_hive = _make_structure("hive", Vector2.ZERO,
		Balance.num("hive/hive_radius", 90.0), hive_hp,
		HIVE_VISUAL, -1)
	## 2-4 satellites on the creep (young: 0-1); keep them apart and off the
	## hive body.
	var count := randi_range(0, 1) if young \
			else randi_range(Balance.inum("hive/satellites_min", 2), Balance.inum("hive/satellites_max", 4))
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
	## Defenders spawn per SHOT (on_structure_damaged), not on a timer.
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
	## Every shot on the HIVE body answers with defenders, escalating as its
	## health falls: grunts always, +tanks below 75%, +mages below 50%, and a
	## boss rises once at 10%.
	if s.site_index < 0 and s.health > 0:
		_on_hive_hit(s)
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
		_spire_accum = spire_interval * 0.5
		_set_provoked(true)
		if Net.is_online():
			_rpc_provoked.rpc(true)

## Per-shot defense (throttled so flame ticks / MG bursts count as one
## answer): grunts always; below 75% HP +tanks; below 50% +mages; at 10% a
## single boss rises from the maw. Counts multiply per living spore mound
## and growth stage. All spawns ride the replicated NO-COUNT path — clients
## see them, wave clearing ignores them (including mage/boss summons, which
## inherit the uncounted flag).
func _on_hive_hit(hive_struct) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_hit_spawn < Balance.num("hive/hit_cooldown", 0.4):
		return
	_last_hit_spawn = now
	_defenders = _defenders.filter(func(d): return is_instance_valid(d))
	var wm = get_tree().get_first_node_in_group("wave_manager")
	if wm == null:
		return
	var wave: int = maxi(wm.wave, 1)
	var frac := float(hive_struct.health) / float(maxi(hive_struct.max_health, 1))
	var mult := 1.0 + spore_bonus * float(_living_count("spore_mound"))
	var queue: Array = []
	for i in int(ceil((Balance.inum("hive/hit_grunts", 3) + _stage) * mult)):
		queue.append("grunt")
	if frac < Balance.num("hive/brute_frac", 0.75):
		for i in Balance.inum("hive/hit_brutes", 3):
			queue.append("brute")
	if frac < Balance.num("hive/mage_frac", 0.5):
		for i in Balance.inum("hive/hit_mages", 3):
			queue.append("mage")
	for kind in queue:
		if _defenders.size() >= max_defenders:
			break
		var pos: Vector2 = global_position + Vector2.from_angle(randf() * TAU) * randf_range(110.0, 150.0)
		var ov := {}
		match kind:
			"brute":
				ov = {"max_health": int(ceil(Balance.num("enemies/brute/hp", 15.0) * pow(wm.hp_scale_factor, wave - 1))), "speed_delta": wave * 2.0}
			"mage":
				ov = {"max_health": int(ceil(Balance.num("enemies/mage/hp", 6.0) * pow(wm.mage_hp_scale_factor, wave - 1)))}
			_:
				ov = {"max_health": int(ceil(Balance.num("enemies/grunt/hp", 2.0) * pow(wm.chaff_hp_scale_factor, wave - 1))), "speed_delta": wave * 2.0}
		var d = wm.spawn_hive_defender(kind, pos, ov)
		if d != null:
			_defenders.append(d)
	## The wounded queen: one boss per site, birthed at 10% health.
	if frac <= Balance.num("hive/boss_frac", 0.10) and not _boss_spawned:
		_boss_spawned = true
		@warning_ignore("integer_division")
		var boss_number: int = maxi(wave / maxi(wm.boss_every, 1), 1)
		var boss_hp := int(Balance.num("enemies/boss/hp", 250.0) * boss_number * pow(wm.boss_hp_growth, boss_number - 1))
		wm.spawn_hive_defender("boss", global_position + Vector2(0, 140), {"max_health": boss_hp})

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

## -- growth + expansion (host decides; stage mirrors like struct health) ----

## Host handler (clients re-emit wave_started too, so gate hard): age one
## wave, stage up every growth_stage_waves, and on expansion waves send a
## drone — unless provoked (an erupting nest has no larvae to spare).
func _on_wave_started(w: int) -> void:
	if _dead or (Net.is_online() and not Net.is_host()):
		return
	_age_waves += 1
	if _stage < growth_stage_cap and _age_waves % growth_stage_waves == 0:
		_apply_stage(_stage + 1)
		if Net.is_online():
			_rpc_stage.rpc(_stage)
	if w % waves_per_expansion == 0 and _provoke_left <= 0.0:
		_try_expand()

## Apply every stage up to `stage` (idempotent; clients may catch up several
## at once). Each stage draws from an RNG seeded off site name + stage — all
## peers grow the identical rim given the same stage number.
func _apply_stage(stage: int) -> void:
	while _stage < stage and _stage < growth_stage_cap:
		_stage += 1
		_grow_stage(_stage)

## One stage of visible growth: 2-3 creep mats pushing the rim out ~15%, and
## 1-2 fresh tentacles on the hive body (the visual animates late additions).
func _grow_stage(stage: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(name)) + stage * 977
	if _creep != null and is_instance_valid(_creep):
		var prev_r := creep_radius * (1.0 + creep_growth * float(stage - 1))
		var new_r := creep_radius * (1.0 + creep_growth * float(stage))
		for i in rng.randi_range(2, 3):
			var mat := Sprite2D.new()
			mat.texture = CREEP_TEX
			mat.rotation = rng.randf() * TAU
			var s := rng.randf_range(0.55, 0.85)
			mat.scale = Vector2(s, s)
			var lo := prev_r * 0.55
			var hi := maxf(new_r - s * 190.0, lo + 10.0)
			mat.position = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(lo, hi)
			_creep.add_child(mat)
	if _hive_visual != null and is_instance_valid(_hive_visual) and _hive_visual.has_method("add_tentacle"):
		for i in rng.randi_range(1, 2):
			_hive_visual.add_tentacle(rng.randf() * TAU, rng)

## Host: roll an expansion target and send the larva-carrier out through the
## wave manager's uncounted replicated spawn path. No valid spot or the grown
## cap is met -> the colony sits this cycle out.
func _try_expand() -> void:
	var wm = get_tree().get_first_node_in_group("wave_manager")
	if wm == null:
		return
	var extra := get_tree().get_nodes_in_group("grown_hives").size() \
			+ get_tree().get_nodes_in_group("expansion_drones").size()
	if extra >= max_grown_hives:
		return
	var target := _pick_expansion_target()
	if target == Vector2.INF:
		return
	var wave: int = maxi(wm.wave, 1)
	## Mild wave scaling: the chaff curve, not the brute curve.
	var hp := int(ceil(Balance.num("hive/drone_hp", 120.0) * pow(wm.chaff_hp_scale_factor, wave - 1)))
	var pos: Vector2 = global_position + Vector2.from_angle(randf() * TAU) * randf_range(110.0, 150.0)
	wm.spawn_hive_defender("expansion_drone", pos, {"max_health": hp, "dest": target})

## Candidate spot near the parent (drones do NOT travel far): clear of rocks,
## other hive sites, in-flight expansions, player buildings and the spawn fan.
## Host-only randomness — the result replicates via the drone's spawn payload.
func _pick_expansion_target() -> Vector2:
	for attempt in 8:
		var p := global_position + Vector2.from_angle(randf() * TAU) * randf_range(expansion_min, expansion_max)
		if _expansion_spot_clear(p):
			return p
	return Vector2.INF

func _expansion_spot_clear(p: Vector2) -> bool:
	## Spawn-area clearance (deterministic fan origin, like world gen uses).
	var spawn := Vector2(1280, 720)
	var scene = get_tree().current_scene
	if scene != null and scene.get_script() != null:
		spawn = scene.get_script().get_script_constant_map().get("PLAYER_SPAWN", spawn)
	if p.distance_to(spawn) < EXPANSION_BUILD_CLEAR + hive_spacing * 0.5:
		return false
	## Keep off every OTHER nest (the parent may be closer than the spacing).
	for site in get_tree().get_nodes_in_group("hive_sites"):
		if site != self and site.global_position.distance_to(p) < hive_spacing:
			return false
	## ... and off spots other drones are already crawling toward.
	for d in get_tree().get_nodes_in_group("expansion_drones"):
		if is_instance_valid(d) and d.dest.distance_to(p) < hive_spacing:
			return false
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.global_position.distance_to(p) < EXPANSION_BUILD_CLEAR:
			return false
	## Rock check: nearest_free returns the point unchanged only on free
	## ground. Sample the center plus two rings covering the site footprint.
	if NavGrid.nearest_free(p) != p:
		return false
	for i in 5:
		var a := TAU * float(i) / 5.0
		if NavGrid.nearest_free(p + Vector2.from_angle(a) * 120.0) != p + Vector2.from_angle(a) * 120.0:
			return false
		var q: Vector2 = p + Vector2.from_angle(a + 0.63) * 240.0
		if NavGrid.nearest_free(q) != q:
			return false
	return true

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
func _rpc_stage(stage: int) -> void:
	_apply_stage(stage)

@rpc("authority", "call_remote", "reliable")
func _rpc_spire_glob(from: Vector2, to: Vector2) -> void:
	_launch_glob(from, to, true)
