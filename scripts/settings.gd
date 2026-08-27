extends Node
## Autoload: persisted graphics/audio settings, applied at startup.

const PATH := "user://settings.cfg"

const RESOLUTIONS: Array = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

var fullscreen: bool = false
var vsync: bool = true
var resolution: Vector2i = Vector2i(1280, 720)
var master_volume: float = 1.0
var sfx_volume: float = 1.0
var muted: bool = false

func _ready() -> void:
	_ensure_sfx_bus()
	load_settings()
	apply()

func _ensure_sfx_bus() -> void:
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	fullscreen = cfg.get_value("graphics", "fullscreen", fullscreen)
	vsync = cfg.get_value("graphics", "vsync", vsync)
	resolution = cfg.get_value("graphics", "resolution", resolution)
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	sfx_volume = cfg.get_value("audio", "sfx_volume", sfx_volume)
	muted = cfg.get_value("audio", "muted", muted)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("graphics", "resolution", resolution)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "muted", muted)
	cfg.save(PATH)

func apply() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		)
		if not fullscreen:
			DisplayServer.window_set_size(resolution)
			_center_window()
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
		)
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master, linear_to_db(clampf(master_volume, 0.0001, 1.0)))
	AudioServer.set_bus_mute(master, muted)
	var sfx := AudioServer.get_bus_index("SFX")
	if sfx != -1:
		AudioServer.set_bus_volume_db(sfx, linear_to_db(clampf(sfx_volume, 0.0001, 1.0)))

func _center_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var screen_pos := DisplayServer.screen_get_position(screen)
	var screen_size := DisplayServer.screen_get_size(screen)
	DisplayServer.window_set_position(screen_pos + (screen_size - resolution) / 2)
