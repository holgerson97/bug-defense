extends Node2D
## Living battle diorama behind the main menu: a grasslands outpost wedged
## between two rock masses holds a corridor against endless small bug squads.
## Everything is the real game content (rocks, towers, enemies) consumed
## as-is — this driver only arranges it and keeps the fight eternal:
##   - GameState.godmode is held true while the backdrop lives, so tower
##     energy spends are free (restored on exit; a real run's
##     GameState.reset() clears it again anyway).
##   - Buildings get max_health x100 after _ready and a repair tower keeps
##     them topped, so the base never falls.
##   - A hidden DummyDefender in group "player" gives enemies a fallback
##     target and powers the towers through PowerGrid's walking-reactor aura.
##   - The driver joins group "day_night" pinned to a warm late afternoon
##     (darkness_factor 0.15 < 0.5), so towers see everything and lamps glow
##     softly.
##   - The SFX bus is ducked by DUCK_DB while the menu lives (re-asserted
##     every frame so a settings change can't undo it); Settings.apply() on
##     exit restores the canonical volume.
## The diorama exists ONLY in main_menu.tscn — never in the game scene.

const ROCK_SCENE := preload("res://scenes/rock.tscn")
const WALL_SCENE := preload("res://scenes/wall.tscn")
const MG_SCENE := preload("res://scenes/mg_tower.tscn")
const TESLA_SCENE := preload("res://scenes/tesla_tower.tscn")
const FLAME_SCENE := preload("res://scenes/flame_tower.tscn")
const REPAIR_SCENE := preload("res://scenes/repair_tower.tscn")
const LIGHT_POLE_SCENE := preload("res://scenes/light_pole.tscn")
const SOLAR_SCENE := preload("res://scenes/solar_panel.tscn")
const GRUNT_SCENE := preload("res://scenes/enemy.tscn")
const RUNNER_SCENE := preload("res://scenes/enemies/runner.tscn")
const BRUTE_SCENE := preload("res://scenes/enemies/brute.tscn")

## Fixed seed: the rock composition is identical on every launch.
const TERRAIN_SEED := 715517
## Pinned warm late afternoon (< 0.5 keeps every tower lit-gated ON).
const DARKNESS := 0.15
const DUCK_DB := -14.0

const MAX_ALIVE := 24
const SQUAD_WAIT_MIN := 8.0
const SQUAD_WAIT_MAX := 15.0
const FIRST_SQUAD_WAIT := 2.5
const LEAK_DIST := 2600.0
const LEAK_CHECK_EVERY := 2.0

## Layout (world coords; the camera drifts around CAM_HOME). The menu column
## + left-edge vignette own roughly screen x < 560 (world x < -80), so the
## outpost sits center-right and the rock corridor mouth at the right edge —
## the battle plays out in the open right two-thirds.
const BASE_CENTER := Vector2(0.0, 0.0)
const CAM_HOME := Vector2(0.0, 0.0)
const CAM_DRIFT := Vector2(40.0, 26.0)
const CAM_DRIFT_PERIOD := 20.0
const CAM_ZOOM_AMP := 0.03
const CAM_ZOOM_PERIOD := 17.0

var _prev_godmode := false
var _rock_tint := Color(1, 1, 1)
var _time := 0.0
var _squad_timer := FIRST_SQUAD_WAIT
var _leak_timer := LEAK_CHECK_EVERY

@onready var _terrain: Node2D = $Terrain
@onready var _buildings: Node2D = $Buildings
@onready var _enemies: Node2D = $Enemies
@onready var _camera: Camera2D = $Camera2D

