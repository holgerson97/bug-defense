extends Node
## Autoload singleton: run-wide state (resources, research, hotbar).

signal resources_changed(resources: Dictionary)
signal upgrades_changed
signal hotbar_changed
signal power_rates_changed(production: float, consumption: float)

const HOTBAR_SIZE := 17

## Stored energy is capped; each Battery building raises the cap.
var BASE_ENERGY_CAP: int = Balance.inum("upgrades/economy/energy_cap_base", 100)
var BATTERY_CAP_BONUS: int = Balance.inum("buildings/battery/cap_bonus", 100)

## Branches holding one-shot building unlocks (everything else is repeatable).
const UNLOCK_BRANCHES := ["Defense", "Resource", "Electricity"]

## Shipped defaults for the research table; costs and effects are overlaid
## from balance.json ("upgrades/research/<id>") in _init — icons, names,
## branches, descriptions and requires always stay in code.
const UPGRADE_DEFAULTS := {
	# Player and building stats: one flat repeatable button per category — each
	# purchase raises the level (effect stacks) and the price (x1.6 per level).
	"damage": {"icon": "res://assets/icons/blaster.svg", "name": "Damage", "branch": "Offense", "desc": "+1 bullet damage", "cost": {"scrap": 35}, "requires": [], "effects": {"damage_bonus": 1.0}},
	"attack_speed": {"icon": "res://assets/icons/blaster.svg", "name": "Attack Speed", "branch": "Offense", "desc": "+10% fire rate", "cost": {"scrap": 52}, "requires": [], "effects": {"fire_rate_cut": 0.1}},
	"crit_chance": {"icon": "res://assets/icons/crit.svg", "name": "Crit Chance", "branch": "Offense", "desc": "+5% crit chance", "cost": {"scrap": 110}, "requires": [], "effects": {"crit_chance": 0.05}},
	"crit_damage": {"icon": "res://assets/icons/crit.svg", "name": "Crit Damage", "branch": "Offense", "desc": "+25% crit damage", "cost": {"scrap": 140}, "requires": [], "effects": {"crit_mult": 0.25}},
	"speed": {"icon": "res://assets/icons/xp.svg", "name": "Move Speed", "branch": "Pilot", "desc": "+10% move speed", "cost": {"scrap": 35}, "requires": [], "effects": {"speed_mult": 0.1}},
	"health": {"icon": "res://assets/icons/health.svg", "name": "Max Health", "branch": "Pilot", "desc": "+25 max health", "cost": {"scrap": 52}, "requires": [], "effects": {"player_hp_bonus": 25.0}},
	"regen": {"icon": "res://assets/icons/health.svg", "name": "Regeneration", "branch": "Pilot", "desc": "+1 HP/s regen", "cost": {"scrap": 140}, "requires": [], "effects": {"player_regen": 1.0}},
	"player_light": {"icon": "res://assets/icons/light_pole.svg", "name": "Headlamp", "branch": "Pilot", "desc": "+15% light radius", "cost": {"scrap": 42}, "requires": [], "effects": {"light_radius": 0.15}},
	"build_range": {"icon": "res://assets/icons/wall.svg", "name": "Build Range", "branch": "Pilot", "desc": "+10% build range", "cost": {"scrap": 52}, "requires": [], "effects": {"build_range": 0.1}},
	"heal_range": {"icon": "res://assets/icons/repair_tower.svg", "name": "Beam Range", "branch": "Pilot", "desc": "+15% heal beam range", "cost": {"scrap": 42}, "requires": [], "effects": {"heal_range": 0.15}},
	"heal_amount": {"icon": "res://assets/icons/repair_tower.svg", "name": "Beam Potency", "branch": "Pilot", "desc": "+1 heal per beam tick", "cost": {"scrap": 56}, "requires": [], "effects": {"heal_amount": 1.0}},
	"player_power": {"icon": "res://assets/icons/solar_panel.svg", "name": "Reactor Output", "branch": "Pilot", "desc": "+20% suit energy output", "cost": {"scrap": 70}, "requires": [], "effects": {"player_power": 0.2}},
	"player_power_range": {"icon": "res://assets/icons/power_pole.svg", "name": "Reactor Aura", "branch": "Pilot", "desc": "+15% suit power radius", "cost": {"scrap": 56}, "requires": [], "effects": {"player_cover": 0.15}},
	"miner_1": {"icon": "res://assets/icons/miner.svg", "name": "Miner", "branch": "Resource", "desc": "Unlocks the Miner building", "cost": {"scrap": 105}, "requires": [], "effects": {}},
	"walls_1": {"icon": "res://assets/icons/wall.svg", "name": "Walls", "branch": "Defense", "desc": "Unlocks buildable Walls", "cost": {"scrap": 52}, "requires": [], "effects": {}},
	"mg_tower_1": {"icon": "res://assets/icons/mg_tower.svg", "name": "Machine Gun Tower", "branch": "Defense", "desc": "Unlocks the MG Tower", "cost": {"scrap": 230}, "requires": ["walls_1"], "effects": {}},
	"grenade_tower_1": {"icon": "res://assets/icons/grenade_tower.svg", "name": "Grenade Tower", "branch": "Defense", "desc": "Unlocks the Grenade Tower", "cost": {"scrap": 320}, "requires": ["mg_tower_1"], "effects": {}},
	"repair_tower_1": {"icon": "res://assets/icons/repair_tower.svg", "name": "Repair Beam Tower", "branch": "Defense", "desc": "Unlocks the Repair Tower", "cost": {"scrap": 270}, "requires": ["walls_1"], "effects": {}},
	"tesla_tower_1": {"icon": "res://assets/icons/tesla_tower.svg", "name": "Tesla Tower", "branch": "Defense", "desc": "Unlocks the Tesla Tower", "cost": {"scrap": 410}, "requires": ["mg_tower_1"], "effects": {}},
	"flame_tower_1": {"icon": "res://assets/icons/flame_tower.svg", "name": "Flamethrower Tower", "branch": "Defense", "desc": "Unlocks the Flamethrower Tower", "cost": {"scrap": 320}, "requires": ["walls_1"], "effects": {}},
	"aa_tower_1": {"icon": "res://assets/icons/aa_tower.svg", "name": "AA Flak Cannon", "branch": "Defense", "desc": "Unlocks the anti-air Flak Cannon", "cost": {"scrap": 450}, "requires": ["mg_tower_1"], "effects": {}},
	"building_walk": {"icon": "res://assets/icons/wall.svg", "name": "Phase Stride", "branch": "Defense", "desc": "Walk across buildings", "cost": {"scrap": 6000}, "requires": ["walls_1"], "effects": {}},
	# Building stats: flat repeatable categories like player stats above.
	"building_hp": {"icon": "res://assets/icons/wall.svg", "name": "Reinforced Structures", "branch": "Engineering", "desc": "+25% building health", "cost": {"scrap": 70}, "requires": [], "effects": {"building_hp_mult": 0.25}},
	"tower_damage": {"icon": "res://assets/icons/mg_tower.svg", "name": "Heavy Ordnance", "branch": "Engineering", "desc": "+1 tower damage", "cost": {"scrap": 175}, "requires": [], "effects": {"tower_damage": 1.0}},
	"miner_yield": {"icon": "res://assets/icons/miner.svg", "name": "Efficient Drills", "branch": "Engineering", "desc": "+1 crystal per mining cycle", "cost": {"scrap": 115}, "requires": [], "effects": {"miner_yield": 1.0}},
	"tower_speed": {"icon": "res://assets/icons/mg_tower.svg", "name": "Rapid Servos", "branch": "Engineering", "desc": "+15% tower attack speed", "cost": {"scrap": 160}, "requires": [], "effects": {"tower_speed": 0.15}},
	"tower_range": {"icon": "res://assets/icons/mg_tower.svg", "name": "Extended Barrels", "branch": "Engineering", "desc": "+10% tower range", "cost": {"scrap": 200}, "requires": [], "effects": {"tower_range": 0.1}},
	"tower_crit_chance": {"icon": "res://assets/icons/crit.svg", "name": "Targeting Optics", "branch": "Engineering", "desc": "+5% tower crit chance", "cost": {"scrap": 225}, "requires": [], "effects": {"tower_crit_chance": 0.05}},
	"tower_crit_damage": {"icon": "res://assets/icons/crit.svg", "name": "Overcharged Cells", "branch": "Engineering", "desc": "+50% tower crit damage", "cost": {"scrap": 285}, "requires": [], "effects": {"tower_crit_mult": 0.5}},
	"solar_1": {"icon": "res://assets/icons/solar_panel.svg", "name": "Solar Panel", "branch": "Electricity", "desc": "Unlocks the Solar Panel", "cost": {"scrap": 35}, "requires": [], "effects": {}},
	"command_center_1": {"icon": "res://assets/icons/command_center.svg", "name": "Command Center", "branch": "Resource", "desc": "Unlocks the Command Center", "cost": {"scrap": 500}, "requires": ["miner_1"], "effects": {}},
	"light_pole_1": {"icon": "res://assets/icons/light_pole.svg", "name": "Light Pole", "branch": "Electricity", "desc": "Unlocks the Light Pole", "cost": {"scrap": 28}, "requires": [], "effects": {}},
	"searchlight_1": {"icon": "res://assets/icons/searchlight.svg", "name": "Searchlight", "branch": "Electricity", "desc": "Unlocks the rotating Searchlight", "cost": {"scrap": 230}, "requires": ["light_pole_1"], "effects": {}},
	"battery_1": {"icon": "res://assets/icons/battery.svg", "name": "Battery", "branch": "Electricity", "desc": "Unlocks the Battery (+100 energy cap each)", "cost": {"scrap": 140}, "requires": ["solar_1"], "effects": {}},
	"power_pole_1": {"icon": "res://assets/icons/power_pole.svg", "name": "Power Pole", "branch": "Electricity", "desc": "Unlocks the Power Pole (carries grid power)", "cost": {"scrap": 50}, "requires": ["solar_1"], "effects": {}},
	"intake_station_1": {"icon": "res://assets/icons/intake_station.svg", "name": "Intake Station", "branch": "Electricity", "desc": "Unlocks the crystal-burning Intake Station", "cost": {"scrap": 410}, "requires": ["battery_1"], "effects": {}},
	"cooling_tower_1": {"icon": "res://assets/icons/cooling_tower.svg", "name": "Cooling Tower", "branch": "Electricity", "desc": "Unlocks the Cooling Tower (boosts the Intake Station)", "cost": {"scrap": 100}, "requires": ["battery_1"], "effects": {}},
}

