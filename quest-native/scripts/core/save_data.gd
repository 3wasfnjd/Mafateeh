extends Node
## Local progress and settings (user://mafateeh_save.cfg). No network, no
## analytics. Progress unlocks levels in order; the developer level selector
## is only offered when ProjectSettings "mafateeh/dev/level_select" is true or
## the hidden developer toggle has been enabled on this device.

const PATH := "user://mafateeh_save.cfg"
const VERSION := 1

var current_level := 1
var unlocked_level := 1
var completed := {}  # level -> true
var master_volume := 0.8
var muted := false
var mode := "mr"  # "mr" (passthrough) | "vr"
var board_scale := 0.12
var dev_enabled := false
var dev_time := ""  # override: dawn/day/sunset/night
var dev_weather := ""  # override: clear/rain


func _ready() -> void:
	load_data()


func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	current_level = clampi(int(cfg.get_value("progress", "current", 1)), 1, LevelData.COUNT)
	unlocked_level = clampi(int(cfg.get_value("progress", "unlocked", 1)), 1, LevelData.COUNT)
	completed = cfg.get_value("progress", "completed", {})
	master_volume = clampf(float(cfg.get_value("settings", "volume", 0.8)), 0.0, 1.0)
	muted = bool(cfg.get_value("settings", "muted", false))
	mode = str(cfg.get_value("settings", "mode", "mr"))
	board_scale = clampf(float(cfg.get_value("settings", "board_scale", 0.12)), 0.06, 0.26)
	dev_enabled = bool(cfg.get_value("dev", "enabled", false))
	current_level = mini(current_level, unlocked_level) if not dev_tools_available() else current_level


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", VERSION)
	cfg.set_value("progress", "current", current_level)
	cfg.set_value("progress", "unlocked", unlocked_level)
	cfg.set_value("progress", "completed", completed)
	cfg.set_value("settings", "volume", master_volume)
	cfg.set_value("settings", "muted", muted)
	cfg.set_value("settings", "mode", mode)
	cfg.set_value("settings", "board_scale", board_scale)
	cfg.set_value("dev", "enabled", dev_enabled)
	cfg.save(PATH)


func dev_tools_available() -> bool:
	return dev_enabled or bool(ProjectSettings.get_setting("mafateeh/dev/level_select", false))


func can_play(level: int) -> bool:
	return level >= 1 and level <= LevelData.COUNT and (level <= unlocked_level or dev_tools_available())


func mark_completed(level: int) -> void:
	completed[level] = true
	unlocked_level = maxi(unlocked_level, mini(level + 1, LevelData.COUNT))
	if level < LevelData.COUNT:
		current_level = level + 1
	save()


func set_current(level: int) -> void:
	if can_play(level):
		current_level = level
		save()


func reset_progress() -> void:
	current_level = 1
	unlocked_level = 1
	completed = {}
	save()
