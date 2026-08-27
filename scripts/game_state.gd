extends Node
## Autoload singleton: run-wide state (XP, level, resources, research, hotbar).

signal xp_changed(xp: int, xp_needed: int, level: int)
signal resources_changed(resources: Dictionary)
signal upgrades_changed
signal hotbar_changed
signal inventory_changed

const WORLD_SIZE := Vector2(2560, 1440)
const HOTBAR_SIZE := 6

const UPGRADES := {
	"damage_1": {"name": "Sharper Rounds", "branch": "Offense", "desc": "+1 bullet damage", "cost": {"scrap": 50}, "requires": [], "effects": {"damage_bonus": 1.0}},
	"fire_rate_1": {"name": "Rapid Fire", "branch": "Offense", "desc": "20% faster firing", "cost": {"scrap": 100}, "requires": ["damage_1"], "effects": {"fire_rate_cut": 0.2}},
	"damage_2": {"name": "Heavy Rounds", "branch": "Offense", "desc": "+2 bullet damage", "cost": {"scrap": 150, "crystal": 50}, "requires": ["fire_rate_1"], "effects": {"damage_bonus": 2.0}},
	"damage_3": {"name": "Annihilator Rounds", "branch": "Offense", "desc": "+3 bullet damage", "cost": {"scrap": 300, "crystal": 100}, "requires": ["damage_2"], "effects": {"damage_bonus": 3.0}},
	"fire_rate_2": {"name": "Overdrive Trigger", "branch": "Offense", "desc": "20% faster firing", "cost": {"scrap": 200, "crystal": 60}, "requires": ["fire_rate_1"], "effects": {"fire_rate_cut": 0.2}},
	"crit_chance_1": {"name": "Critical Eye", "branch": "Offense", "desc": "+10% crit chance", "cost": {"scrap": 150, "crystal": 40}, "requires": ["damage_1"], "effects": {"crit_chance": 0.1}},
	"crit_chance_2": {"name": "Predator Instinct", "branch": "Offense", "desc": "+15% crit chance", "cost": {"scrap": 250, "crystal": 80}, "requires": ["crit_chance_1"], "effects": {"crit_chance": 0.15}},
	"crit_damage_1": {"name": "Deadly Precision", "branch": "Offense", "desc": "+50% crit damage", "cost": {"scrap": 200, "crystal": 60}, "requires": ["crit_chance_1"], "effects": {"crit_mult": 0.5}},
	"crit_damage_2": {"name": "Executioner", "branch": "Offense", "desc": "+100% crit damage", "cost": {"scrap": 350, "crystal": 120}, "requires": ["crit_damage_1"], "effects": {"crit_mult": 1.0}},
	"speed_1": {"name": "Thrusters", "branch": "Pilot", "desc": "+15% move speed", "cost": {"scrap": 50}, "requires": [], "effects": {"speed_mult": 0.15}},
	"speed_2": {"name": "Afterburners", "branch": "Pilot", "desc": "+15% move speed", "cost": {"scrap": 150, "crystal": 40}, "requires": ["speed_1"], "effects": {"speed_mult": 0.15}},
	"hp_1": {"name": "Hull Plating", "branch": "Pilot", "desc": "+25 max health", "cost": {"scrap": 100}, "requires": ["speed_1"], "effects": {"player_hp_bonus": 25.0}},
	"hp_2": {"name": "Composite Armor", "branch": "Pilot", "desc": "+50 max health", "cost": {"scrap": 200, "crystal": 60}, "requires": ["hp_1"], "effects": {"player_hp_bonus": 50.0}},
	"hp_3": {"name": "Fortress Hull", "branch": "Pilot", "desc": "+75 max health", "cost": {"scrap": 400, "crystal": 150}, "requires": ["hp_2"], "effects": {"player_hp_bonus": 75.0}},
	"regen_1": {"name": "Nanobots", "branch": "Pilot", "desc": "Regenerate 2 HP/s", "cost": {"scrap": 150, "crystal": 50}, "requires": ["hp_1"], "effects": {"player_regen": 2.0}},
	"regen_2": {"name": "Nanoswarm", "branch": "Pilot", "desc": "+3 HP/s regen", "cost": {"scrap": 300, "crystal": 100}, "requires": ["regen_1"], "effects": {"player_regen": 3.0}},
	"miner_1": {"name": "Miner", "branch": "Industry", "desc": "Unlocks the Miner building", "cost": {"scrap": 150}, "requires": [], "effects": {}},
	"walls_1": {"name": "Walls", "branch": "Industry", "desc": "Unlocks buildable Walls", "cost": {"scrap": 75}, "requires": [], "effects": {}},
	"mg_tower_1": {"name": "Machine Gun Tower", "branch": "Industry", "desc": "Unlocks the MG Tower", "cost": {"scrap": 150, "crystal": 30}, "requires": ["walls_1"], "effects": {}},
	"grenade_tower_1": {"name": "Grenade Tower", "branch": "Industry", "desc": "Unlocks the Grenade Tower", "cost": {"scrap": 200, "crystal": 60}, "requires": ["mg_tower_1"], "effects": {}},
	"repair_tower_1": {"name": "Repair Beam Tower", "branch": "Industry", "desc": "Unlocks the Repair Tower", "cost": {"scrap": 150, "crystal": 60}, "requires": ["walls_1"], "effects": {}},
}