# Single source of truth per placeable: per-placement cost, unlocking research,
# hotbar slot, and (for towers) attack range read by both the tower script and
# the placement ghost. "tower": true marks combat towers (range upgrades,
# range-ring preview) — check that flag, never sniff the id. "arc" (degrees)
# makes a tower directional: it only engages enemies inside that wedge around
# its placement facing (R rotates).
# The searchlight's "range" is its beam reach; "cone" the full beam angle in
# degrees (mirrored by BEAM_REACH / BEAM_HALF_ANGLE in searchlight.gd);
# "sweep" the full ping-pong arc in degrees (mirrors SWEEP_HALF_ARC there).
# The power pole's "range" is its grid coverage radius (PowerGrid.COVER_RANGE);
# the intake station's is its complex radius (COMPLEX_RANGE) — both only feed
# the ghost's placement circle.
## Buildings cost crystal (plus gold for premium ones); bug hearts
## (internal key "scrap") are spent exclusively on research.
## Shipped defaults: costs and range/arc/cone/sweep are overlaid from
## balance.json in _init (towers read range/arc from "towers/<id>",
## support buildings from "buildings/<id>").
const BUILDING_DEFAULTS := {
	"miner": {"icon": "res://assets/icons/miner.svg", "name": "Miner", "cost": {"crystal": 15}, "research": "miner_1", "slot": 1},
	"wall": {"icon": "res://assets/icons/wall.svg", "name": "Wall", "cost": {"crystal": 6}, "research": "walls_1", "slot": 2},
	"mg_tower": {"icon": "res://assets/icons/mg_tower.svg", "name": "MG Tower", "cost": {"crystal": 90}, "research": "mg_tower_1", "slot": 3, "range": 350.0, "arc": 90.0, "tower": true},
	"grenade_tower": {"icon": "res://assets/icons/grenade_tower.svg", "name": "Grenade Tower", "cost": {"crystal": 120}, "research": "grenade_tower_1", "slot": 4, "range": 450.0, "arc": 120.0, "tower": true},
	"repair_tower": {"icon": "res://assets/icons/repair_tower.svg", "name": "Repair Tower", "cost": {"crystal": 100}, "research": "repair_tower_1", "slot": 5, "range": 250.0, "tower": true},
	"tesla_tower": {"icon": "res://assets/icons/tesla_tower.svg", "name": "Tesla Tower", "cost": {"crystal": 115, "gold": 15}, "research": "tesla_tower_1", "slot": 6, "range": 360.0, "tower": true},
	"flame_tower": {"icon": "res://assets/icons/flame_tower.svg", "name": "Flamethrower Tower", "cost": {"crystal": 105}, "research": "flame_tower_1", "slot": 7, "range": 260.0, "arc": 90.0, "tower": true},
	"aa_tower": {"icon": "res://assets/icons/aa_tower.svg", "name": "AA Flak Cannon", "cost": {"crystal": 130, "gold": 20}, "research": "aa_tower_1", "slot": 8, "range": 550.0, "arc": 120.0, "tower": true},
	"solar_panel": {"icon": "res://assets/icons/solar_panel.svg", "name": "Solar Panel", "cost": {"crystal": 12}, "research": "solar_1", "slot": 9},
	"command_center": {"icon": "res://assets/icons/command_center.svg", "name": "Command Center", "cost": {"crystal": 160}, "research": "command_center_1", "slot": 10},
	"light_pole": {"icon": "res://assets/icons/light_pole.svg", "name": "Light Pole", "cost": {"crystal": 8}, "research": "light_pole_1", "slot": 11},
	"searchlight": {"icon": "res://assets/icons/searchlight.svg", "name": "Searchlight", "cost": {"crystal": 70, "gold": 10}, "research": "searchlight_1", "slot": 12, "range": 500.0, "cone": 36.0, "sweep": 140.0},
	"battery": {"icon": "res://assets/icons/battery.svg", "name": "Battery", "cost": {"crystal": 45}, "research": "battery_1", "slot": 13},
	"power_pole": {"icon": "res://assets/icons/power_pole.svg", "name": "Power Pole", "cost": {"crystal": 10}, "research": "power_pole_1", "slot": 14, "range": 160.0},
	"intake_station": {"icon": "res://assets/icons/intake_station.svg", "name": "Intake Station", "cost": {"crystal": 130, "gold": 25}, "research": "intake_station_1", "slot": 15, "range": 110.0},
	"cooling_tower": {"icon": "res://assets/icons/cooling_tower.svg", "name": "Cooling Tower", "cost": {"crystal": 55, "gold": 10}, "research": "cooling_tower_1", "slot": 16},
}

