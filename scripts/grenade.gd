extends Node2D
## Lobbed grenade: travels to a target point over FLIGHT_TIME (fake arc via
## scaling) and explodes, damaging all enemies in a radius.


const FLIGHT_TIME := 0.6
const BLAST_RADIUS := 90.0
const BLAST_DAMAGE := 3

var target_point: Vector2
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
	var blast_damage := GameState.tower_damage_roll(BLAST_DAMAGE)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(global_position) <= BLAST_RADIUS and enemy.has_method("take_damage"):
			enemy.take_damage(blast_damage)
	Effects.explosion(self, global_position)
	Sfx.play("explosion", global_position, -4.0)
	queue_free()
