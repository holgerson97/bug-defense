extends Node
## Autoload: persisted graphics/audio settings, applied at startup.

const PATH := "user://settings.cfg"

var fullscreen: bool = false
var vsync: bool = true
var master_volume: float = 1.0
var muted: bool = false

func _ready() -> void:
	load_settings()
	apply()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	fullscreen = cfg.get_value("graphics", "fullscreen", fullscreen)
	vsync = cfg.get_value("graphics", "vsync", vsync)
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	muted = cfg.get_value("audio", "muted", muted)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "muted", muted)
	cfg.save(PATH)

func apply() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		)
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
		)
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master, linear_to_db(clampf(master_volume, 0.0001, 1.0)))
	AudioServer.set_bus_mute(master, muted)