## Global bounty boost: kills pay 1.25x their listed bug-heart value.
var SCRAP_GAIN_MULT: float = Balance.num("upgrades/economy/scrap_gain_mult", 1.25)

## Balance-fed live tables (same shape as the *_DEFAULTS consts above).
var UPGRADES: Dictionary = {}
var BUILDINGS: Dictionary = {}
## Player classes, purely from balance.json "classes" (data-driven: the owner
## adds/tunes classes there). Missing/empty section degrades to a lone neutral
## Assault, so everyone keeps today's baseline stats.
var CLASSES: Dictionary = {}
## Selectable worlds, purely from balance.json "worlds" (data-driven like
## CLASSES). Missing/empty section leaves this empty: no world picker, and
## every run plays the classic midnight look (all world params fall back).
var WORLDS: Dictionary = {}

## Balance-fed bases for the stat helpers below (fallback = shipped value).
var _cost_scale: float = Balance.num("upgrades/cost_scale", 1.6)
var _player_crit_base: float = Balance.num("upgrades/crit/player_chance_base", 0.05)
var _player_crit_cap: float = Balance.num("upgrades/crit/player_chance_cap", 0.8)
var _player_crit_mult_base: float = Balance.num("upgrades/crit/player_mult_base", 1.5)
var _tower_crit_cap: float = Balance.num("upgrades/crit/tower_chance_cap", 0.8)
var _tower_crit_mult_base: float = Balance.num("upgrades/crit/tower_mult_base", 1.5)
var _player_damage_base: int = Balance.inum("player/damage", 1)
var _player_hp_base: int = Balance.inum("player/max_health", 100)
var _min_fire_cooldown: float = Balance.num("player/min_fire_cooldown", 0.04)
var _crystal_start: int = Balance.inum("upgrades/economy/crystal_start", 30)
var _energy_start: int = Balance.inum("upgrades/economy/energy_start", 20)

