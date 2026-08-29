extends SceneTree
var frames := 0
var count := 350
var main
var samples: Array = []
var last_pframe := 0

func _initialize() -> void:
	count = int(OS.get_environment("STRESS_N"))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 60:
		var player = get_first_node_in_group("player")
		if player == null:
			print("RESULT n=%d FAILED no player" % count)
			return true
		root.get_node("/root/GameState").godmode = true
		var enemy_scene = load("res://scenes/enemy.tscn")
		for i in count:
			var e = enemy_scene.instantiate()
			e.global_position = player.global_position + Vector2.from_angle(TAU * i / maxi(count, 1)) * randf_range(400.0, 1400.0)
			main.add_child(e)
	if frames > 120 and samples.size() < 180:
		var pf := Engine.get_physics_frames()
		if pf != last_pframe:
			last_pframe = pf
			samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
	if samples.size() >= 180:
		samples.sort()
		var total := 0.0
		for s in samples:
			total += s
		print("RESULT n=%d alive=%d avg_physics_ms=%.2f p90=%.2f" % [count, get_nodes_in_group("enemies").size(), total / samples.size() * 1000.0, samples[int(samples.size() * 0.9)] * 1000.0])
		return true
	return false
