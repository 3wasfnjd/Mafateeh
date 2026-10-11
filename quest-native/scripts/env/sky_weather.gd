class_name SkyWeather
extends Node
## Offline time-of-day and weather. Purely visual/atmospheric: it never reads
## or writes puzzle state, so it cannot change a solution, hide a light beam
## or block a route. Presets come from each level's data; developers can
## override them (settings panel, --time/--weather, project settings).

signal weather_changed(raining: bool, amount: float)

const TIMES := ["dawn", "day", "sunset", "night"]

const PRESETS := {
	"dawn": {"elev": 12.0, "azim": 70.0, "sun": Color("ffbf8f"), "energy": 1.15,
		"ambient": Color("9a9cb8"), "amb_energy": 0.75, "top": Color("6d82b8"), "horizon": Color("f2b98e"),
		"ground": Color("8a6e57"), "lanterns": 0.25},
	"day": {"elev": 55.0, "azim": 35.0, "sun": Color("fff2dc"), "energy": 1.55,
		"ambient": Color("c9cfd9"), "amb_energy": 0.7, "top": Color("4f8acb"), "horizon": Color("cfe0ec"),
		"ground": Color("b49673"), "lanterns": 0.0},
	"sunset": {"elev": 13.0, "azim": -65.0, "sun": Color("ffa062"), "energy": 1.3,
		"ambient": Color("b08d98"), "amb_energy": 0.7, "top": Color("5a5e9c"), "horizon": Color("f6a35f"),
		"ground": Color("8d6550"), "lanterns": 0.45},
	"night": {"elev": 38.0, "azim": 20.0, "sun": Color("a9bde8"), "energy": 0.42,
		"ambient": Color("4c5a84"), "amb_energy": 0.85, "top": Color("0e1631"), "horizon": Color("2c3962"),
		"ground": Color("2a2730"), "lanterns": 1.0},
}

var env: Environment
var sun: DirectionalLight3D
var board: Node3D
var game: Node3D
var sky_mat: ProceduralSkyMaterial
var time_name := "day"
var raining := false
var rain_amount := 0.0  # 0..1, eased
var mixed_reality := false
var _cur := {}
var _blend := 1.0
var _from := {}
var _to := {}
var rain: RainField
var lanterns: Array = []
var scenery: Node3D


func setup(e: Environment, s: DirectionalLight3D, b: Node3D, g: Node3D) -> void:
	env = e
	sun = s
	board = b
	game = g
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	sky_mat.energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	_cur = PRESETS.day.duplicate()
	_apply(_cur)
	rain = RainField.new()
	rain.name = "Rain"
	board.add_child(rain)
	for side in [-1, 1]:
		var l := OmniLight3D.new()
		l.light_color = Color("ffb35c")
		l.omni_range = 3.2
		l.omni_attenuation = 1.6
		l.shadow_enabled = false
		l.position = Vector3(LevelData.EXIT_X + side * 0.82, 1.35, -3.25)
		board.add_child(l)
		lanterns.append(l)
	scenery = VRScenery.new()
	scenery.name = "VRScenery"
	add_child(scenery)


func apply_level(n: int, force_time := "", force_weather := "") -> void:
	var d := LevelData.get_level(n)
	var t: String = d.get("time", "day")
	var w: String = d.get("weather", "clear")
	var pt := String(ProjectSettings.get_setting("mafateeh/dev/force_time", ""))
	var pw := String(ProjectSettings.get_setting("mafateeh/dev/force_weather", ""))
	if Save.dev_time != "": t = Save.dev_time
	if Save.dev_weather != "": w = Save.dev_weather
	if pt != "": t = pt
	if pw != "": w = pw
	if force_time != "": t = force_time
	if force_weather != "": w = force_weather
	set_time(t, false)
	set_rain(w == "rain", false)
	rain.rebuild(game.state)
	for i in lanterns.size():
		lanterns[i].position.y = LevelData.exit_y(d) + 1.35