func _ready() -> void:
	## Day/night contract (Util.is_lit, light_source/searchlight _ready): join
	## BEFORE any light-carrying building spawns below.
	add_to_group("day_night")
	_prev_godmode = GameState.godmode
	GameState.godmode = true
	## Grasslands look, exactly like main.gd wires it; a missing "worlds"
	## balance section degrades to {} = the classic midnight fallback.
	var def: Dictionary = GameState.world_def("grasslands")
	$Background.set_world(def)
	_rock_tint = Util.color_arr(def.get("rock_tint"), _rock_tint)
	## Warm golden late-afternoon: day tint pulled slightly toward dusk.
	var day: Color = Util.color_arr(def.get("day_modulate"), Color(1, 1, 1))
	var night: Color = Util.color_arr(def.get("night_modulate"), Color(0.13, 0.15, 0.22))
	$Warmth.color = day.lerp(night, DARKNESS) * Color(1.06, 0.97, 0.82)
	## Terrain + base from the FIXED seed (rock.generate and rock._ready draw
	## from the global RNG, both run synchronously inside this block).
	seed(TERRAIN_SEED)
	_spawn_terrain()
	_spawn_base()
	randomize()
	_camera.position = CAM_HOME
	_camera.make_current()

## Restores ride tree exit (Play fade frees us explicitly; a Net-driven scene
## change tears the menu down and lands here too). Rock/building NavGrid cells
## and light sources release themselves via their own tree_exited hooks.
func _exit_tree() -> void:
	GameState.godmode = _prev_godmode
	Settings.apply()

## "day_night" group contract (Util.is_lit + light sources at ready).
func darkness_factor() -> float:
	return DARKNESS

func _process(delta: float) -> void:
	_time += delta
	## Duck the SFX bus to a distant murmur; re-asserted every frame because
	## the settings menu (also alive here) writes the bus on any change.
	var sfx := AudioServer.get_bus_index("SFX")
	if sfx != -1:
		AudioServer.set_bus_volume_db(sfx,
			linear_to_db(clampf(Settings.sfx_volume, 0.0001, 1.0)) + DUCK_DB)
	## Self-heal godmode offline (leaving a co-op lobby can have synced it
	## off); online the host owns the flag and the setter no-ops on clients.
	if not GameState.godmode and not Net.is_online():
		GameState.godmode = true
	## Slow sinusoidal camera drift + faint zoom breathing.
	_camera.position = CAM_HOME + Vector2(
		sin(_time * TAU / CAM_DRIFT_PERIOD) * CAM_DRIFT.x,
		sin(_time * TAU / (CAM_DRIFT_PERIOD * 1.31)) * CAM_DRIFT.y)
	var z := 1.0 + CAM_ZOOM_AMP * sin(_time * TAU / CAM_ZOOM_PERIOD)
	_camera.zoom = Vector2(z, z)
	_squad_timer -= delta
	if _squad_timer <= 0.0:
		_squad_timer = randf_range(SQUAD_WAIT_MIN, SQUAD_WAIT_MAX)
		_spawn_squad()
	_leak_timer -= delta
	if _leak_timer <= 0.0:
		_leak_timer = LEAK_CHECK_EVERY
		_free_leaks()

## -- terrain ---------------------------------------------------------------

## Two large masses flank the corridor mouth; mediums dress the base flanks.
## The larges are PINNED by bbox corner so a walkable gate gap (roughly
## y -150..170 around x 300-720) is guaranteed no matter how the seeded blobs
## grow — centering them can fuse the flanks into one impassable wall.
func _spawn_terrain() -> void:
	_add_rock_pinned(Vector2(900.0, -150.0), 28, Vector2(1.0, 1.0))
	_add_rock_pinned(Vector2(900.0, 170.0), 28, Vector2(1.0, 0.0))
	_add_rock(Vector2(-96.0, -480.0), 10)
	_add_rock(Vector2(-128.0, 460.0), 10)

func _add_rock(center: Vector2, budget: int) -> void:
	var rock = ROCK_SCENE.instantiate()
	rock.generate(budget)
	_place_rock(rock, center - rock.bounds.get_center())

