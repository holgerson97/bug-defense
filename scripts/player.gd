extends CharacterBody2D
## The space marine: movement, aiming, shooting and health. Building
## placement lives in the BuildController child node. In multiplayer one
## instance exists per peer (node name = peer id); only the authority runs
## input and camera, everyone else renders a synced puppet.

signal died

@export var base_speed: float = 320.0
@export var base_fire_rate: float = 0.15

const RECOIL_KICK := 5.0
const RECOIL_MAX := 14.0
const RECOIL_RECOVER := 14.0
var auto_attack_range: float = Balance.num("player/auto_attack_range", 250.0)
## Physics layer 6 ("buildings") as a bit value; Phase Stride masks it out.
const BUILDING_LAYER_BIT := 32
## Heal beam (hold F): mends the most damaged building in range every tick.
var heal_beam_range: float = Balance.num("player/heal_beam/range", 140.0)
var heal_tick: float = Balance.num("player/heal_beam/tick", 0.5)
var heal_base: int = Balance.inum("player/heal_beam/heal", 3)
var heal_energy: int = Balance.inum("player/heal_beam/energy", 1)
## Suit reactor: passive 6/s baseline — sustains roughly two turrets.
var reactor_interval: float = Balance.num("player/reactor/interval", 2.0)
var reactor_amount: float = Balance.num("player/reactor/amount", 12.0)

var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
## Replicated by the MultiplayerSynchronizer; setters also run on puppets.
var health: int = 0: set = _set_health
var dead: bool = false: set = _set_dead
var _max_health: int
var _fire_cooldown: float = 0.0
var _regen_accum: float = 0.0
var _recoil: Vector2 = Vector2.ZERO
var _auto_attack: bool = false
## Starts full so the first heal tick lands the moment F is pressed.
var _heal_accum: float = heal_tick
var _heal_target: Node2D = null
var _heal_beam: Line2D
var _reactor_accum: float = 0.0
## Fractional energy owed by the reactor once output multipliers land.
var _reactor_carry: float = 0.0
var _auto_label: Label
var _god_label: Label
var _name_label: Label
var _base_light_radius: float
## Spectate (online death): the hidden player node glides after a living
## teammate so the local camera simply follows; wheel cycles targets.
var _spectate_target: Node2D = null

@onready var _health_bar: ProgressBar = $HealthBar
@onready var _camera: Camera2D = $Camera2D
@onready var _build = $BuildController
@onready var _light = $LightSource

## Spawned players are named by peer id; that peer owns the node's input.
func _enter_tree() -> void:
	var id := str(name).to_int()
	if id > 0:
		set_multiplayer_authority(id)

func _ready() -> void:
	GameState.upgrades_changed.connect(_on_upgrades_changed)
	base_speed = Balance.num("player/speed", base_speed)
	base_fire_rate = Balance.num("player/fire_cooldown", base_fire_rate)
	_max_health = GameState.player_max_health()
	_base_light_radius = Balance.num("player/light_radius", _light.radius)
	_apply_light_radius()
	_apply_building_walk()
	_camera.enabled = is_multiplayer_authority()
	_apply_identity()
	if not is_multiplayer_authority():
		## Puppet: no input, no build ghost tick, no hunt arrows.
		$EnemyArrows.set_physics_process(false)
		_update_health_bar()
		return
	health = _max_health
	## Heal beam visual: repair-tower style, drawn in global space (top_level)
	## so it tracks target and player without inheriting body rotation.
	_heal_beam = Line2D.new()
	_heal_beam.top_level = true
	_heal_beam.z_index = 50
	_heal_beam.width = 3.0
	_heal_beam.default_color = Color(0.35, 1, 0.55, 0.85)
	_heal_beam.visible = false
	add_child(_heal_beam)
	_auto_label = Label.new()
	_auto_label.text = "AUTO"
	_auto_label.top_level = true
	_auto_label.z_index = 60
	_auto_label.visible = false
	_auto_label.add_theme_font_size_override("font_size", 10)
	_auto_label.add_theme_color_override("font_color", UITheme.ACCENT)
	add_child(_auto_label)
	_god_label = Label.new()
	_god_label.text = "GOD"
	_god_label.top_level = true
	_god_label.z_index = 60
	_god_label.visible = GameState.godmode
	_god_label.add_theme_font_size_override("font_size", 10)
	_god_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	add_child(_god_label)

