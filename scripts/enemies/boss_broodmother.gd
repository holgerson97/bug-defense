extends "res://scripts/enemy.gd"
## Boss (every 10th wave): slow bruiser that births runners while alive.

const RUNNER_SCENE = preload("res://scenes/enemies/runner.tscn")
const BIRTH_INTERVAL := 6.0
const BIRTH_COUNT := 2

var _birth_timer: float = 0.0

@onready var _health_bar: ProgressBar = $HealthBar

func _ready() -> void:
	super()
	_health_bar.max_value = max_health
	_health_bar.value = health

func _physics_process(delta: float) -> void:
	_health_bar.global_position = global_position + Vector2(-60, -80)
	super(delta)
	if _target == null or not is_instance_valid(_target):
		return
	_birth_timer += delta
	if _birth_timer >= BIRTH_INTERVAL:
		_birth_timer = 0.0
		_birth()

func take_damage(amount) -> void:
	# The broodmother bleeds hard on death: extra bursts around the body.
	if not _dead and health - int(amount) <= 0:
		for i in 4:
			var off := Vector2.from_angle(randf() * TAU) * randf_range(8.0, 32.0)
			Effects.blood_death(self, global_position + off, Vector2.from_angle(randf() * TAU))
	super(amount)
	_health_bar.value = health

func _birth() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	var wm = get_tree().get_first_node_in_group("wave_manager")
	for i in BIRTH_COUNT:
		var runner = RUNNER_SCENE.instantiate()
		var pos: Vector2 = global_position + Vector2.from_angle(randf() * TAU) * 50.0
		runner.global_position = pos.clamp(Vector2(24, 24), GameState.WORLD_SIZE - Vector2(24, 24))
		if wm != null and wm.has_method("register_enemy"):
			wm.register_enemy(runner)
		scene.add_child(runner)