func _init() -> void:
	for id in UPGRADE_DEFAULTS:
		var up: Dictionary = UPGRADE_DEFAULTS[id].duplicate(true)
		up["cost"] = Balance.cost_dict("upgrades/research/%s/cost" % id, up["cost"])
		var eff: Dictionary = Balance.dict("upgrades/research/%s/effects" % id, up["effects"])
		var effects := {}
		for key in eff:
			if eff[key] is float or eff[key] is int:
				effects[key] = float(eff[key])
		up["effects"] = effects
		UPGRADES[id] = up
	for id in BUILDING_DEFAULTS:
		var b: Dictionary = BUILDING_DEFAULTS[id].duplicate(true)
		b["cost"] = Balance.cost_dict("buildings/%s/cost" % id, b["cost"])
		var sec: String = ("towers/" + id) if b.get("tower", false) else ("buildings/" + id)
		for key in ["range", "arc", "cone", "sweep"]:
			if b.has(key):
				b[key] = Balance.num("%s/%s" % [sec, key], b[key])
		BUILDINGS[id] = b
	## Classes: "stats" values are MULTIPLIERS over the "player" bases (1.0 =
	## unchanged); keys ending in "_add" are flat adds. Underscore keys
	## ("_readme") are documentation, not classes.
	var class_section: Dictionary = Balance.section("classes")
	for id in class_section:
		if not str(id).begins_with("_") and class_section[id] is Dictionary:
			CLASSES[id] = class_section[id]
	if CLASSES.is_empty():
		CLASSES = {"assault": {"name": "Assault", "desc": "Balanced frontline fighter", "tint": [1.0, 1.0, 1.0], "stats": {}}}
	## Worlds mirror the classes pattern; underscore keys are documentation.
	var world_section: Dictionary = Balance.section("worlds")
	for id in world_section:
		if not str(id).begins_with("_") and world_section[id] is Dictionary:
			WORLDS[id] = world_section[id]

