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
var hint_shown := false
# Settings page (all optional; defaults match the original experience).
var sfx_volume := 1.0
var ambience_volume := 1.0
var turn_mode := "smooth"  # "smooth" | "snap" (left stick board rotation)
var turn_speed := 1  # 0 slow, 1 normal, 2 fast
var left_handed := false  # swaps the two sticks: left moves the hero
var haptics := true
var weather_pref := "auto"  # "auto" (per level) | "clear"
var show_intro := true
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
	hint_shown = bool(cfg.get_value("settings", "hint_shown", false))
	sfx_volume = clampf(float(cfg.get_value("settings", "sfx_volume", 1.0)), 0.0, 1.0)
	ambience_volume = clampf(float(cfg.get_value("settings", "ambience_volume", 1.0)), 0.0, 1.0)
	turn_mode = "snap" if str(cfg.get_value("settings", "turn_mode", "smooth")) == "snap" else "smooth"
	turn_speed = clampi(int(cfg.get_value("settings", "turn_speed", 1)), 0, 2)
	left_handed = bool(cfg.get_value("settings", "left_handed", false))
	haptics = bool(cfg.get_value("settings", "haptics", true))
	weather_pref = "clear" if str(cfg.get_value("settings", "weather", "auto")) == "clear" else "auto"
	show_intro = bool(cfg.get_value("settings", "show_intro", true))
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
	cfg.set_value("settings", "hint_shown", hint_shown)
	cfg.set_value("settings", "sfx_volume", sfx_volume)
	cfg.set_value("settings", "ambience_volume", ambience_volume)
	cfg.set_value("settings", "turn_mode", turn_mode)
	cfg.set_value("settings", "turn_speed", turn_speed)
	cfg.set_value("settings", "left_handed", left_handed)
	cfg.set_value("settings", "haptics", haptics)
	cfg.set_value("settings", "weather", weather_pref)
	cfg.set_value("settings", "show_intro", show_intro)
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


func is_completed(level: int) -> bool:
	return completed.has(level)


func reset_progress() -> void:
	current_level = 1
	unlocked_level = 1
	completed = {}
	save()
