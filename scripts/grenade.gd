extends Node2D
## Lobbed grenade: travels to a target point over FLIGHT_TIME (fake arc via
## scaling) and explodes, damaging all enemies in a radius.


const FLIGHT_TIME := 0.6

var blast_radius: float = Balance.num("towers/grenade_tower/blast_radius", 90.0)
var blast_damage: int = Balance.inum("towers/grenade_tower/blast_damage", 3)

var target_point: Vector2
## Phase 6 client replay: full arc + explosion FX/sfx, damage skipped.
var cosmetic := false
var _start: Vector2
var _time: float = 0.0

func _ready() -> void:
	_start = global_position

func _physics_process(delta: float) -> void:
	_time += delta
	var t := minf(_time / FLIGHT_TIME, 1.0)
	global_position = _start.lerp(target_point, t)
	var arc := 1.0 + 0.8 * sin(t * PI)
	scale = Vector2(arc, arc)
	if t >= 1.0:
		_explode()

func _explode() -> void:
	if not cosmetic:
		var dmg := GameState.tower_damage_roll(blast_damage)
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy.global_position.distance_to(global_position) <= blast_radius and enemy.has_method("take_damage"):
				enemy.take_damage(dmg)
	Effects.explosion(self, global_position)
	Sfx.play("explosion", global_position, -4.0)
	queue_free()