var power_production: float = 0.0
var power_consumption: float = 0.0
var _prod_accum: float = 0.0
var _cons_accum: float = 0.0
var _rate_timer: float = 0.0
## Starter crystal lets the first solar/wall/miner go up before any mining.
var resources: Dictionary = {"scrap": 0, "crystal": _crystal_start, "energy": _energy_start}
## Cheat toggle (G): player takes no damage, all costs are free.
## Online it is session-wide and host-owned: client G presses are ignored
## (the setter no-ops), the host's state broadcast mirrors it to everyone.
var godmode := false:
	set(value):
		if _is_client() and not _applying_sync:
			return
		godmode = value
		_sync_dirty = true
var purchased: Dictionary = {}
var hotbar: Array = []
var selected_slot: int = 0
## Fractional scrap owed from bounty multiplication; paid out once it
## accumulates to a whole unit, so long-run payout is exactly +25%.
var _scrap_carry := 0.0
## Host: a broadcast is pending (flushed once per physics frame, see below).
var _sync_dirty := false
## True while a client applies a host broadcast (lets sync writes through
## client-side guards like the godmode setter).
var _applying_sync := false

func _ready() -> void:
	## MP: any state change marks the host dirty; the actual broadcast is
	## debounced to one reliable RPC per physics frame in _physics_process.
	resources_changed.connect(func(_r): _sync_dirty = true)
	upgrades_changed.connect(func(): _sync_dirty = true)
	## The broadcast must keep flowing while the host has the game paused
	## (research purchases still land via the always-processing HUD; RPCs also
	## arrive during pause) — otherwise mirrors go stale until unpause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset()

## Online, not the host: this GameState is a read-only mirror of the host's.
## Offline this is always false, so every call below takes the direct path
## with zero RPC overhead. Looked up by path because this autoload loads
## (and resets) before Net does.
func _is_client() -> bool:
	if not is_inside_tree():
		return false
	var net := get_node_or_null("/root/Net")
	return net != null and net.is_online() and not net.is_host()

func reset() -> void:
	resources = {"scrap": 0, "crystal": _crystal_start, "energy": _energy_start}
	godmode = false
	purchased = {}
	_scrap_carry = 0.0
	hotbar = [{"id": "blaster", "name": "Blaster", "icon": "res://assets/icons/blaster.svg"}, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null]
	selected_slot = 0
	resources_changed.emit(resources)
	upgrades_changed.emit()
	hotbar_changed.emit()

func add_resource(kind: String, amount: int) -> void:
	## Client: income is an intent — the host banks it into the shared pool
	## and the next broadcast updates the mirror. No local mutation.
	if _is_client():
		_rpc_add_resource.rpc_id(1, kind, amount)
		return
	if kind == "energy" and amount > 0:
		_prod_accum += amount
	resources[kind] = resources.get(kind, 0) + amount
	# Banked energy clamps to the cap on every gain — overflow is wasted.
	if kind == "energy":
		resources[kind] = mini(resources[kind], energy_cap())
	resources_changed.emit(resources)

