extends Control

@onready var _menu: VBoxContainer = $Center/Menu
@onready var _settings: VBoxContainer = $Center/SettingsMenu
@onready var _lobby: VBoxContainer = $Center/LobbyMenu
@onready var _lobby_status: Label = $Center/LobbyMenu/Status
@onready var _host_button: Button = $Center/LobbyMenu/HostButton
@onready var _ip: LineEdit = $Center/LobbyMenu/JoinRow/Ip
@onready var _join_button: Button = $Center/LobbyMenu/JoinRow/JoinButton
@onready var _player_list: VBoxContainer = $Center/LobbyMenu/PlayerList
@onready var _start_button: Button = $Center/LobbyMenu/StartButton
@onready var _fullscreen: CheckButton = $Center/SettingsMenu/Fullscreen
@onready var _vsync: CheckButton = $Center/SettingsMenu/Vsync
@onready var _resolution: OptionButton = $Center/SettingsMenu/ResolutionRow/Resolution
@onready var _volume: HSlider = $Center/SettingsMenu/VolumeRow/Volume
@onready var _sfx_volume: HSlider = $Center/SettingsMenu/SfxRow/SfxVolume
@onready var _mute: CheckButton = $Center/SettingsMenu/Mute

## Class picker widgets (built in code; classes are data-driven from balance).
var _class_buttons: Dictionary = {}
var _class_desc: Label
var _lobby_class: OptionButton
var _lobby_class_desc: Label
## World picker widgets (same pattern; worlds are data-driven from balance).
## Empty WORLDS section = no pickers at all (midnight fallback everywhere).
var _world_buttons: Dictionary = {}
var _world_desc: Label
var _lobby_world: OptionButton

func _ready() -> void:
	theme = UITheme.build()
	_build_class_picker()
	_build_lobby_class_row()
	_build_world_picker()
	_build_lobby_world_row()
	_sync_class_ui()
	_sync_world_ui()
	$Center/Menu/Play.pressed.connect(_on_play)
	$Center/Menu/Coop.pressed.connect(_show_lobby.bind(true))
	$Center/Menu/SettingsButton.pressed.connect(_show_settings.bind(true))
	$Center/Menu/Quit.pressed.connect(func(): get_tree().quit())
	$Center/SettingsMenu/Back.pressed.connect(_show_settings.bind(false))
	_host_button.pressed.connect(_on_host)
	_join_button.pressed.connect(_on_join)
	_start_button.pressed.connect(func(): Net.start_game())
	$Center/LobbyMenu/LobbyBack.pressed.connect(_on_lobby_back)
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

func _on_play() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

## -- class selection --

## Main menu (single player): one toggle button per class above Play, with a
## dim one-line description underneath. Persists via Settings/Net.local_class.
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
		button.custom_minimum_size = Vector2(0, 40)
		button.text = GameState.class_title(id)
		button.add_theme_color_override("font_color", UITheme.TEXT_COLOR.lerp(GameState.class_tint(id), 0.5))
		button.pressed.connect(_on_class_picked.bind(id))
		row.add_child(button)
		_class_buttons[id] = button
	_class_desc = Label.new()
	_class_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_class_desc.add_theme_font_size_override("font_size", 14)
	_class_desc.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	var menu := $Center/Menu
	menu.add_child(row)
	menu.move_child(row, $Center/Menu/Play.get_index())
	menu.add_child(_class_desc)
	menu.move_child(_class_desc, $Center/Menu/Play.get_index())

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
	var anchor := $Center/LobbyMenu/PlayersLabel.get_index()
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
	_class_desc.text = GameState.class_desc(cls)
	_lobby_class.select(maxi(GameState.CLASSES.keys().find(cls), 0))
	_lobby_class_desc.text = GameState.class_desc(cls)

## -- world selection --

## Main menu (single player): one toggle button per world under the class
## picker, with a dim one-line description. Persists via Settings/Net.
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
		button.custom_minimum_size = Vector2(0, 36)
		button.text = GameState.world_title(id)
		button.add_theme_color_override("font_color", UITheme.TEXT_COLOR.lerp(_world_tint(id), 0.45))
		button.pressed.connect(_on_world_picked.bind(id))
		row.add_child(button)
		_world_buttons[id] = button
	_world_desc = Label.new()
	_world_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_world_desc.add_theme_font_size_override("font_size", 14)
	_world_desc.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	var menu := $Center/Menu
	menu.add_child(row)
	menu.move_child(row, $Center/Menu/Play.get_index())
	menu.add_child(_world_desc)
	menu.move_child(_world_desc, $Center/Menu/Play.get_index())

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
	_lobby.move_child(row, $Center/LobbyMenu/PlayersLabel.get_index())

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
