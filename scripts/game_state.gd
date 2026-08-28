extends Node
## Autoload singleton: run-wide state (XP, level, resources, research, hotbar).

signal xp_changed(xp: int, xp_needed: int, level: int)
signal resources_changed(resources: Dictionary)
signal upgrades_changed
signal hotbar_changed

const WORLD_SIZE := Vector2(2560, 1440)
const HOTBAR_SIZE := 11

const UPGRADES := {
	"damage_1": {"icon": "res://assets/icons/blaster.svg", "name": "Sharper Rounds", "branch": "Offense", "desc": "+1 bullet damage", "cost": {"scrap": 50}, "requires": [], "effects": {"damage_bonus": 1.0}},
	"fire_rate_1": {"icon": "res://assets/icons/blaster.svg", "name": "Rapid Fire", "branch": "Offense", "desc": "20% faster firing", "cost": {"scrap": 100}, "requires": ["damage_1"], "effects": {"fire_rate_cut": 0.2}},
	"damage_2": {"icon": "res://assets/icons/blaster.svg", "name": "Heavy Rounds", "branch": "Offense", "desc": "+2 bullet damage", "cost": {"scrap": 150, "crystal": 50}, "requires": ["fire_rate_1"], "effects": {"damage_bonus": 2.0}},
	"damage_3": {"icon": "res://assets/icons/blaster.svg", "name": "Annihilator Rounds", "branch": "Offense", "desc": "+3 bullet damage", "cost": {"scrap": 300, "crystal": 100}, "requires": ["damage_2"], "effects": {"damage_bonus": 3.0}},
	"fire_rate_2": {"icon": "res://assets/icons/blaster.svg", "name": "Overdrive Trigger", "branch": "Offense", "desc": "20% faster firing", "cost": {"scrap": 200, "crystal": 60}, "requires": ["fire_rate_1"], "effects": {"fire_rate_cut": 0.2}},
	"crit_chance_1": {"icon": "res://assets/icons/crit.svg", "name": "Critical Eye", "branch": "Offense", "desc": "+10% crit chance", "cost": {"scrap": 150, "crystal": 40}, "requires": ["damage_1"], "effects": {"crit_chance": 0.1}},
	"crit_chance_2": {"icon": "res://assets/icons/crit.svg", "name": "Predator Instinct", "branch": "Offense", "desc": "+15% crit chance", "cost": {"scrap": 250, "crystal": 80}, "requires": ["crit_chance_1"], "effects": {"crit_chance": 0.15}},
	"crit_damage_1": {"icon": "res://assets/icons/crit.svg", "name": "Deadly Precision", "branch": "Offense", "desc": "+50% crit damage", "cost": {"scrap": 200, "crystal": 60}, "requires": ["crit_chance_1"], "effects": {"crit_mult": 0.5}},
	"crit_damage_2": {"icon": "res://assets/icons/crit.svg", "name": "Executioner", "branch": "Offense", "desc": "+100% crit damage", "cost": {"scrap": 350, "crystal": 120}, "requires": ["crit_damage_1"], "effects": {"crit_mult": 1.0}},
	"speed_1": {"icon": "res://assets/icons/xp.svg", "name": "Thrusters", "branch": "Pilot", "desc": "+15% move speed", "cost": {"scrap": 50}, "requires": [], "effects": {"speed_mult": 0.15}},
	"speed_2": {"icon": "res://assets/icons/xp.svg", "name": "Afterburners", "branch": "Pilot", "desc": "+15% move speed", "cost": {"scrap": 150, "crystal": 40}, "requires": ["speed_1"], "effects": {"speed_mult": 0.15}},
	"hp_1": {"icon": "res://assets/icons/health.svg", "name": "Hull Plating", "branch": "Pilot", "desc": "+25 max health", "cost": {"scrap": 100}, "requires": ["speed_1"], "effects": {"player_hp_bonus": 25.0}},
	"hp_2": {"icon": "res://assets/icons/health.svg", "name": "Composite Armor", "branch": "Pilot", "desc": "+50 max health", "cost": {"scrap": 200, "crystal": 60}, "requires": ["hp_1"], "effects": {"player_hp_bonus": 50.0}},
	"hp_3": {"icon": "res://assets/icons/health.svg", "name": "Fortress Hull", "branch": "Pilot", "desc": "+75 max health", "cost": {"scrap": 400, "crystal": 150}, "requires": ["hp_2"], "effects": {"player_hp_bonus": 75.0}},
	"regen_1": {"icon": "res://assets/icons/health.svg", "name": "Nanobots", "branch": "Pilot", "desc": "Regenerate 2 HP/s", "cost": {"scrap": 150, "crystal": 50}, "requires": ["hp_1"], "effects": {"player_regen": 2.0}},
	"regen_2": {"icon": "res://assets/icons/health.svg", "name": "Nanoswarm", "branch": "Pilot", "desc": "+3 HP/s regen", "cost": {"scrap": 300, "crystal": 100}, "requires": ["regen_1"], "effects": {"player_regen": 3.0}},
	"miner_1": {"icon": "res://assets/icons/miner.svg", "name": "Miner", "branch": "Industry", "desc": "Unlocks the Miner building", "cost": {"scrap": 150}, "requires": [], "effects": {}},
	"walls_1": {"icon": "res://assets/icons/wall.svg", "name": "Walls", "branch": "Industry", "desc": "Unlocks buildable Walls", "cost": {"scrap": 75}, "requires": [], "effects": {}},
	"mg_tower_1": {"icon": "res://assets/icons/mg_tower.svg", "name": "Machine Gun Tower", "branch": "Industry", "desc": "Unlocks the MG Tower", "cost": {"scrap": 150, "crystal": 30}, "requires": ["walls_1"], "effects": {}},
	"grenade_tower_1": {"icon": "res://assets/icons/grenade_tower.svg", "name": "Grenade Tower", "branch": "Industry", "desc": "Unlocks the Grenade Tower", "cost": {"scrap": 200, "crystal": 60}, "requires": ["mg_tower_1"], "effects": {}},
	"repair_tower_1": {"icon": "res://assets/icons/repair_tower.svg", "name": "Repair Beam Tower", "branch": "Industry", "desc": "Unlocks the Repair Tower", "cost": {"scrap": 150, "crystal": 60}, "requires": ["walls_1"], "effects": {}},
	"tesla_tower_1": {"icon": "res://assets/icons/tesla_tower.svg", "name": "Tesla Tower", "branch": "Industry", "desc": "Unlocks the Tesla Tower", "cost": {"scrap": 250, "crystal": 80}, "requires": ["mg_tower_1"], "effects": {}},
	"flame_tower_1": {"icon": "res://assets/icons/flame_tower.svg", "name": "Flamethrower Tower", "branch": "Industry", "desc": "Unlocks the Flamethrower Tower", "cost": {"scrap": 200, "crystal": 60}, "requires": ["walls_1"], "effects": {}},
	"aa_tower_1": {"icon": "res://assets/icons/aa_tower.svg", "name": "AA Flak Cannon", "branch": "Industry", "desc": "Unlocks the anti-air Flak Cannon", "cost": {"scrap": 250, "crystal": 100}, "requires": ["mg_tower_1"], "effects": {}},
	"building_hp_1": {"icon": "res://assets/icons/wall.svg", "name": "Reinforced Structures", "branch": "Engineering", "desc": "+25% building health", "cost": {"scrap": 100}, "requires": ["walls_1"], "effects": {"building_hp_mult": 0.25}},
	"tower_damage_1": {"icon": "res://assets/icons/mg_tower.svg", "name": "Heavy Ordnance", "branch": "Engineering", "desc": "+1 tower damage", "cost": {"scrap": 150, "crystal": 50}, "requires": ["mg_tower_1"], "effects": {"tower_damage": 1.0}},
	"miner_yield_1": {"icon": "res://assets/icons/miner.svg", "name": "Efficient Drills", "branch": "Engineering", "desc": "+1 crystal per mining cycle", "cost": {"scrap": 100, "crystal": 30}, "requires": ["miner_1"], "effects": {"miner_yield": 1.0}},
	"solar_1": {"icon": "res://assets/icons/solar_panel.svg", "name": "Solar Panel", "branch": "Industry", "desc": "Unlocks the Solar Panel", "cost": {"scrap": 50}, "requires": [], "effects": {}},
	"command_center_1": {"icon": "res://assets/icons/command_center.svg", "name": "Command Center", "branch": "Industry", "desc": "Unlocks the Command Center", "cost": {"scrap": 300, "crystal": 100}, "requires": ["miner_1"], "effects": {}},
}