## Online identity: tint the body toward the registry color; puppets also get
## a small dim name tag so teammates are tellable apart.
func _apply_identity() -> void:
	var info: Dictionary = Net.players.get(get_multiplayer_authority(), {})
	if info.is_empty():
		return
	var color: Color = info["color"]
	$Body.modulate = Color.WHITE.lerp(color, 0.4)
	if is_multiplayer_authority():
		return
	_name_label = Label.new()
	_name_label.text = info["name"]
	_name_label.top_level = true
	_name_label.z_index = 60
	_name_label.add_theme_font_size_override("font_size", 10)
	_name_label.add_theme_color_override("font_color", Color(color, 0.75))
	add_child(_name_label)

func _physics_process(delta: float) -> void:
	_health_bar.global_position = global_position + Vector2(-22, -40)
	## Puppet: transform/health arrive via the synchronizer; only track labels.
	if not is_multiplayer_authority():
		if _name_label != null:
			_name_label.global_position = global_position + Vector2(-_name_label.size.x / 2.0, -58)
		return

	# Camera recoil eases back to zero; offset doesn't fight position smoothing.
	_recoil *= exp(-RECOIL_RECOVER * delta)
	if _recoil.length_squared() < 0.01:
		_recoil = Vector2.ZERO
	_camera.offset = _recoil

	if dead:
		_spectate_tick(delta)
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_dir * GameState.player_speed(base_speed)
	move_and_slide()
	# Space toggles auto-attack: aim and fire at the closest enemy in sight.
	if Input.is_action_just_pressed("auto_attack"):
		_auto_attack = not _auto_attack
		_auto_label.visible = _auto_attack
	_auto_label.global_position = global_position + Vector2(26, -46)
	# G toggles godmode: no damage taken and all costs are free while active.
	if Input.is_action_just_pressed("godmode"):
		GameState.godmode = not GameState.godmode
		_god_label.visible = GameState.godmode
	_god_label.global_position = global_position + Vector2(26, -58)
	var auto_target = null
	if _auto_attack:
		# Terrain LOS like towers: never aim at enemies behind rock/ore.
		auto_target = Util.nearest_visible_in_group(self, "enemies", global_position, auto_attack_range)
	if auto_target != null:
		look_at(auto_target.global_position)
	else:
		var mouse := get_global_mouse_position()
		if global_position.distance_squared_to(mouse) > 16.0:
			look_at(mouse)

	var regen := GameState.player_regen()
	if regen > 0.0 and health < _max_health:
		_regen_accum += regen * delta
		if _regen_accum >= 1.0:
			var heal := int(_regen_accum)
			_regen_accum -= heal
			health = mini(health + heal, _max_health)

	_fire_cooldown -= delta
	var selected := GameState.selected_item_id()
	# Auto-attack fires the blaster regardless of the selected hotbar slot.
	var firing := auto_target != null or (selected == "blaster" and Input.is_action_pressed("shoot"))
	if firing and _fire_cooldown <= 0.0:
		_shoot()
		_fire_cooldown = GameState.player_fire_cooldown(base_fire_rate)

	## Suit reactor: passive energy through the normal path so it shows in the
	## HUD production rate; carry banks fractional output from multipliers.
	_reactor_accum += delta
	if _reactor_accum >= reactor_interval:
		_reactor_accum -= reactor_interval
		_reactor_carry += reactor_amount * GameState.player_power_mult()
		var whole := int(_reactor_carry)
		_reactor_carry -= whole
		GameState.add_resource("energy", whole)

	## Heal beam: hold F, tick every 0.5s; each tick re-picks the most damaged
	## building in range and spends energy (godmode-aware via try_spend_energy).
	if Input.is_action_pressed("heal_beam"):
		_heal_accum += delta
		if _heal_accum >= heal_tick:
			_heal_accum = 0.0
			_heal_target = _pick_heal_target()
			if _heal_target != null and not GameState.try_spend_energy(heal_energy):
				_heal_target = null
			if _heal_target != null:
				## request_heal routes to the host online (heal() itself
				## no-ops on clients — building HP is host-owned, Phase 4).
				_heal_target.request_heal(heal_base + GameState.player_heal_bonus())
	else:
		_heal_accum = heal_tick
		_heal_target = null
	_update_heal_beam()
	_build.tick(selected)

## Most-damaged building in beam range (repair tower pick, minus player heal).
func _pick_heal_target():
	var reach := heal_beam_range * GameState.player_heal_range_mult()
	var best = null
	var best_missing := 0
	for building in get_tree().get_nodes_in_group("buildings"):
		if building.global_position.distance_to(global_position) > reach:
			continue
		var missing: int = building.max_health - building.health
		if missing > best_missing:
			best_missing = missing
			best = building
	return best

