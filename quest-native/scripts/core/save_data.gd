extends Node
## Local progress and settings (user://mafateeh_save.cfg). No network, no
## analytics. Progress unlocks levels in order; the developer level selector
## is only offered when ProjectSettings "mafateeh/dev/level_select" is true or
## the hidden developer toggle has been enabled on this device.

const PATH := "user://mafateeh_save.cfg"
const VERSION := 2  # 2: unlocks derived from completed levels; dev tools reset

var current_level := 1
var unlocked_level := 1
var completed := {}  # level -> true
var stars := {}  # level -> best stars (1..3)
var secrets := {}  # level -> true when its secret gem was found
var wearing := {}  # wardrobe slot -> item id (see Wardrobe.ITEMS)
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
var weather_pref := "cycle"  # "cycle" (passing showers) | "level" (as designed) | "clear"
var day_cycle := true  # time of day moves on by itself (dawn → day → sunset → night)
var dust := true  # light drifting dust in clear weather
var quality := "high"  # "high" | "balanced" (render resolution, foveation, shadows)
var language := ""  # "ar" | "en"; empty until chosen: follows the headset language
var dev_time := ""  # override: dawn/day/sunset/night
var dev_weather := ""  # override: clear/rain


func _ready() -> void:
	load_data()


func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	current_level = clampi(int(cfg.get_value("progress", "current", 1)), 1, LevelData.COUNT)
	completed = {}
	var stored: Variant = cfg.get_value("progress", "completed", {})
	if stored is Dictionary:
		for k in stored:
			var n := int(k)
			if n >= 1 and n <= LevelData.COUNT and stored[k]:
				completed[n] = true
	unlocked_level = _unlocked_from(completed)
	stars = {}
	secrets = {}
	var st: Variant = cfg.get_value("progress", "stars", {})
	if st is Dictionary:
		for k in st:
			if int(k) >= 1 and int(k) <= LevelData.COUNT:
				stars[int(k)] = clampi(int(st[k]), 1, 3)
	var se: Variant = cfg.get_value("progress", "secrets", {})
	if se is Dictionary:
		for k in se:
			if int(k) >= 1 and int(k) <= LevelData.COUNT and se[k]:
				secrets[int(k)] = true
	wearing = {}
	var wr: Variant = cfg.get_value("progress", "wearing", {})
	if wr is Dictionary:
		for slot in wr:
			var it := Wardrobe.item(str(wr[slot]))
			if not it.is_empty() and it.slot == slot:
				wearing[slot] = it.id
	master_volume = clampf(float(cfg.get_value("settings", "volume", 0.8)), 0.0, 1.0)
	muted = bool(cfg.get_value("settings", "muted", false))
	mode = str(cfg.get_value("settings", "mode", "mr"))
	board_scale = clampf(float(cfg.get_value("settings", "board_scale", 0.12)), 0.06, 0.26)
	# Saves from earlier test builds may carry the hidden developer switch; start clean.
	var saved_version := int(cfg.get_value("meta", "version", 1))
	dev_enabled = bool(cfg.get_value("dev", "enabled", false)) and saved_version >= VERSION
	hint_shown = bool(cfg.get_value("settings", "hint_shown", false))
	sfx_volume = clampf(float(cfg.get_value("settings", "sfx_volume", 1.0)), 0.0, 1.0)
	ambience_volume = clampf(float(cfg.get_value("settings", "ambience_volume", 1.0)), 0.0, 1.0)
	turn_mode = "snap" if str(cfg.get_value("settings", "turn_mode", "smooth")) == "snap" else "smooth"
	turn_speed = clampi(int(cfg.get_value("settings", "turn_speed", 1)), 0, 2)
	left_handed = bool(cfg.get_value("settings", "left_handed", false))
	haptics = bool(cfg.get_value("settings", "haptics", true))
	var wp := str(cfg.get_value("settings", "weather", "cycle"))
	weather_pref = wp if wp in ["cycle", "level", "clear"] else "cycle"  # old "auto" → automatic
	day_cycle = bool(cfg.get_value("settings", "day_cycle", true))
	dust = bool(cfg.get_value("settings", "dust", true))
	language = str(cfg.get_value("settings", "language", ""))
	quality = "balanced" if str(cfg.get_value("settings", "quality", "high")) == "balanced" else "high"
	current_level = mini(current_level, unlocked_level) if not dev_tools_available() else current_level


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", VERSION)
	cfg.set_value("progress", "current", current_level)
	cfg.set_value("progress", "unlocked", unlocked_level)
	cfg.set_value("progress", "completed", completed)
	cfg.set_value("progress", "stars", stars)
	cfg.set_value("progress", "secrets", secrets)
	cfg.set_value("progress", "wearing", wearing)
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
	cfg.set_value("settings", "day_cycle", day_cycle)
	cfg.set_value("settings", "dust", dust)
	cfg.set_value("settings", "language", language)
	cfg.set_value("settings", "quality", quality)
	cfg.save(PATH)


## Interface language: the player's choice, else Arabic on an Arabic-language
## headset and English otherwise.
func lang() -> String:
	if language == "ar" or language == "en":
		return language
	return "ar" if OS.get_locale_language() == "ar" else "en"


func arabic() -> bool:
	return lang() == "ar"


## Picks the interface string for the current language.
func text(ar: String, en: String) -> String:
	return ar if arabic() else en


func dev_tools_available() -> bool:
	return dev_enabled or bool(ProjectSettings.get_setting("mafateeh/dev/level_select", false))


func can_play(level: int) -> bool:
	return level >= 1 and level <= LevelData.COUNT and (level <= unlocked_level or dev_tools_available())


## A level opens only when the one before it has been solved: the furthest
## playable level is the first one not yet completed in an unbroken run from 1.
static func _unlocked_from(done: Dictionary) -> int:
	var n := 1
	while n < LevelData.COUNT and done.has(n):
		n += 1
	return n


func mark_completed(level: int, earned := 0, secret := false) -> void:
	completed[level] = true
	if earned > 0:
		stars[level] = maxi(stars.get(level, 0), earned)
	if secret:
		secrets[level] = true
	unlocked_level = _unlocked_from(completed)
	if level < LevelData.COUNT:
		current_level = level + 1
	save()


func set_current(level: int) -> void:
	if can_play(level):
		current_level = level
		save()


func total_stars() -> int:
	var n := 0
	for k in stars:
		n += stars[k]
	return n


func total_secrets() -> int:
	return secrets.size()


func wardrobe_unlocked(it: Dictionary) -> bool:
	return Wardrobe.is_unlocked(it, total_stars(), total_secrets()) or dev_tools_available()


## Put an item on (or take it off when already worn). Returns false if still locked.
func toggle_wear(id: String) -> bool:
	var it := Wardrobe.item(id)
	if it.is_empty() or not wardrobe_unlocked(it):
		return false
	if wearing.get(it.slot, "") == id:
		wearing.erase(it.slot)
	else:
		wearing[it.slot] = id
	save()
	return true


func is_completed(level: int) -> bool:
	return completed.has(level)


func reset_progress() -> void:
	current_level = 1
	unlocked_level = 1
	completed = {}
	stars = {}
	secrets = {}
	wearing = {}
	save()