## Kill bounty with the global multiplier and fractional carry: rounding
## remainders bank up instead of ceil-doubling 1-scrap chaff kills.
func add_scrap_bounty(base: int) -> void:
	## Client: the host applies the multiplier and owns the carry.
	if _is_client():
		_rpc_add_scrap_bounty.rpc_id(1, base)
		return
	var total := base * SCRAP_GAIN_MULT + _scrap_carry
	var whole := int(total)
	_scrap_carry = total - whole
	add_resource("scrap", whole)

## Storage limit for banked energy: base plus a bonus per standing Battery.
func energy_cap() -> int:
	var tree := get_tree()
	var batteries := tree.get_node_count_in_group("batteries") if tree != null else 0
	return BASE_ENERGY_CAP + batteries * BATTERY_CAP_BONUS

## Batteries call this on ready/exit: re-clamps banked energy to the new cap
## (a destroyed battery drops stored charge) and refreshes the HUD readout.
## Clients skip the clamp: their battery set is local-only until Phase 4
## replicates buildings, so their cap is HUD-cosmetic — the host owns energy.
func energy_cap_changed() -> void:
	if not _is_client():
		resources["energy"] = mini(int(resources.get("energy", 0)), energy_cap())
	resources_changed.emit(resources)

## Rolling per-second energy production/consumption, refreshed every 2s
## for the HUD's demand/capacity readout.
func _process(delta: float) -> void:
	## process_mode ALWAYS is for the sync flush below; rate accounting keeps
	## freezing with the sim like it always did.
	if get_tree().paused:
		return
	_rate_timer += delta
	if _rate_timer >= 2.0:
		power_production = _prod_accum / _rate_timer
		power_consumption = _cons_accum / _rate_timer
		_prod_accum = 0.0
		_cons_accum = 0.0
		_rate_timer = 0.0
		power_rates_changed.emit(power_production, power_consumption)

## Host: flush at most ONE full-state broadcast per physics frame, no matter
## how many mutations landed this frame (the dicts are tiny; reliable channel).
func _physics_process(_delta: float) -> void:
	if not _sync_dirty:
		return
	_sync_dirty = false
	if Net.is_online() and Net.is_host():
		_rpc_sync_state.rpc(resources, purchased, godmode)

## Per-attack energy drain for towers and miners. Returns false (and spends
## nothing) when there isn't enough energy banked.
func try_spend_energy(amount: int) -> bool:
	if godmode:
		return true
	## Client: report mirror availability WITHOUT spending and WITHOUT an RPC.
	## Until Phases 4-5 move buildings/towers host-side, every peer still
	## simulates its own towers locally — only the HOST's copies may actually
	## drain the shared pool, or each attack would be paid once per peer.
	## Phases 4-5 remove client-side building simulation (and this branch).
	if _is_client():
		return resources.get("energy", 0) >= amount
	if resources.get("energy", 0) < amount:
		return false
	resources["energy"] -= amount
	_cons_accum += amount
	resources_changed.emit(resources)
	return true

func can_afford(cost: Dictionary) -> bool:
	if godmode:
		return true
	for kind in cost:
		if resources.get(kind, 0) < cost[kind]:
			return false
	return true

## Godmode spends nothing — succeed without touching resources (no emit needed).
## Client: optimistic — checks the mirror, sends the spend intent to the host
## and deducts the mirror immediately (callers like build_controller expect a
## synchronous bool and place instantly). The host revalidates; its next state
## broadcast overwrites the mirror either way, so a rare reject self-heals.
func spend(cost: Dictionary) -> bool:
	if godmode:
		return true
	if not can_afford(cost):
		return false
	if _is_client():
		_rpc_spend.rpc_id(1, cost)
	for kind in cost:
		resources[kind] -= cost[kind]
	resources_changed.emit(resources)
	return true

func select_slot(index: int) -> void:
	selected_slot = clampi(index, 0, HOTBAR_SIZE - 1)
	hotbar_changed.emit()

func set_hotbar_item(index: int, item) -> void:
	hotbar[index] = item
	hotbar_changed.emit()

func selected_item_id() -> String:
	var item = hotbar[selected_slot]
	return item["id"] if item != null else ""

## Stat upgrades (Offense/Pilot/Engineering) can be bought forever; unlock
## branches (Defense/Resource/Electricity) are one-time.
func is_repeatable(id: String) -> bool:
	return not UPGRADES[id]["branch"] in UNLOCK_BRANCHES

func upgrade_level(id: String) -> int:
	return int(purchased.get(id, 0))