# Per-placement costs, paid directly when the building is placed.
const BUILDINGS := {
	"wall": {"icon": "res://assets/icons/wall.svg", "name": "Wall", "cost": {"scrap": 15}, "research": "walls_1"},
	"mg_tower": {"icon": "res://assets/icons/mg_tower.svg", "name": "MG Tower", "cost": {"scrap": 120, "crystal": 40}, "research": "mg_tower_1"},
	"grenade_tower": {"icon": "res://assets/icons/grenade_tower.svg", "name": "Grenade Tower", "cost": {"scrap": 160, "crystal": 60}, "research": "grenade_tower_1"},
	"repair_tower": {"icon": "res://assets/icons/repair_tower.svg", "name": "Repair Tower", "cost": {"scrap": 120, "crystal": 50}, "research": "repair_tower_1"},
	"tesla_tower": {"icon": "res://assets/icons/tesla_tower.svg", "name": "Tesla Tower", "cost": {"scrap": 140, "crystal": 60}, "research": "tesla_tower_1"},
	"flame_tower": {"icon": "res://assets/icons/flame_tower.svg", "name": "Flamethrower Tower", "cost": {"scrap": 130, "crystal": 50}, "research": "flame_tower_1"},
	"aa_tower": {"icon": "res://assets/icons/aa_tower.svg", "name": "AA Flak Cannon", "cost": {"scrap": 150, "crystal": 70}, "research": "aa_tower_1"},
	"solar_panel": {"icon": "res://assets/icons/solar_panel.svg", "name": "Solar Panel", "cost": {"scrap": 30}, "research": "solar_1"},
	"command_center": {"icon": "res://assets/icons/command_center.svg", "name": "Command Center", "cost": {"scrap": 200, "crystal": 80}, "research": "command_center_1"},
}

