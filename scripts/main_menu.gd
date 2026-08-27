extends Control

@onready var _menu: VBoxContainer = $Center/Menu
@onready var _settings: VBoxContainer = $Center/SettingsMenu
@onready var _fullscreen: CheckButton = $Center/SettingsMenu/Fullscreen
@onready var _vsync: CheckButton = $Center/SettingsMenu/Vsync
@onready var _resolution: OptionButton = $Center/SettingsMenu/ResolutionRow/Resolution
@onready var _volume: HSlider = $Center/SettingsMenu/VolumeRow/Volume
@onready var _sfx_volume: HSlider = $Center/SettingsMenu/SfxRow/SfxVolume
@onready var _mute: CheckButton = $Center/SettingsMenu/Mute

func _ready() -> void:
	theme = UITheme.build()
	$Center/Menu/Play.pressed.connect(_on_play)
	$Center/Menu/SettingsButton.pressed.connect(_show_settings.bind(true))
	$Center/Menu/Quit.pressed.connect(func(): get_tree().quit())
	$Center/SettingsMenu/Back.pressed.connect(_show_settings.bind(false))
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

func _show_settings(show_settings: bool) -> void:
	_menu.visible = not show_settings
	_settings.visible = show_settings

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
