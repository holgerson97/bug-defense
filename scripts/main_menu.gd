extends Control

@onready var _menu: VBoxContainer = $UI/Root/Center/Menu
@onready var _new_game: VBoxContainer = $UI/Root/Center/NewGameMenu
@onready var _settings: VBoxContainer = $UI/Root/Center/SettingsMenu
@onready var _lobby: VBoxContainer = $UI/Root/Center/LobbyMenu
@onready var _lobby_status: Label = $UI/Root/Center/LobbyMenu/Status
@onready var _host_button: Button = $UI/Root/Center/LobbyMenu/HostButton
@onready var _ip: LineEdit = $UI/Root/Center/LobbyMenu/JoinRow/Ip
@onready var _join_button: Button = $UI/Root/Center/LobbyMenu/JoinRow/JoinButton
@onready var _player_list: VBoxContainer = $UI/Root/Center/LobbyMenu/PlayerList
@onready var _start_button: Button = $UI/Root/Center/LobbyMenu/StartButton
@onready var _fullscreen: CheckButton = $UI/Root/Center/SettingsMenu/Fullscreen
@onready var _vsync: CheckButton = $UI/Root/Center/SettingsMenu/Vsync
@onready var _resolution: OptionButton = $UI/Root/Center/SettingsMenu/ResolutionRow/Resolution
@onready var _volume: HSlider = $UI/Root/Center/SettingsMenu/VolumeRow/Volume
@onready var _sfx_volume: HSlider = $UI/Root/Center/SettingsMenu/SfxRow/SfxVolume
@onready var _mute: CheckButton = $UI/Root/Center/SettingsMenu/Mute

## Class picker widgets (built in code; classes are data-driven from balance).
var _class_buttons: Dictionary = {}
var _class_card: PanelContainer
var _card_sprite: TextureRect
var _card_weapon: Label
var _card_stats: Label
var _lobby_class: OptionButton
var _lobby_class_desc: Label
## World picker widgets (same pattern; worlds are data-driven from balance).
## Empty WORLDS section = no pickers at all (midnight fallback everywhere).
var _world_buttons: Dictionary = {}
var _world_desc: Label
var _lobby_world: OptionButton
## True once a Play/Start transition began (blocks double presses).
var _leaving := false

func _ready() -> void:
	theme = UITheme.build()
	## The menus live in a CanvasLayer (above the diorama, immune to its
	## CanvasModulate); themes don't cross CanvasLayer, so re-root it there.
	$UI/Root.theme = UITheme.build()
	_build_vignette()
	_build_class_picker()
	_build_lobby_class_row()
	_build_world_picker()
	_build_lobby_world_row()
	_sync_class_ui()
	_sync_world_ui()
	## Play opens the NEW GAME setup view (class/world pickers + Start);
	## the run itself launches from that view's Start button.
	$UI/Root/Center/Menu/Play.pressed.connect(_show_new_game.bind(true))
	$UI/Root/Center/NewGameMenu/Start.pressed.connect(_on_start_run)
	$UI/Root/Center/NewGameMenu/NewGameBack.pressed.connect(_show_new_game.bind(false))
	$UI/Root/Center/Menu/Coop.pressed.connect(_show_lobby.bind(true))
	$UI/Root/Center/Menu/SettingsButton.pressed.connect(_show_settings.bind(true))
	$UI/Root/Center/Menu/Quit.pressed.connect(func(): get_tree().quit())
	$UI/Root/Center/SettingsMenu/Back.pressed.connect(_show_settings.bind(false))
	_host_button.pressed.connect(_on_host)
	_join_button.pressed.connect(_on_join)
	_start_button.pressed.connect(_on_start_game)
	$UI/Root/Center/LobbyMenu/LobbyBack.pressed.connect(_on_lobby_back)
	Net.player_list_changed.connect(_refresh_lobby)
	Net.session_ended.connect(_on_session_ended)
	## Late join (Phase 7): joining a running game parks us here until the
	## host's next intermission; Net drives the status line.
	Net.late_join_status.connect(func(message: String): _lobby_status.text = message)
	for res in Settings.RESOLUTIONS:
		_resolution.add_item("%d x %d" % [res.x, res.y])
	_fullscreen.toggled.connect(_on_fullscreen)
	_vsync.toggled.connect(_on_vsync)
	_resolution.item_selected.connect(_on_resolution)
	_volume.value_changed.connect(_on_volume)
	_sfx_volume.value_changed.connect(_on_sfx_volume)
	_mute.toggled.connect(_on_mute)
	_sync_controls()