## Repeatable upgrades get 60% more expensive per level owned.
func upgrade_cost(id: String) -> Dictionary:
	var base: Dictionary = UPGRADES[id]["cost"]
	var lvl := upgrade_level(id)
	if lvl == 0 or not is_repeatable(id):
		return base
	var scaled := {}
	for kind in base:
		# minf guards against int64 overflow at absurd upgrade levels.
		scaled[kind] = int(ceil(minf(base[kind] * pow(_cost_scale, lvl), 1e12)))
	return scaled

func is_purchased(id: String) -> bool:
	return upgrade_level(id) > 0

func is_unlocked(id: String) -> bool:
	for req in UPGRADES[id]["requires"]:
		if not is_purchased(req):
			return false
	return true

func can_purchase(id: String) -> bool:
	if not is_repeatable(id) and is_purchased(id):
		return false
	return is_unlocked(id) and can_afford(upgrade_cost(id))

func purchase(id: String) -> bool:
	if not can_purchase(id):
		return false
	## Client: purchase is a single intent RPC — the host runs the real
	## spend + level-up and broadcasts. Only the mirror's resources are
	## deducted optimistically (NOT via spend(), which would RPC a second,
	## double-counted spend); the level itself waits for the host broadcast.
	if _is_client():
		var cost := upgrade_cost(id)
		_rpc_purchase.rpc_id(1, id)
		if not godmode:
			for kind in cost:
				resources[kind] -= cost[kind]
			resources_changed.emit(resources)
		return true
	spend(upgrade_cost(id))
	purchased[id] = upgrade_level(id) + 1
	# Building unlocks put their item into the hotbar slot from the table.
	for b_id in BUILDINGS:
		var b: Dictionary = BUILDINGS[b_id]
		if b["research"] == id:
			set_hotbar_item(b["slot"], {"id": b_id, "name": b["name"], "icon": b["icon"]})
	upgrades_changed.emit()
	return true

## Sum of one effect key across all purchased upgrades.
func stat(key: String) -> float:
	var total := 0.0
	for id in purchased:
		var effects: Dictionary = UPGRADES[id]["effects"]
		if effects.has(key):
			total += effects[key] * upgrade_level(id)
	return total

# Player stats: research effects.
func player_damage() -> int:
	return _player_damage_base + int(stat("damage_bonus"))

func player_crit_chance() -> float:
	return minf(_player_crit_base + stat("crit_chance"), _player_crit_cap)

func player_crit_mult() -> float:
	return _player_crit_mult_base + stat("crit_mult")

func player_fire_cooldown(base_cooldown: float) -> float:
	# Diminishing returns so unlimited fire-rate levels never hit zero.
	return maxf(base_cooldown / (1.0 + stat("fire_rate_cut")), _min_fire_cooldown)

func player_speed(base_speed: float) -> float:
	return base_speed * (1.0 + stat("speed_mult"))

func player_max_health() -> int:
	return _player_hp_base + int(stat("player_hp_bonus"))

func player_regen() -> float:
	return stat("player_regen")

func player_light_mult() -> float:
	return 1.0 + stat("light_radius")

func build_range_mult() -> float:
	return 1.0 + stat("build_range")

## Heal beam (hold F): reach and extra healing per tick.
func player_heal_range_mult() -> float:
	return 1.0 + stat("heal_range")

func player_heal_bonus() -> int:
	return int(stat("heal_amount"))

## Suit reactor: energy output and power-aura radius scaling.
func player_power_mult() -> float:
	return 1.0 + stat("player_power")

func player_cover_mult() -> float:
	return 1.0 + stat("player_cover")

## -- player classes --
## Per-player, NOT research: the shared helpers above stay class-agnostic and
## each consumer layers its own class on top. Stat layering order everywhere:
##   base (balance.json "player") -> research bonuses (helpers above)
##   -> class multiplier / flat add (outermost).
## Flat bases (max HP, damage, heal) are deliberately scaled AFTER research so
## class identity holds late-game (a Heavy's +25 HP research is worth x1.6).

func class_info(id: String) -> Dictionary:
	var c = CLASSES.get(id)
	return c if c is Dictionary else {}

func class_title(id: String) -> String:
	return str(class_info(id).get("name", id.capitalize()))

func class_desc(id: String) -> String:
	return str(class_info(id).get("desc", ""))

func class_sprite(id: String) -> String:
	return str(class_info(id).get("sprite", ""))

## Innate class perk: walk over buildings without the Phase Stride research.
func class_building_walk(id: String) -> bool:
	return bool(class_info(id).get("building_walk", false))