## Anchor so bounds.position + bounds.size * pin lands on `corner`:
## pin (1,1) = bottom-right bbox corner, (1,0) = top-right.
func _add_rock_pinned(corner: Vector2, budget: int, pin: Vector2) -> void:
	var rock = ROCK_SCENE.instantiate()
	rock.generate(budget)
	_place_rock(rock, corner - rock.bounds.position - rock.bounds.size * pin)

## 32px lattice snap, same as main._place_rock_formation.
func _place_rock(rock, anchor: Vector2) -> void:
	rock.position = anchor.snapped(Vector2(32.0, 32.0))
	rock.modulate = _rock_tint
	_terrain.add_child(rock)

## -- the outpost -----------------------------------------------------------

func _spawn_base() -> void:
	## Wall line with a gate gap (48px wall pitch; y = -48/0/48 skipped).
	for y in range(-288, 289, 48):
		if absi(y) <= 48:
			continue
		_add_building(WALL_SCENE, Vector2(160.0, float(y)))
	_add_building(MG_SCENE, Vector2(80.0, -64.0))
	_add_building(FLAME_SCENE, Vector2(80.0, 96.0))
	_add_building(TESLA_SCENE, Vector2(0.0, 16.0))
	_add_building(REPAIR_SCENE, Vector2(-64.0, -48.0))
	_add_building(SOLAR_SCENE, Vector2(-96.0, 112.0))
	_add_building(LIGHT_POLE_SCENE, Vector2(128.0, -208.0))
	_add_building(LIGHT_POLE_SCENE, Vector2(128.0, 176.0))
	var dummy := DummyDefender.new()
	dummy.position = BASE_CENTER
	dummy.visible = false
	dummy.add_to_group("player")
	add_child(dummy)

## x100 health AFTER _ready (balance/hp-mult already applied there), so the
## base can never be chewed down between repair pulses.
func _add_building(scene, pos: Vector2, facing := 0.0) -> void:
	var b = scene.instantiate()
	b.position = pos
	b.facing = facing
	_buildings.add_child(b)
	b.max_health = b.max_health * 100
	b.health = b.max_health
	b._update_health_bar()

## -- attackers -------------------------------------------------------------

## A squad of grunts/runners (occasional brute) from an off-screen point
## beyond the rocks, walking the corridor. Trimmed to the alive cap.
func _spawn_squad() -> void:
	var alive := get_tree().get_nodes_in_group("enemies").size()
	var count := mini(randi_range(4, 8), MAX_ALIVE - alive)
	if count <= 0:
		return
	var anchor := Vector2(randf_range(1020.0, 1220.0), randf_range(-200.0, 200.0))
	var brute := randf() < 0.25
	for i in count:
		var scene = GRUNT_SCENE
		if brute and i == 0:
			scene = BRUTE_SCENE
		elif randf() < 0.35:
			scene = RUNNER_SCENE
		var e = scene.instantiate()
		e.position = anchor + Vector2(randf_range(-70.0, 70.0), randf_range(-70.0, 70.0))
		_enemies.add_child(e)

## Safety valve: anything that wandered far off the diorama gets freed.
func _free_leaks() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(BASE_CENTER) > LEAK_DIST:
			e.queue_free()

## -- dummy defender --------------------------------------------------------

## Hidden stand-in inside the base with the minimal "player"-group API the
## consumers touch: enemies (_pick_target fallback -> global_position,
## take_damage), the repair tower (health / max_health() / heal) and
## PowerGrid.covered (class_mult("reactor_cover") + global_position — its
## reactor aura is what powers the diorama towers). Invulnerable no-op.
class DummyDefender extends Node2D:
	var health := 1000

	func max_health() -> int:
		return 1000

	func take_damage(_amount, _hit_fx := true) -> void:
		pass

	func heal(_amount) -> void:
		pass

	func class_mult(_key) -> float:
		return 1.0

	func class_add(_key) -> float:
		return 0.0
