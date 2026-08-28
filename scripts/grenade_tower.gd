extends "res://scripts/building.gd"
## Grenade tower: lobs a grenade at a random enemy in range every few seconds.

const FIRE_INTERVAL := 2.5
const FIRE_RANGE := 450.0
const ENERGY_PER_LOB := 2

var grenade_scene: PackedScene = preload("res://scenes/grenade.tscn")
var _fire_accum: float = 0.0

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_fire_accum += delta
	if _fire_accum >= FIRE_INTERVAL:
		_fire_accum = 0.0
		_fire()

func _fire() -> void:
	var candidates: Array = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(global_position) <= FIRE_RANGE:
			candidates.append(enemy)
	if candidates.is_empty():
		return
	if not GameState.try_spend_energy(ENERGY_PER_LOB):
		set_powered(false)
		return
	set_powered(true)
	var target = candidates.pick_random()
	var grenade = grenade_scene.instantiate()
	grenade.global_position = global_position
	grenade.target_point = target.global_position
	get_tree().current_scene.add_child(grenade)
