extends StaticBody2D
## Shared base for placeable buildings: health bar, enemy gnaw damage,
## healing, and a debris burst on destruction. Towers extend this script.

const Effects = preload("res://scripts/effects.gd")

const GNAW_DPS := 4.0

@export var max_health: int = 60
@export var health_bar_offset: Vector2 = Vector2(-18, -30)

var health: int
var _gnaw_accum: float = 0.0
var _destroyed: bool = false

@onready var _health_bar: ProgressBar = $HealthBar
@onready var _sense: Area2D = $Sense

func _ready() -> void:
	max_health = int(ceil(max_health * GameState.building_hp_mult()))
	health = max_health
	_update_health_bar()

func _physics_process(delta: float) -> void:
	_health_bar.global_position = global_position + health_bar_offset
	# Each touching enemy gnaws GNAW_DPS HP per second.
	var gnawers := 0
	for body in _sense.get_overlapping_bodies():
		if body.is_in_group("enemies"):
			gnawers += 1
	if gnawers > 0:
		_gnaw_accum += gnawers * GNAW_DPS * delta
		if _gnaw_accum >= 1.0:
			var dmg := int(_gnaw_accum)
			_gnaw_accum -= dmg
			take_damage(dmg)

func take_damage(amount: int) -> void:
	if _destroyed:
		return
	health = maxi(health - amount, 0)
	_update_health_bar()
	if health == 0:
		_destroyed = true
		Effects.debris_burst(self, global_position)
		Sfx.play("explosion", global_position, -8.0)
		queue_free()

func heal(amount: int) -> void:
	if _destroyed:
		return
	health = mini(health + amount, max_health)
	_update_health_bar()

func _update_health_bar() -> void:
	_health_bar.max_value = max_health
	_health_bar.value = health
	_health_bar.visible = health < max_health