func _sync_controls() -> void:
	_fullscreen.set_pressed_no_signal(Settings.fullscreen)
	_vsync.set_pressed_no_signal(Settings.vsync)
	var res_index := Settings.RESOLUTIONS.find(Settings.resolution)
	_resolution.select(maxi(res_index, 0))
	_resolution.disabled = Settings.fullscreen
	_volume.set_value_no_signal(Settings.master_volume * 100.0)
	_sfx_volume.set_value_no_signal(Settings.sfx_volume * 100.0)
	_mute.set_pressed_no_signal(Settings.muted)

## Soft dark left-edge gradient behind the menu column so text/pickers stay
## readable over the daylight diorama (never a hard opaque box): near-opaque
## under the column, fully transparent before mid-screen — the battle owns
## the right two-thirds of the frame.
func _build_vignette() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.38, 0.58])
	gradient.colors = PackedColorArray([
		Color(0.02, 0.03, 0.05, 0.8),
		Color(0.02, 0.03, 0.05, 0.55),
		Color(0.02, 0.03, 0.05, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 512
	tex.height = 8
	tex.fill_from = Vector2(0.0, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var rect := TextureRect.new()
	rect.name = "Vignette"
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := $UI/Root
	root.add_child(rect)
	root.move_child(rect, 0)

## 0.4s fade to black over everything, then restore the SFX bus and free the
## diorama (its _exit_tree resets godmode + bus) before the scene change.
func _fade_out_and_release() -> void:
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	$UI.add_child(fade)
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.4)
	await tween.finished
	var backdrop := get_node_or_null("Backdrop")
	if backdrop != null:
		backdrop.free()

## Launch from the NEW GAME view's Start button.
func _on_start_run() -> void:
	if _leaving:
		return
	_leaving = true
	await _fade_out_and_release()
	## main.gd's GameState.reset() clears godmode again; the backdrop's exit
	## already restored it, this is the existing change path unchanged.
	get_tree().change_scene_to_file("res://scenes/main.tscn")

## Host-start mirrors Play: fade + cleanup first, then Net.start_game()
## (its call_local RPC changes our scene). Clients change via the Net RPC
## without a local fade — their backdrop still cleans up on scene teardown.
func _on_start_game() -> void:
	if _leaving:
		return
	_leaving = true
	await _fade_out_and_release()
	Net.start_game()

## -- class selection --

## NEW GAME view: one FIXED-SIZE toggle button per class (uniform footprint
## regardless of name length — picking a class must never shift the layout),
## with the fixed-footprint info card underneath. Persists via
## Settings/Net.local_class.
func _build_class_picker() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for id in GameState.CLASSES:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(104, 40)
		button.clip_text = true
		button.text = GameState.class_title(id)
		button.add_theme_color_override("font_color", UITheme.TEXT_COLOR.lerp(GameState.class_tint(id), 0.5))
		button.pressed.connect(_on_class_picked.bind(id))
		row.add_child(button)
		_class_buttons[id] = button
	var menu := _new_game
	var anchor := $UI/Root/Center/NewGameMenu/Start.get_index()
	menu.add_child(row)
	menu.move_child(row, anchor)
	_build_class_card()
	menu.add_child(_class_card)
	menu.move_child(_class_card, anchor + 1)

## Info card under the picker: class sprite on top, then the weapon, then
## the stat deviations from baseline. FIXED footprint sized for the largest
## class (9 stat lines); shorter content pads out instead of shrinking, so
## switching classes moves nothing around it.
func _build_class_card() -> void:
	_class_card = PanelContainer.new()
	_class_card.custom_minimum_size = Vector2(300, 360)
	_class_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_class_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	_class_card.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)
	_card_sprite = TextureRect.new()
	_card_sprite.custom_minimum_size = Vector2(96, 96)
	_card_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_sprite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_card_sprite)
	_card_weapon = Label.new()
	_card_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_weapon.add_theme_font_size_override("font_size", 15)
	_card_weapon.add_theme_color_override("font_color", UITheme.ACCENT)
	vbox.add_child(_card_weapon)
	_card_stats = Label.new()
	_card_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_stats.add_theme_font_size_override("font_size", 13)
	_card_stats.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	vbox.add_child(_card_stats)

const STAT_NAMES := {
	"max_health": "Health", "damage": "Damage", "speed": "Move Speed",
	"auto_attack_range": "Auto-Attack Range", "light_radius": "Light Radius",
	"build_range": "Build Range", "reactor_amount": "Reactor Output",
	"reactor_cover": "Reactor Aura", "heal_beam_range": "Heal Beam Range",
}

## "x0.75 speed" reads poorly; show signed percentages, invert cooldown into
## attack speed, list flat adds and perks in plain words.
func _class_stat_lines(id: String) -> String:
	var info: Dictionary = GameState.class_info(id)
	var stats: Dictionary = info.get("stats", {})
	var lines: Array = []
	for key in stats:
		var v: float = float(stats[key])
		if key == "fire_cooldown":
			if not is_equal_approx(v, 1.0):
				lines.append("Attack Speed %+d%%" % roundi((1.0 / v - 1.0) * 100.0))
		elif key.ends_with("_add"):
			lines.append("%s %+d" % [key.trim_suffix("_add").capitalize(), int(v)])
		elif not is_equal_approx(v, 1.0):
			var label: String = STAT_NAMES.get(key, key.capitalize())
			lines.append("%s %+d%%" % [label, roundi((v - 1.0) * 100.0)])
	if bool(info.get("building_walk", false)):
		lines.append("Walks over buildings")
	if lines.is_empty():
		lines.append("Baseline stats")
	return "\n".join(lines)

## Lobby: dropdown above the player list — each peer picks its own class and
## the choice replicates through the Net registry. Late joiners parked here
## pick the same way; the pick rides their registration at the intermission.
func _build_lobby_class_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = "Your class"
	row.add_child(label)
	_lobby_class = OptionButton.new()
	_lobby_class.focus_mode = Control.FOCUS_NONE
	_lobby_class.custom_minimum_size = Vector2(160, 32)
	for id in GameState.CLASSES:
		_lobby_class.add_item(GameState.class_title(id))
	_lobby_class.item_selected.connect(_on_lobby_class_picked)
	row.add_child(_lobby_class)
	_lobby_class_desc = Label.new()
	_lobby_class_desc.add_theme_font_size_override("font_size", 13)
	_lobby_class_desc.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	var anchor := $UI/Root/Center/LobbyMenu/PlayersLabel.get_index()
	_lobby.add_child(row)
	_lobby.move_child(row, anchor)
	_lobby.add_child(_lobby_class_desc)
	_lobby.move_child(_lobby_class_desc, anchor + 1)

func _on_class_picked(id: String) -> void:
	Net.set_local_class(id)
	_sync_class_ui()

func _on_lobby_class_picked(index: int) -> void:
	var ids: Array = GameState.CLASSES.keys()
	if index >= 0 and index < ids.size():
		Net.set_local_class(ids[index])
	_sync_class_ui()

## Reflect Net.local_class in both pickers + description lines.
func _sync_class_ui() -> void:
	var cls: String = Net.local_class
	for id in _class_buttons:
		_class_buttons[id].set_pressed_no_signal(id == cls)
	var sprite_path := GameState.class_sprite(cls)
	_card_sprite.texture = load(sprite_path) if sprite_path != "" else null
	_card_sprite.modulate = Color.WHITE if sprite_path != "" else GameState.class_tint(cls)
	var weapon := str(GameState.class_info(cls).get("weapon", "blaster"))
	_card_weapon.text = weapon.capitalize()
	_card_stats.text = _class_stat_lines(cls)
	_lobby_class.select(maxi(GameState.CLASSES.keys().find(cls), 0))
	_lobby_class_desc.text = "%s — %s" % [str(GameState.class_info(cls).get("weapon", "blaster")).capitalize(), GameState.class_desc(cls)]

## -- world selection --

## NEW GAME view: one FIXED-SIZE toggle button per world under the class
## card, with a dim one-line description (fixed height so picks never shift
## the Start button). Persists via Settings/Net.
func _build_world_picker() -> void:
	if GameState.WORLDS.is_empty():
		return
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for id in GameState.WORLDS:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(120, 36)
		button.clip_text = true
		button.text = GameState.world_title(id)
		button.add_theme_color_override("font_color", UITheme.TEXT_COLOR.lerp(_world_tint(id), 0.45))
		button.pressed.connect(_on_world_picked.bind(id))
		row.add_child(button)
		_world_buttons[id] = button
	_world_desc = Label.new()
	_world_desc.custom_minimum_size = Vector2(0, 22)
	_world_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_world_desc.add_theme_font_size_override("font_size", 14)
	_world_desc.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	var menu := _new_game
	var anchor := $UI/Root/Center/NewGameMenu/Start.get_index()
	menu.add_child(row)
	menu.move_child(row, anchor)
	menu.add_child(_world_desc)
	menu.move_child(_world_desc, anchor + 1)

## Lobby: one shared world, HOST-chosen — a dropdown the host drives; clients
## see it read-only. The pick replicates through the host's Net registry entry.
func _build_lobby_world_row() -> void:
	if GameState.WORLDS.is_empty():
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = "World (host)"
	row.add_child(label)
	_lobby_world = OptionButton.new()
	_lobby_world.focus_mode = Control.FOCUS_NONE
	_lobby_world.custom_minimum_size = Vector2(160, 32)
	for id in GameState.WORLDS:
		_lobby_world.add_item(GameState.world_title(id))
	_lobby_world.item_selected.connect(_on_lobby_world_picked)
	row.add_child(_lobby_world)
	_lobby.add_child(row)
	_lobby.move_child(row, $UI/Root/Center/LobbyMenu/PlayersLabel.get_index())

## Button tint from the world's accent ground color (lightened so midnight's
## near-black still reads on a button face).
func _world_tint(id: String) -> Color:
	var def: Dictionary = GameState.world_def(id)
	return Util.color_arr(def.get("ground_detail", def.get("ground_color")), Color.WHITE).lightened(0.35)

func _on_world_picked(id: String) -> void:
	Net.set_local_world(id)
	_sync_world_ui()

func _on_lobby_world_picked(index: int) -> void:
	var ids: Array = GameState.WORLDS.keys()
	if index >= 0 and index < ids.size():
		Net.set_local_world(ids[index])
	_sync_world_ui()

## Reflect the effective world in both pickers: the host's replicated pick
## while in an online lobby, the local persisted pick otherwise.
func _sync_world_ui() -> void:
	if _world_buttons.is_empty():
		return
	var wid: String = Net.local_world
	if Net.is_online() and not Net.is_host():
		wid = str(Net.players.get(1, {}).get("world", wid))
	for id in _world_buttons:
		_world_buttons[id].set_pressed_no_signal(id == wid)
	_world_desc.text = GameState.world_desc(wid)
	_lobby_world.select(maxi(GameState.WORLDS.keys().find(wid), 0))
	_lobby_world.disabled = Net.is_online() and not Net.is_host()

func _show_settings(show_settings: bool) -> void:
	_menu.visible = not show_settings
	_settings.visible = show_settings

## NEW GAME setup view: class/world pickers + Start replace the main column.
func _show_new_game(show_new_game: bool) -> void:
	_menu.visible = not show_new_game
	_new_game.visible = show_new_game
	if show_new_game:
		_sync_class_ui()
		_sync_world_ui()

## -- co-op lobby --

func _show_lobby(show_lobby: bool) -> void:
	_menu.visible = not show_lobby
	_lobby.visible = show_lobby
	if show_lobby:
		_lobby_status.text = "Host a game or join by IP"
		_sync_class_ui()
		_sync_world_ui()
		_refresh_lobby()

func _on_host() -> void:
	var err := Net.host()
	if err != OK:
		_lobby_status.text = "Host failed (port in use?)"
		return
	_lobby_status.text = "Hosting on port %d" % Net.DEFAULT_PORT
	_refresh_lobby()

func _on_join() -> void:
	var ip := _ip.text.strip_edges()
	if not ip.is_valid_ip_address():
		_lobby_status.text = "Invalid IP address"
		return
	var err := Net.join(ip)
	if err != OK:
		_lobby_status.text = "Join failed"
		return
	_lobby_status.text = "Connecting to %s..." % ip
	_refresh_lobby()

func _on_lobby_back() -> void:
	Net.leave()
	_show_lobby(false)

func _on_session_ended(reason: String) -> void:
	_lobby_status.text = reason
	_refresh_lobby()

func _refresh_lobby() -> void:
	## The host's world pick rides the registry; mirror it into the picker.
	_sync_world_ui()
	for child in _player_list.get_children():
		child.queue_free()
	for peer_id in Net.players:
		var info: Dictionary = Net.players[peer_id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.text = info["name"] + (" (Host)" if peer_id == 1 else "")
		label.add_theme_color_override("font_color", info["color"])
		row.add_child(label)
		## Replicated class pick, visible to everyone in the lobby.
		var cls := Label.new()
		cls.text = "— " + GameState.class_title(str(info.get("class", "assault")))
		cls.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		row.add_child(cls)
		_player_list.add_child(row)
	if Net.players.is_empty() and _lobby.visible:
		var hint := Label.new()
		hint.text = "No session"
		hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		_player_list.add_child(hint)
	_host_button.disabled = Net.is_online()
	_join_button.disabled = Net.is_online()
	_ip.editable = not Net.is_online()
	# Host can start solo; clients wait for the host's start RPC.
	_start_button.disabled = not (Net.is_online() and Net.is_host())

func _apply_and_save() -> void:
	Settings.apply()
	Settings.save_settings()

func _on_fullscreen(pressed: bool) -> void:
	Settings.fullscreen = pressed
	_resolution.disabled = pressed
	_apply_and_save()

func _on_vsync(pressed: bool) -> void:
	Settings.vsync = pressed
	_apply_and_save()

func _on_resolution(index: int) -> void:
	Settings.resolution = Settings.RESOLUTIONS[index]
	_apply_and_save()

func _on_volume(value: float) -> void:
	Settings.master_volume = value / 100.0
	_apply_and_save()

func _on_sfx_volume(value: float) -> void:
	Settings.sfx_volume = value / 100.0
	_apply_and_save()
	Sfx.play("hit")

func _on_mute(pressed: bool) -> void:
	Settings.muted = pressed
	_apply_and_save()