var xp: int = 0
var level: int = 1
var resources: Dictionary = {"scrap": 0, "crystal": 0, "energy": 20}
var purchased: Dictionary = {}
var hotbar: Array = []
var selected_slot: int = 0

func _ready() -> void:
	reset()

func reset() -> void:
	xp = 0
	level = 1
	resources = {"scrap": 0, "crystal": 0, "energy": 20}
	purchased = {}
	hotbar = [{"id": "blaster", "name": "Blaster", "icon": "res://assets/icons/blaster.svg"}, null, null, null, null, null, null, null, null, null, null]
	selected_slot = 0
	xp_changed.emit(xp, xp_needed(), level)
	resources_changed.emit(resources)
	upgrades_changed.emit()
	hotbar_changed.emit()

func xp_needed() -> int:
	return 100 * level

func add_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_needed():
		xp -= xp_needed()
		level += 1
	xp_changed.emit(xp, xp_needed(), level)

func add_resource(kind: String, amount: int) -> void:
	resources[kind] = resources.get(kind, 0) + amount
	resources_changed.emit(resources)

## Per-attack energy drain for towers and miners. Returns false (and spends
## nothing) when there isn't enough energy banked.
func try_spend_energy(amount: int) -> bool:
	if resources.get("energy", 0) < amount:
		return false
	resources["energy"] -= amount
	resources_changed.emit(resources)
	return true

func can_afford(cost: Dictionary) -> bool:
	for kind in cost:
		if resources.get(kind, 0) < cost[kind]:
			return false
	return true

func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
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

## Player-stat upgrades (Offense/Pilot) can be bought forever; Industry
## building unlocks are one-time.
func is_repeatable(id: String) -> bool:
	return UPGRADES[id]["branch"] != "Industry"

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
		scaled[kind] = int(ceil(base[kind] * pow(1.6, lvl)))
	# High-level repeatables demand gold, the Harvester-only late-game resource.
	if lvl >= 5:
		scaled["gold"] = int(ceil(15.0 * pow(1.5, lvl - 5)))
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
	spend(upgrade_cost(id))
	purchased[id] = upgrade_level(id) + 1
	match id:
		"miner_1":
			set_hotbar_item(1, {"id": "miner", "name": "Miner", "icon": "res://assets/icons/miner.svg"})
		"walls_1":
			set_hotbar_item(2, {"id": "wall", "name": "Wall", "icon": "res://assets/icons/wall.svg"})
		"mg_tower_1":
			set_hotbar_item(3, {"id": "mg_tower", "name": "MG Tower", "icon": "res://assets/icons/mg_tower.svg"})
		"grenade_tower_1":
			set_hotbar_item(4, {"id": "grenade_tower", "name": "Grenade Tower", "icon": "res://assets/icons/grenade_tower.svg"})
		"repair_tower_1":
			set_hotbar_item(5, {"id": "repair_tower", "name": "Repair Tower", "icon": "res://assets/icons/repair_tower.svg"})
		"tesla_tower_1":
			set_hotbar_item(6, {"id": "tesla_tower", "name": "Tesla Tower", "icon": "res://assets/icons/tesla_tower.svg"})
		"flame_tower_1":
			set_hotbar_item(7, {"id": "flame_tower", "name": "Flamethrower Tower", "icon": "res://assets/icons/flame_tower.svg"})
		"aa_tower_1":
			set_hotbar_item(8, {"id": "aa_tower", "name": "AA Flak Cannon", "icon": "res://assets/icons/aa_tower.svg"})
		"solar_1":
			set_hotbar_item(9, {"id": "solar_panel", "name": "Solar Panel", "icon": "res://assets/icons/solar_panel.svg"})
		"command_center_1":
			set_hotbar_item(10, {"id": "command_center", "name": "Command Center", "icon": "res://assets/icons/command_center.svg"})
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

# Player stats: research effects plus small per-level bonuses.
func player_damage() -> int:
	return 1 + int(stat("damage_bonus")) + int((level - 1) / 4.0)

func player_crit_chance() -> float:
	return minf(0.05 + stat("crit_chance"), 0.8)

func player_crit_mult() -> float:
	return 1.5 + stat("crit_mult")

func player_fire_cooldown(base_cooldown: float) -> float:
	# Diminishing returns so unlimited fire-rate levels never hit zero.
	return maxf(base_cooldown / (1.0 + stat("fire_rate_cut")), 0.04)

func player_speed(base_speed: float) -> float:
	return base_speed * (1.0 + stat("speed_mult") + 0.01 * (level - 1))

func player_max_health() -> int:
	return 100 + int(stat("player_hp_bonus"))

func player_regen() -> float:
	return stat("player_regen")

# Building stats (Engineering research).
func building_hp_mult() -> float:
	return 1.0 + stat("building_hp_mult")

func tower_damage_bonus() -> int:
	return int(stat("tower_damage"))

func miner_yield_bonus() -> int:
	return int(stat("miner_yield"))