const BUILDINGS := {
	"wall": {"name": "Wall", "cost": {"scrap": 40}, "pack": 5, "research": "walls_1"},
	"mg_tower": {"name": "MG Tower", "cost": {"scrap": 60, "crystal": 15}, "pack": 1, "research": "mg_tower_1"},
	"grenade_tower": {"name": "Grenade Tower", "cost": {"scrap": 80, "crystal": 25}, "pack": 1, "research": "grenade_tower_1"},
	"repair_tower": {"name": "Repair Tower", "cost": {"scrap": 60, "crystal": 20}, "pack": 1, "research": "repair_tower_1"},
}

var xp: int = 0
var level: int = 1
var resources: Dictionary = {"scrap": 0, "crystal": 0}
var purchased: Dictionary = {}
var hotbar: Array = []
var selected_slot: int = 0
var inventory: Dictionary = {}

func _ready() -> void:
	reset()

func reset() -> void:
	xp = 0
	level = 1
	resources = {"scrap": 0, "crystal": 0}
	purchased = {}
	hotbar = [{"id": "blaster", "name": "Blaster"}, null, null, null, null, null]
	selected_slot = 0
	inventory = {}
	xp_changed.emit(xp, xp_needed(), level)
	resources_changed.emit(resources)
	upgrades_changed.emit()
	hotbar_changed.emit()
	inventory_changed.emit()

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

func is_purchased(id: String) -> bool:
	return purchased.has(id)

func is_unlocked(id: String) -> bool:
	for req in UPGRADES[id]["requires"]:
		if not is_purchased(req):
			return false
	return true

func can_purchase(id: String) -> bool:
	return not is_purchased(id) and is_unlocked(id) and can_afford(UPGRADES[id]["cost"])

func purchase(id: String) -> bool:
	if not can_purchase(id):
		return false
	spend(UPGRADES[id]["cost"])
	purchased[id] = true
	match id:
		"miner_1":
			set_hotbar_item(1, {"id": "miner", "name": "Miner"})
		"walls_1":
			set_hotbar_item(2, {"id": "wall", "name": "Wall"})
		"mg_tower_1":
			set_hotbar_item(3, {"id": "mg_tower", "name": "MG Tower"})
		"grenade_tower_1":
			set_hotbar_item(4, {"id": "grenade_tower", "name": "Grenade Tower"})
		"repair_tower_1":
			set_hotbar_item(5, {"id": "repair_tower", "name": "Repair Tower"})
	upgrades_changed.emit()
	return true

func can_buy_building(id: String) -> bool:
	var building: Dictionary = BUILDINGS[id]
	return is_purchased(building["research"]) and can_afford(building["cost"])

func buy_building(id: String) -> bool:
	if not can_buy_building(id):
		return false
	spend(BUILDINGS[id]["cost"])
	inventory[id] = inventory.get(id, 0) + BUILDINGS[id]["pack"]
	inventory_changed.emit()
	return true

## Consume one building from the inventory (returns false if none left).
func use_building(id: String) -> bool:
	if inventory.get(id, 0) <= 0:
		return false
	inventory[id] -= 1
	inventory_changed.emit()
	return true

## Sum of one effect key across all purchased upgrades.
func stat(key: String) -> float:
	var total := 0.0
	for id in purchased:
		var effects: Dictionary = UPGRADES[id]["effects"]
		if effects.has(key):
			total += effects[key]
	return total

# Player stats: research effects plus small per-level bonuses.
func player_damage() -> int:
	return 1 + int(stat("damage_bonus")) + int((level - 1) / 4.0)

func player_crit_chance() -> float:
	return 0.05 + stat("crit_chance")

func player_crit_mult() -> float:
	return 1.5 + stat("crit_mult")

func player_fire_cooldown(base_cooldown: float) -> float:
	return maxf(base_cooldown * (1.0 - stat("fire_rate_cut")), 0.05)

func player_speed(base_speed: float) -> float:
	return base_speed * (1.0 + stat("speed_mult") + 0.01 * (level - 1))

func player_max_health() -> int:
	return 100 + int(stat("player_hp_bonus"))

func player_regen() -> float:
	return stat("player_regen")