## Beam tracks player and target every frame; hidden when there is no live
## target (no building in range, no energy, or F released).
func _update_heal_beam() -> void:
	if _heal_target == null or not is_instance_valid(_heal_target):
		_heal_target = null
		_heal_beam.visible = false
		return
	_heal_beam.points = PackedVector2Array([global_position, _heal_target.global_position])
	_heal_beam.visible = true

## Enemies are host-simulated puppets on clients (Phase 5), so client shots
## can't land locally: online clients send a fire intent to the host (which
## spawns the authoritative bullet) and keep a cosmetic tracer for feel.
func _shoot() -> void:
	var dmg := GameState.player_damage()
	var crit := randf() < GameState.player_crit_chance()
	if crit:
		dmg = int(ceil(dmg * GameState.player_crit_mult()))
	if Net.is_online() and not Net.is_host():
		_rpc_fire.rpc_id(1, $Muzzle.global_position, rotation, dmg, crit)
		_spawn_bullet($Muzzle.global_position, rotation, 0, crit, true)
	else:
		_spawn_bullet($Muzzle.global_position, rotation, dmg, crit, false)
		## Phase 6: the host's own shots replay on every client.
		FxEvents.player_fire(self, $Muzzle.global_position, rotation, crit)
	Effects.muzzle_flash(self, $Muzzle.global_position, rotation)
	Sfx.play("shoot_player", $Muzzle.global_position, -6.0)
	_recoil = (_recoil - transform.x * RECOIL_KICK).limit_length(RECOIL_MAX)

func _spawn_bullet(pos: Vector2, rot: float, dmg: int, crit: bool, cosmetic: bool) -> void:
	var bullet = bullet_scene.instantiate()
	bullet.global_position = pos
	bullet.rotation = rot
	bullet.damage = dmg
	bullet.crit = crit
	if cosmetic:
		## Tracer flies through (collision-less puppet) enemies; walls/rocks
		## still stop it so the visual reads right.
		bullet.collision_mask &= ~2
	get_tree().current_scene.add_child(bullet)

## Client -> host: fire intent. The host trusts aim (client-authoritative
## movement anyway) but clamps damage against the shared-research ceiling.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_fire(pos: Vector2, rot: float, dmg: int, crit: bool) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	var cap := int(ceil(GameState.player_damage() * maxf(GameState.player_crit_mult(), 1.0)))
	_spawn_bullet(pos, rot, clampi(dmg, 1, cap), crit, false)
	## Phase 6: the shooter already played its own flash/tracer — the host
	## renders the remote shot locally and relays it to the other clients.
	Effects.muzzle_flash(self, pos, rot)
	Sfx.play("shoot_player", pos, -6.0)
	FxEvents.player_fire(self, pos, rot, crit, multiplayer.get_remote_sender_id())

## Phase 5: enemies live on the host, so their melee lands on player puppets
## THERE — but health is authority-owned (Phase 2 sync). The host forwards the
## hit to the owning peer; that peer applies it and the synchronizer mirrors
## it back. Offline and the host's own player keep the direct path.
func take_damage(amount: int) -> void:
	if Net.is_online() and Net.is_host() and not is_multiplayer_authority():
		## Registry check: a disconnected peer's puppet lingers until Phase 7
		## handles despawn — don't RPC into the void.
		if Net.players.has(get_multiplayer_authority()):
			_rpc_take_damage.rpc_id(get_multiplayer_authority(), amount)
		return
	if not is_multiplayer_authority() or dead or GameState.godmode:
		return
	_apply_damage(amount)

func _apply_damage(amount: int) -> void:
	Sfx.play("player_hurt", global_position, -3.0)
	health = maxi(health - amount, 0)
	if health == 0:
		dead = true

## Host -> owning peer: enemy damage. Only the host may send it.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_take_damage(amount: int) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_multiplayer_authority():
		return
	if dead or GameState.godmode:
		return
	_apply_damage(clampi(amount, 0, 1000))

func heal(amount: int) -> void:
	if not is_multiplayer_authority() or dead or health >= _max_health:
		return
	health = mini(health + amount, _max_health)

func max_health() -> int:
	return _max_health

func _set_health(value: int) -> void:
	health = value
	if _health_bar != null:
		_update_health_bar()

func _set_dead(value: bool) -> void:
	if dead == value:
		return
	dead = value
	if dead:
		_apply_death()
	else:
		_apply_revive()