func class_tint(id: String) -> Color:
	var t = class_info(id).get("tint")
	if t is Array and t.size() >= 3:
		return Color(float(t[0]), float(t[1]), float(t[2]))
	return Color.WHITE

## World theme params for main/background/day_night; unknown id = {} and every
## consumer's fallback reproduces the classic midnight world.
func world_def(id: String) -> Dictionary:
	var w = WORLDS.get(id)
	return w if w is Dictionary else {}

func world_title(id: String) -> String:
	return str(world_def(id).get("name", id.capitalize()))

func world_desc(id: String) -> String:
	return str(world_def(id).get("desc", ""))

func _class_stat(id: String, key: String):
	var stats = class_info(id).get("stats")
	return stats.get(key) if stats is Dictionary else null

## Multiplier over a player base stat; unknown class/key = neutral 1.0 (so a
## missing "classes" section means everyone plays Assault).
func class_mult(id: String, key: String) -> float:
	var v = _class_stat(id, key)
	return float(v) if (v is float or v is int) else 1.0

## Flat add ("*_add" keys) over a player base stat; unknown = 0.0.
func class_add(id: String, key: String) -> float:
	var v = _class_stat(id, key)
	return float(v) if (v is float or v is int) else 0.0

# Building stats (Engineering research).
func building_hp_mult() -> float:
	return 1.0 + stat("building_hp_mult")

func tower_damage_bonus() -> int:
	return int(stat("tower_damage"))

func miner_yield_bonus() -> int:
	return int(stat("miner_yield"))

## Attack towers fire faster per Rapid Servos level (diminishing returns).
func tower_interval(base_interval: float) -> float:
	return base_interval / (1.0 + stat("tower_speed"))

## Attack and repair towers reach further per Extended Barrels level.
func tower_range_mult() -> float:
	return 1.0 + stat("tower_range")

func tower_crit_chance() -> float:
	return minf(stat("tower_crit_chance"), _tower_crit_cap)

func tower_crit_mult() -> float:
	return _tower_crit_mult_base + stat("tower_crit_mult")

## Tower hit: base + flat damage bonus, then a crit roll.
func tower_damage_roll(base_damage: int) -> int:
	var dmg := base_damage + tower_damage_bonus()
	if randf() < tower_crit_chance():
		dmg = int(ceil(dmg * tower_crit_mult()))
	return dmg

## -- MP RPCs (Phase 3): client intents up, host state broadcast down. --
## Autoload, so node paths match on every peer. Host handlers route into the
## normal (host/offline) code paths above, which validate and mark dirty.

## Client -> host: bank income into the shared pool.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_add_resource(kind: String, amount: int) -> void:
	if multiplayer.is_server() and amount > 0:
		add_resource(kind, amount)

## Client -> host: kill bounty (host applies multiplier + carry).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_add_scrap_bounty(base: int) -> void:
	if multiplayer.is_server() and base > 0:
		add_scrap_bounty(base)

## Client -> host: spend intent. Marks dirty even on reject so the corrective
## broadcast un-deducts the client's optimistic mirror.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_spend(cost: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	for kind in cost:
		if not (cost[kind] is int) or cost[kind] < 0:
			return
	spend(cost)
	_sync_dirty = true

## Client -> host: research purchase intent (revalidated by purchase()).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_purchase(id: String) -> void:
	if multiplayer.is_server() and UPGRADES.has(id):
		purchase(id)
		_sync_dirty = true

## Host -> clients: full state mirror. Re-emits the local signals so HUD,
## research panel and ghost affordability react exactly as offline.
@rpc("authority", "call_remote", "reliable")
func _rpc_sync_state(res: Dictionary, bought: Dictionary, god: bool) -> void:
	_applying_sync = true
	## godmode flips ride the upgrades signal so the GOD label refreshes.
	var upgrades_differ: bool = bought != purchased or god != godmode
	resources = res
	purchased = bought
	godmode = god
	_applying_sync = false
	if upgrades_differ:
		# Mirror the hotbar slots that unlock research grants on the host.
		for b_id in BUILDINGS:
			var b: Dictionary = BUILDINGS[b_id]
			if is_purchased(b["research"]) and hotbar[b["slot"]] == null:
				hotbar[b["slot"]] = {"id": b_id, "name": b["name"], "icon": b["icon"]}
		hotbar_changed.emit()
		upgrades_changed.emit()
	resources_changed.emit(resources)