func set_time(t: String, smooth := true) -> void:
	if not PRESETS.has(t):
		return
	time_name = t
	_from = _cur.duplicate()
	_to = PRESETS[t]
	_blend = 0.0 if smooth else 1.0
	if not smooth:
		_cur = _to.duplicate()
		_apply(_cur)


func set_rain(on: bool, smooth := true) -> void:
	raining = on
	if not smooth:
		rain_amount = 1.0 if on else 0.0
		_apply(_cur)
	weather_changed.emit(on, rain_amount)


func cycle_time() -> void:
	set_time(TIMES[(TIMES.find(time_name) + 1) % TIMES.size()])


func toggle_rain() -> void:
	set_rain(not raining)


func set_mixed_reality(on: bool) -> void:
	mixed_reality = on
	scenery.visible = not on
	_apply(_cur)


func _process(delta: float) -> void:
	var changed := false
	if _blend < 1.0:
		_blend = minf(1.0, _blend + delta / 2.5)
		var k := smoothstep(0.0, 1.0, _blend)
		for key in _to:
			var a = _from[key]
			var b = _to[key]
			_cur[key] = a.lerp(b, k) if a is Color else lerpf(a, b, k)
		changed = true
	var target := 1.0 if raining else 0.0
	if absf(rain_amount - target) > 0.001:
		rain_amount = move_toward(rain_amount, target, delta / 3.0)
		changed = true
		weather_changed.emit(raining, rain_amount)
	if changed:
		_apply(_cur)
	rain.amount = rain_amount
	var hero_pos: Vector2 = game.motor.pos if game and game.get("motor") else Vector2.ZERO
	rain.hero = hero_pos
	if scenery.visible and board.visible:
		scenery.follow(board)


func _apply(p: Dictionary) -> void:
	var wet := rain_amount
	var elev := deg_to_rad(p.elev)
	var azim := deg_to_rad(p.azim)
	sun.rotation = Vector3(-elev, azim, 0)
	sun.light_color = p.sun.lerp(Color("c9d2dc"), wet * 0.5)
	sun.light_energy = p.energy * lerpf(1.0, 0.55, wet)
	# Ambient keeps every path and clue readable, including at night and in rain.
	env.ambient_light_color = p.ambient.lerp(Color("aeb6c2"), wet * 0.35)
	env.ambient_light_energy = maxf(p.amb_energy * lerpf(1.0, 1.1, wet), 0.55)
	sky_mat.sky_top_color = p.top.lerp(Color("6c7480"), wet * 0.6)
	sky_mat.sky_horizon_color = p.horizon.lerp(Color("a3a9b0"), wet * 0.6)
	sky_mat.ground_horizon_color = p.horizon.lerp(p.ground, 0.5)
	sky_mat.ground_bottom_color = p.ground
	sky_mat.sun_angle_max = 6.0 if time_name == "night" else 20.0
	for l in lanterns:
		l.light_energy = p.lanterns * 1.6
		l.visible = p.lanterns > 0.05
	# Wet stone: darker and glossier, but no screen-space reflections.
	for name in ["stone", "stone_dark", "plaster", "plaster_top"]:
		var m := Kit.mat(name) as StandardMaterial3D
		if not m.has_meta("dry_rough"):
			m.set_meta("dry_rough", m.roughness)
			m.set_meta("dry_color", m.albedo_color)
		var dry: Color = m.get_meta("dry_color")
		var factor := 0.35 if name.begins_with("stone") else 0.15
		m.roughness = lerpf(m.get_meta("dry_rough"), 0.38 if name.begins_with("stone") else 0.75, wet)
		m.albedo_color = dry.darkened(wet * factor)
	var glow := Kit.mat("glow") as StandardMaterial3D
	glow.emission_energy_multiplier = 1.6 + p.lanterns * 1.2
	if scenery:
		scenery.set_tint(p, wet)