## Offline death keeps today's flow: `died` -> main.gd game over. Online the
## player goes dark and inert and the local peer spectates a living teammate
## until the host revives everyone at the next intermission (Phase 7).
func _apply_death() -> void:
	if _heal_beam != null:
		_heal_beam.visible = false
	if Net.is_online():
		visible = false
		remove_from_group("player")
		$CollisionShape2D.set_deferred("disabled", true)
		_health_bar.visible = false
		if is_multiplayer_authority():
			_pick_spectate_target(0)
	died.emit()

## Runs on every peer via the synced dead flag: undo _apply_death.
func _apply_revive() -> void:
	visible = true
	if not is_in_group("player"):
		add_to_group("player")
	$CollisionShape2D.set_deferred("disabled", false)
	_health_bar.visible = true
	if is_multiplayer_authority():
		_spectate_target = null
		if _god_label != null:
			_god_label.visible = GameState.godmode
		var hud := _hud()
		if hud != null:
			hud.hide_spectate()

## Host: revive a dead player at `pos` — own player directly, remote players
## via RPC to the owning peer (health/dead/position sync mirrors it back).
func revive_at(pos: Vector2) -> void:
	if is_multiplayer_authority():
		_do_revive(pos)
	elif Net.players.has(get_multiplayer_authority()):
		_rpc_revive.rpc_id(get_multiplayer_authority(), pos)

## Host -> owning peer: intermission respawn. Only the host may send it.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_revive(pos: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_multiplayer_authority():
		return
	_do_revive(pos)

func _do_revive(pos: Vector2) -> void:
	if not dead:
		return
	global_position = pos
	health = _max_health
	dead = false

## -- spectate (authority peer, while dead online) --

func _hud() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("HUD") if scene != null else null

func _living_players() -> Array:
	var out := []
	for p in get_tree().get_nodes_in_group("player"):
		if p != self and not p.is_queued_for_deletion():
			out.append(p)
	return out

func _pick_spectate_target(step: int) -> void:
	var living := _living_players()
	if living.is_empty():
		_spectate_target = null
		return
	var idx := maxi(living.find(_spectate_target), 0)
	_spectate_target = living[wrapi(idx + step, 0, living.size())]
	var hud := _hud()
	if hud != null:
		var info: Dictionary = Net.players.get(_spectate_target.get_multiplayer_authority(), {})
		hud.show_spectate(info.get("name", "teammate"))

## Glide the (hidden) node after the followed teammate; the smoothed camera
## child does the rest. Leavers/dead targets re-pick automatically.
func _spectate_tick(delta: float) -> void:
	if not Net.is_online():
		return
	if _spectate_target == null or not is_instance_valid(_spectate_target) \
			or not _spectate_target.is_in_group("player"):
		_pick_spectate_target(0)
	if _spectate_target != null:
		global_position = global_position.lerp(_spectate_target.global_position, 1.0 - exp(-6.0 * delta))

## While dead the wheel cycles spectate targets instead of hotbar slots
## (_input runs before the hotbar's _unhandled_input; consume the event).
func _input(event: InputEvent) -> void:
	if not dead or not Net.is_online() or not is_multiplayer_authority():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_pick_spectate_target(-1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_pick_spectate_target(1)
			get_viewport().set_input_as_handled()

func _update_health_bar() -> void:
	_health_bar.max_value = _max_health
	_health_bar.value = health

func _on_upgrades_changed() -> void:
	var new_max := GameState.player_max_health()
	if new_max != _max_health:
		var gained := maxi(new_max - _max_health, 0)
		_max_health = new_max
		if is_multiplayer_authority():
			health = mini(health + gained, _max_health)
		_update_health_bar()
	_apply_light_radius()
	_apply_building_walk()
	## Phase 3 cosmetic gap: a client's GOD label now refreshes on host sync
	## (game_state emits upgrades_changed when the synced godmode flips).
	if _god_label != null:
		_god_label.visible = GameState.godmode

## Phase Stride research: drop the buildings bit from the collision mask so the
## player walks over structures; restored when unowned (fresh run after reset).
func _apply_building_walk() -> void:
	if GameState.is_purchased("building_walk"):
		collision_mask &= ~BUILDING_LAYER_BIT
	else:
		collision_mask |= BUILDING_LAYER_BIT

## Headlamp research: scale the light pool and its texture from the base radius.
func _apply_light_radius() -> void:
	_light.radius = _base_light_radius * GameState.player_light_mult()
	_light.texture_scale = _light.radius * 2.0 / _light.TEXTURE_SIZE
