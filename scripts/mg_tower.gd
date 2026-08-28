extends "res://scripts/building.gd"
## Machine gun tower: re-targets the nearest enemy every shot and fires
## a standard bullet from the rotating head's muzzle.

const FIRE_INTERVAL := 0.35
const ENERGY_PER_SHOT := 1

var fire_range: float = GameState.BUILDINGS["mg_tower"]["range"]

var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
var _fire_accum: float = 0.0
var _target

@onready var _head: Node2D = $Head
@onready var _muzzle: Marker2D = $Head/Muzzle

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _target != null and is_instance_valid(_target):
		_head.rotation = (_target.global_position - global_position).angle()
	else:
		_target = null
	_fire_accum += delta
	if _fire_accum >= GameState.tower_interval(FIRE_INTERVAL):
		_fire_accum = 0.0
		_target = Util.nearest_in_group(self, "enemies", global_position, fire_range, [], true)
		if _target != null:
			if GameState.try_spend_energy(ENERGY_PER_SHOT):
				set_powered(true)
				_head.rotation = (_target.global_position - global_position).angle()
				_fire()
			else:
				set_powered(false)

func _fire() -> void:
	var bullet = bullet_scene.instantiate()
	bullet.global_position = _muzzle.global_position
	bullet.rotation = _head.global_rotation
	var dmg := 1 + GameState.tower_damage_bonus()
	if randf() < GameState.tower_crit_chance():
		dmg = int(ceil(dmg * GameState.tower_crit_mult()))
		bullet.crit = true
	bullet.damage = dmg
	# Tower bullets fly over deposits (mask without 16) — otherwise an ore
	# block in the firing line eats shots and mints free crystal.
	bullet.collision_mask = 2 | 64
	get_tree().current_scene.add_child(bullet)
	Effects.muzzle_flash(self, _muzzle.global_position, _head.global_rotation)
	Sfx.play("shoot", _muzzle.global_position, -12.0)
