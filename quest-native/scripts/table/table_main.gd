extends Node3D
## Mafateeh: the tabletop game in mixed reality (the owner's direction: AR only, a small
## diorama on the table, few words, light simple menus in beige / light brown).
##
## The menu (TableMenu): one clay plaque with a rail of tabs (levels, wardrobe, atmosphere,
## settings, about). In play: a scene diorama sits on the table and its level runs on it; once
## won, the stars it earned rise over it (by how quickly it was solved), the scene sinks into
## the ground and the next level's rises out of it. Each level hides a gem somewhere in its
## scene; point at it and press to take it. The old man's clothes are all open to try on.
## Weather drifts over some scenes (dust, sand gusts in the dunes, a shower on the farm), each
## scene has its own quiet surroundings sound, and the last level ends with the old men firing
## for joy, then a thank-you with the studio's site.
## Before the first scene appears the player sets it down (TablePlacer): a ring follows the
## pointer over the real tables the headset knows (outlined; the room data needs the scene
## permission, asked for at start), or the floor; the trigger fixes it there.
##   Trigger: point and press (the pointer is smoothed, snaps onto things, and rings what it
##   is on). Hold grip and move the hand: carry the diorama. Left stick x: turn it; y: resize it.
##   Right stick: walk the old man (level 2). Tap grip: set it down somewhere else. Menu: the menu.
## Desktop (no headset): click, drag on the sand to draw, WASD walk, right-drag look,
##   arrows walk the old man, Q/E turn the diorama, Esc the menu.
## Screenshot args: --screenshot=path [--start=play|menu] [--page=levels|wardrobe|world|settings|about] [--lang=ar|en]
##   [--cam=x,y,z,yaw,pitch] [--level=N] [--k=size] [--turn=deg] [--demo=1] [--wait=frames]
##   [--place=1] (show the placing ring instead of the scene) [--weather=rain|gust|dust]

const MUSIC := "res://audio/music/%s.ogg"   # calm loops from tools/audio/make_soft_audio.py
const AMBIENCE := "res://audio/ambience/%s.ogg"
const MUSIC_DB := -15.0
const SFX_DB := -11.0
const AMBIENCE_DB := -20.0
const LAST_LEVEL := 11
const RISE_TIME := 1.1      # a scene sinking into the ground, or rising out of it
# How long a level may take for three stars (twice as long: two; any longer: one). Seconds.
const PAR := {1: 45.0, 2: 150.0, 3: 90.0, 4: 200.0, 5: 90.0, 6: 110.0, 7: 70.0, 8: 100.0, 9: 120.0, 10: 75.0, 11: 100.0}
# Where each level's hidden key lies (x, z in the scene's metres; it sits on whatever is there),
# always on low ground in sight from the front, never up in a palm or behind a house.
const GEMS := {1: Vector2(-6.4, -5.2), 2: Vector2(5.8, -0.6), 3: Vector2(-8.2, 1.6), 4: Vector2(10.6, 5.6),
	5: Vector2(6.6, -2.4), 6: Vector2(8.4, -6.6), 7: Vector2(-6.2, 5.4), 8: Vector2(6.9, 3.0),
	9: Vector2(7.7, 6.9), 10: Vector2(10.2, 7.0), 11: Vector2(-6.0, -1.8)}
# The weather each scene has when the atmosphere is "as designed", and its surroundings sound.
# dust: drifting motes; gusts: blown sand now and then; rain: a passing shower now and then
const WEATHER := {1: "dust rain", 2: "dust rain", 3: "dust rain gusts", 4: "dust gusts rain", 5: "dust rain",
	6: "dust rain gusts", 7: "", 8: "dust rain", 9: "dust rain gusts", 10: "dust gusts", 11: ""}
const AMBIENT := {1: "birds", 2: "birds", 3: "wind", 4: "wind", 5: "fire", 6: "birds", 7: "night", 8: "market", 9: "water", 10: "wind", 11: "night"}

var env: Environment
var sun: DirectionalLight3D
var _music: AudioStreamPlayer
var _music_mood := ""
var _ambience: AudioStreamPlayer
var rig: XRRig
var xr := false
var desk_cam: Camera3D
var card: TableMenu         # the menu, while it is open
var _args := {}
var diorama: Diorama
var level: Node3D           # Table*Level: setup(d), pointer(held, p), demo(), level_won; aim(), move(), hover_boxes() optional
var stage := 1              # which level is on the table
var _round := 0             # bumped on every _play, so a stale "level won" timer does nothing
var table_k := 1.0
var _drag := {}
var _yaw := 0.0
var _pitch := -0.12
var _mouse_down := false
var _mr_on := false         # passthrough switched on (only possible once the session runs)
var surfaces: SceneSurfaces # real tables from the headset's room setup (Meta Scene API)
var _moved_by_hand := false # once the player carries the diorama, detected tables no longer move it
# the pointer
var _hand := "right"        # the hand that pressed last: the one that points
var _down := {}             # hand -> trigger held last frame
var _swallow := false       # a press went to the menu or the gem: the level does not see it
var _hover_id := ""
const ISLAND_R := 16.0   # model metres: the island's radius (0.33 m at 1x)
var _ptr_drawn := false   # the headset's pointer is drawn (on the headset, or a --hand screenshot)
var _hover_mark: MeshInstance3D
var _t := 0.0
# this level's extras
var _started_at := 0.0
var _gem: Node3D
var _weather: TableWeather
var _placer: TablePlacer   # finding the surface, before the scene appears
var _place_began := 0.0
var _clock_running := false
var _placing := false
var _intro: TableIntro       # the way in (studio logo, the gate), before the first level
var _intro_begun := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _args.has("lang") and _save():   # screenshots: --lang=ar|en (not saved)
		_save().language = str(_args.lang)
	_setup_audio()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8f8a82")  # stand-in for the room on desktop
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff6ea")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 32, 0)
	sun.light_energy = 0.95
	sun.shadow_enabled = false  # no shadows (owner's choice; also cheaper on Quest)
	add_child(sun)
	rig = XRRig.new()
	rig.name = "XRRig"
	add_child(rig)
	rig.setup(env)
	xr = not _args.has("screenshot") and rig.start()
	if xr:
		# Passthrough can only be switched on once the session runs (before that the runtime
		# reports no alpha-blend mode and the rig would fall back to a black VR void), so
		# _process keeps trying until it takes.
		surfaces = SceneSurfaces.new()
		add_child(surfaces)
		surfaces.attach(rig)
		surfaces.surfaces_changed.connect(func():
			if _placer:
				_placer.rebuild())
	else:
		desk_cam = Camera3D.new()
		desk_cam.fov = 70
		rig.add_child(desk_cam)
		desk_cam.position = Vector3(0, 1.62, 0)
		desk_cam.current = true
	rig.menu_pressed.connect(_toggle_menu)
	rig.grip_tapped.connect(_on_grip_tap)
	if _args.has("cam"):
		var c := str(_args.cam).split_floats(",")
		rig.position = Vector3(c[0], 0, c[2])
		desk_cam.position.y = c[1]
		_yaw = deg_to_rad(c[3])
		_pitch = deg_to_rad(c[4])
		desk_cam.rotation = Vector3(_pitch, _yaw, 0)
	match str(_args.get("start", "")):
		"play": _play(int(_args.get("level", "1")))
		"intro": _start_intro()
		_:
			if xr:
				_start_intro()   # on the headset: the way in, then the game (the menu is one button away)
			else:
				_show_menu(str(_args.get("page", "levels")))
	if _args.has("screenshot"):
		if _args.has("sky"):   # store art: a warm desert sky behind the table instead of the grey room
			var sky := Sky.new()
			var pm := ProceduralSkyMaterial.new()
			var night := str(_args.sky) == "night"
			pm.sky_top_color = Color("0d1630") if night else Color("8fb6d8")
			pm.sky_horizon_color = Color("2b2c46") if night else Color("f1dcb8")
			pm.ground_bottom_color = Color("15141c") if night else Color("b9a58c")
			pm.ground_horizon_color = Color("2b2c46") if night else Color("e9dcc6")
			pm.sky_energy_multiplier = 0.6 if night else 1.0
			sky.sky_material = pm
			env.sky = sky
			env.background_mode = Environment.BG_SKY
		if _args.has("title"):
			_store_title(str(_args.title))
		_screenshot.call_deferred()


## The studio's logo, then the gate; it starts once the headset reports the head, and the
## game (the next level, from placing the scene) follows it.
func _start_intro() -> void:
	_intro = TableIntro.new()
	add_child(_intro)
	_intro_begun = false
	_intro.finished.connect(func():
		_intro = null
		_play(_next_level()))


func _save() -> Node:
	return get_node_or_null("/root/Save")


# --- the menu -----------------------------------------------------------------------------------

func _show_menu(page := "levels") -> void:
	_close_menu()
	var m := TableMenu.new()
	m.page = page
	m.stage = stage if diorama else 0
	card = m
	add_child(m)
	_place_card(true)
	m.play_level.connect(func(n: int): _play(n if n > 0 else _next_level()))
	m.closed.connect(_close_menu)
	m.replace_table.connect(func():
		if diorama:
			_close_menu()
			_begin_place())
	m.settings_changed.connect(_apply_settings)


func _close_menu() -> void:
	if card:
		card.queue_free()
		card = null


func _toggle_menu() -> void:
	if _intro:
		_intro.queue_free()   # the menu button skips the way in
		_intro = null
		_show_menu()
		return
	if card and diorama:
		_close_menu()
	else:
		_show_menu()


## The first level not yet won (from the one on the table), or the next one.
func _next_level() -> int:
	var save := _save()
	for k in LAST_LEVEL:
		var n := (stage - 1 + k) % LAST_LEVEL + 1 if diorama else k + 1
		if save == null or not save.table_stars.has(n):
			return n
	return stage % LAST_LEVEL + 1 if diorama else 1


## Sets the menu in front of the player, where it then stays (it does not follow the head).
## Before the headset reports the head it goes to a default spot, and moves once, when it does.
var _card_placed := false


func _place_card(_instant := true) -> void:
	var head := _head()
	_card_placed = head.origin.length() > 0.01
	var fwd := -head.basis.z
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var target := head.origin + fwd * 0.75 + Vector3(0, -0.06, 0)
	if not _card_placed:
		target = Vector3(0, 1.56, -0.75)
	card.global_position = target
	var look := head.origin if _card_placed else Vector3(0, 1.62, 0)
	card.look_at(look, Vector3.UP, true)


## Settings changed in the menu: volumes, the old man's clothes, the weather.
func _apply_settings() -> void:
	var save := _save()
	if save == null:
		return
	for b in [["Music", MUSIC_DB, save.music_volume], ["SFX", SFX_DB, save.sfx_volume], ["Ambience", AMBIENCE_DB, save.ambience_volume]]:
		var i := AudioServer.get_bus_index(b[0])
		if i >= 0:
			AudioServer.set_bus_volume_db(i, b[1] + linear_to_db(maxf(b[2], 0.0001)))
			AudioServer.set_bus_mute(i, b[2] <= 0.001)
	if diorama:
		diorama.dress()
		if not save.day_cycle:
			_sky = -1
		elif _sky < 0 and not (stage in ALWAYS_NIGHT):
			# carry on from the light the scene has now
			_sky = 0
			for i in SKY.size():
				if SKY[i][0] == _mood:
					_sky = i
			_sky_left = SKY[_sky][1]
	_set_weather()


# --- play ---------------------------------------------------------------------------------

func _play(n := 1, rising := false) -> void:
	_close_menu()
	var keep := Transform3D()
	var keep_spot := diorama != null
	if diorama:
		keep = diorama.global_transform
		diorama.queue_free()
	stage = n
	_round += 1
	diorama = Diorama.new()
	diorama.pacing_cat = false     # the level's cat is the one being played
	diorama.birds_outside = false  # keep the ground the player works on clear
	add_child(diorama)
	diorama.setup(n)
	var mood := str(diorama.layout.get("mood", "day"))
	_start_sky(mood)
	_play_ambience(AMBIENT.get(n, ""))
	match n:
		2: level = TableStepsLevel.new()
		3: level = TableFalconLevel.new()
		4: level = TableCampLevel.new()
		5: level = TableLanternLevel.new()
		6: level = TableDrumLevel.new()
		7: level = TableStarsLevel.new()
		8: level = TableBarterLevel.new()
		9: level = TableSaniaLevel.new()
		10: level = TableRaidLevel.new()
		11: level = TableChestLevel.new()
		_: level = TablePathLevel.new()
	diorama.stage.add_child(level)
	level.setup(diorama)
	level.level_won.connect(_on_level_won)
	_hover_mark = TableKit.ring(diorama.stage, 1.0, Color("fff1d0"), 0.85, 0.1)
	_hover_mark.visible = false
	_hover_id = ""
	_weather = TableWeather.new()
	diorama.stage.add_child(_weather)
	_weather.setup(diorama)
	_set_weather()
	_gem = null
	var save := _save()
	if GEMS.has(n) and not (save and save.table_gems.get(n, false)):
		var g: Vector2 = GEMS[n]
		_gem = TableFx.gem(diorama.stage, Vector3(g.x, _surface_y(g), g.y))
	_started_at = _t
	_clock_running = keep_spot or not xr   # in XR it starts when the scene is set down
	if keep_spot:
		diorama.global_transform = keep
	elif xr:
		_begin_place()   # find the surface first; the scene appears where it is set down
	else:
		table_k = 1.0
		_place_table()
	if rising:  # the new scene grows up out of the ground
		diorama.set_rise(0.0)
		create_tween().tween_method(diorama.set_rise, 0.0, 1.0, RISE_TIME).set_delay(0.15)


## The height of the scene's top surface at (x, z): the ground, a roof, a dune.
func _surface_y(at: Vector2) -> float:
	return diorama.top_at(at.x, at.y)


func _set_weather() -> void:
	if _weather == null or not is_instance_valid(_weather):
		return
	var save := _save()
	var designed: bool = save == null or save.weather_pref != "clear"
	var kind: String = WEATHER.get(stage, "")
	var dust_on: bool = (save == null or save.dust) and kind.contains("dust")
	_weather.dust(dust_on, str(diorama.layout.get("mood", "day")) == "evening")
	_weather.auto(designed and kind.contains("rain"), designed and kind.contains("gusts"))


func _on_level_won() -> void:
	var won := stage
	var r := _round
	var save := _save()
	var took := _t - _started_at
	var par: float = PAR.get(won, 90.0)
	var earned := 3 if took <= par else (2 if took <= par * 2.0 else 1)
	if save:
		save.table_stars[won] = maxi(save.table_stars.get(won, 0), earned)
		save.save()
	TableFx.stars(diorama.stage, Vector3(0, 9.0, 0), earned)
	if won == 9 and (save == null or save.weather_pref != "clear"):
		_weather.shower(9.0)   # the farm is watered: a shower to go with it
	get_tree().create_timer(12.0 if won >= LAST_LEVEL else 4.5).timeout.connect(func():
		if r != _round or diorama == null:
			return  # the player already started again
		if won >= LAST_LEVEL:
			_show_menu("thanks")   # the end: thank you, and where to find the studio's games
			return
		# the old scene sinks into the ground, which stays; the next one rises out of it
		var tw := create_tween()
		tw.tween_method(diorama.set_rise, 1.0, 0.0, RISE_TIME)
		tw.tween_callback(func():
			if r == _round:
				_play(won + 1, true)))


# --- sound ----------------------------------------------------------------------------------------

## Three quiet buses: the music, every sound effect, and the surroundings (the owner wants
## all of it soft). Their levels follow the settings.
func _setup_audio() -> void:
	for b in [["Music", MUSIC_DB], ["SFX", SFX_DB], ["Ambience", AMBIENCE_DB]]:
		if AudioServer.get_bus_index(b[0]) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b[0])
			AudioServer.set_bus_send(i, "Master")
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(b[0]), b[1])
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Ambience"
	add_child(_ambience)
	_apply_settings()
	_play_music("day")


## The level's loop (day, evening or night), faded across when it changes.
func _play_music(mood: String) -> void:
	if mood == _music_mood or _music == null:
		return
	var path := MUSIC % mood
	if not ResourceLoader.exists(path):
		return
	_music_mood = mood
	_crossfade(_music, path)


## The scene's surroundings: birds, wind, a fire, the night, the market, running water.
func _play_ambience(kind: String) -> void:
	var path := AMBIENCE % kind
	if kind == "" or not ResourceLoader.exists(path):
		var tw := create_tween()
		tw.tween_property(_ambience, "volume_db", -40.0, 1.2)
		tw.tween_callback(_ambience.stop)   # stopped, so the same sound later starts afresh
		return
	if _ambience.stream and _ambience.stream.resource_path == path and _ambience.playing:
		return
	_crossfade(_ambience, path)


func _crossfade(player: AudioStreamPlayer, path: String) -> void:
	var st := load(path) as AudioStreamOggVorbis
	if st == null:
		return
	st.loop = true
	var tw := create_tween()
	if player.playing:
		tw.tween_property(player, "volume_db", -40.0, 1.2)
	tw.tween_callback(func():
		player.stream = st
		player.volume_db = -40.0
		player.play())
	tw.tween_property(player, "volume_db", 0.0, 2.0)


## Light for the level's time of day: "day", "evening" (low warm sun) or "night" (dim and
## blue, so lamps and fires carry the scene). Only the diorama is lit; the room is passthrough.
var _mood := "day"          # the light on the scene now


func _apply_mood(mood: String, seconds := 0.8) -> void:
	_mood = mood
	var looks := {
		"day": [Vector3(-48, 32, 0), Color("ffffff"), 0.95, Color("fff6ea"), 0.55],
		"evening": [Vector3(-16, 60, 0), Color("ffb36b"), 0.75, Color("f2c9a0"), 0.42],
		"night": [Vector3(-40, -30, 0), Color("9fb4e0"), 0.38, Color("7f8fb8"), 0.45],
		"dawn": [Vector3(-14, -100, 0), Color("ffc9a8"), 0.62, Color("e9cfc6"), 0.44],
	}
	var l: Array = looks.get(mood, looks.day)
	var tw := create_tween().set_parallel()
	tw.tween_property(sun, "rotation_degrees", l[0], seconds)
	tw.tween_property(sun, "light_color", l[1], seconds)
	tw.tween_property(sun, "light_energy", l[2], seconds)
	tw.tween_property(env, "ambient_light_color", l[3], seconds)
	tw.tween_property(env, "ambient_light_energy", l[4], seconds)


# The time of day goes round by itself (unless switched off in the menu): day, sunset, night,
# dawn, each for a while, from the level's own time. Levels 7 (the stars) and 10 (the old
# men's tracers) stay at night.
const SKY := [["day", 75.0], ["evening", 30.0], ["night", 45.0], ["dawn", 25.0]]   # about three minutes round
const ALWAYS_NIGHT := [7, 11]
var _sky := -1              # where in SKY the day is; -1: it stays as it is
var _sky_left := 0.0


func _start_sky(mood: String) -> void:
	_apply_mood(mood)
	if diorama:
		diorama.set_night(mood == "night")
	_play_music("evening" if mood == "dawn" else mood)
	var save := _save()
	_sky = -1
	if stage in ALWAYS_NIGHT or (save and not save.day_cycle):
		return
	for i in SKY.size():
		if SKY[i][0] == mood:
			_sky = i
	if _sky < 0:
		_sky = 0
	_sky_left = SKY[_sky][1]


func _tick_sky(dt: float) -> void:
	if _sky < 0:
		return
	_sky_left -= dt
	if _sky_left > 0.0:
		return
	_sky = (_sky + 1) % SKY.size()
	_sky_left = SKY[_sky][1]
	var mood: String = SKY[_sky][0]
	_apply_mood(mood, 10.0)   # slowly, as the light really changes
	if diorama:
		diorama.set_night(mood == "night")
	_play_music("evening" if mood == "dawn" else mood)


# --- the table ------------------------------------------------------------------------------------

## Puts the diorama in front of the player at about table height, the gate facing them.
func _place_table() -> void:
	var head := _head()
	var fwd := -head.basis.z
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var table := _nearest_table(head, fwd)
	if not table.is_empty():
		# on the real table: centred on its top, sized to fit it (the island is 0.66 m across at 1x)
		var fit: float = minf(table.size.x, table.size.y) * 0.95 / 0.66
		table_k = clampf(minf(table_k, fit), 0.4, 3.0)
		var c: Vector3 = table.center
		var to := Vector3(head.origin.x - c.x, 0, head.origin.z - c.z)
		var face := -to.normalized() if to.length() > 0.05 else fwd
		diorama.global_transform = Transform3D(Basis.looking_at(face, Vector3.UP).scaled(Vector3.ONE * table_k), c + Vector3(0, 0.005, 0))
		return
	var y := maxf(0.55, head.origin.y - 0.55) if head.origin.y > 0.3 else 0.75
	diorama.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP).scaled(Vector3.ONE * table_k),
		Vector3(head.origin.x, y, head.origin.z) + fwd * 0.7)


## The detected table closest in front of the player (within 3 m), or {}.
func _nearest_table(head: Transform3D, fwd: Vector3) -> Dictionary:
	if surfaces == null:
		return {}
	var best := {}
	var best_score := INF
	for s in surfaces.surfaces():
		if s.label != "table":
			continue
		var to: Vector3 = s.center - head.origin
		var flat := Vector3(to.x, 0, to.z)
		var d := flat.length()
		if d > 3.0 or d < 0.15:
			continue
		var score := d - flat.normalized().dot(fwd)
		if score < best_score:
			best_score = score
			best = s
	return best


func _on_grip_tap(_h: String) -> void:
	if diorama and card == null and not _placing:
		_begin_place()


## Placing (TablePlacer): the scene waits, hidden, while a ring follows the pointer over the
## real surfaces; the trigger sets it down there and it rises out of the surface.
func _begin_place() -> void:
	if diorama == null:
		return
	if _placer:
		_placer.queue_free()
	_placing = true
	_place_began = _t
	diorama.visible = false
	# the level waits while it is hidden: no beats, no thirst, no wind, no weather unseen
	if level:
		level.process_mode = Node.PROCESS_MODE_DISABLED
	if _weather:
		_weather.process_mode = Node.PROCESS_MODE_DISABLED
	if _hover_mark:
		_hover_mark.visible = false
	_placer = TablePlacer.new()
	_placer.surfaces = surfaces
	_placer.k = table_k
	add_child(_placer)


func _finish_place() -> void:
	table_k = _placer.fitted
	diorama.global_transform = _placer.placement()
	_placer.queue_free()
	_placer = null
	_placing = false
	_moved_by_hand = true
	diorama.visible = true
	diorama.set_rise(0.0)
	create_tween().tween_method(diorama.set_rise, 0.0, 1.0, RISE_TIME)
	TableKit.sfx(diorama, "unlock", Vector3.ZERO, -6.0)
	if xr:
		rig.pulse(_hand, 0.4, 0.06)
	if level:
		level.process_mode = Node.PROCESS_MODE_INHERIT
	if _weather:
		_weather.process_mode = Node.PROCESS_MODE_INHERIT
	# the level's clock starts when it is first on the table, and does not count the time
	# spent setting it down somewhere else later
	if _clock_running:
		_started_at += _t - _place_began
	else:
		_started_at = _t
		_clock_running = true


func _table_controls(dt: float) -> void:
	var save := _save()
	var st := rig.stick("right" if save and save.left_handed else "left")  # the other stick walks the old man
	if absf(st.x) > 0.25:
		diorama.rotate_y(-st.x * 1.4 * dt)
	if absf(st.y) > 0.25:
		var nk := clampf(table_k * exp(st.y * 0.9 * dt), 0.4, 3.0)
		var t := diorama.global_transform
		diorama.global_transform = Transform3D(t.basis.scaled(Vector3.ONE * (nk / table_k)), t.origin)
		table_k = nk
	var dh := rig.dragging_hand()
	if dh != "":
		var c: Vector3 = rig.hands[dh].grip.global_position
		if _drag.get("hand", "") != dh:
			_drag = {"hand": dh, "ctrl": c, "pos": diorama.global_position}
			_moved_by_hand = true
		diorama.global_position = _drag.pos + (c - _drag.ctrl)
	else:
		_drag = {}


func _head() -> Transform3D:
	if xr:
		return rig.head_transform()
	return desk_cam.global_transform if desk_cam else Transform3D()


func _ensure_passthrough() -> void:
	var xi := rig.xr_interface
	if xi == null:
		return
	if xi.get_supported_environment_blend_modes().has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND):
		rig.passthrough_supported = true
		_mr_on = rig.set_mode("mr") == "mr"


# --- every frame: the pointer -------------------------------------------------------------------

func _process(dt: float) -> void:
	_t += dt
	_tick_sky(dt)
	if card and xr and not _card_placed:
		_place_card()
	if _intro and not _intro_begun and (_head().origin.length() > 0.01 or _t > 1.5 or not xr):
		_intro_begun = true
		_intro.begin(_head())
	if xr and not _mr_on:
		_ensure_passthrough()
	if not xr:
		_desk_move(dt)
	if _gem:
		TableFx.gem_tick(_gem, _t)
	if xr and card == null and diorama and not _placing:
		_table_controls(dt)
	if diorama and level and level.has_method("move"):
		level.move(_hero_stick() if card == null and not _placing else Vector2.ZERO)
	# the pointing hand's ray, and whether its trigger is down (the mouse on desktop)
	_ptr_drawn = xr or not rig.fake_ray.is_empty()
	var ray := []
	var down := false
	var pressed := false
	if xr:
		for hand in ["right", "left"]:
			if not rig.aiming(hand):
				rig.set_pointer(hand, null, false)
				continue
			var c: XRController3D = rig.hands[hand].aim
			var d: bool = c.is_button_pressed("trigger_click") or c.get_float("trigger") > 0.6
			if d and not _down.get(hand, false):
				_hand = hand
				pressed = true
			_down[hand] = d
		if rig.aiming(_hand):
			down = _down.get(_hand, false)
			ray = rig.press_ray(_hand) if pressed else rig.ray(_hand)
			var other := "left" if _hand == "right" else "right"
			if rig.aiming(other):
				rig.set_pointer(other, null, false)   # only the pointing hand shows its ray
	elif not rig.fake_ray.is_empty():   # screenshots: --hand draws the headset's pointer
		ray = rig.fake_ray
	elif desk_cam:
		var mp := get_viewport().get_mouse_position()
		ray = [desk_cam.project_ray_origin(mp), desk_cam.project_ray_normal(mp)]
		down = _mouse_down
		pressed = down and not _down.get("mouse", false)
		_down["mouse"] = down
	if not down:
		_swallow = false
	if ray.is_empty():
		if level and diorama:
			level.pointer(false, null)
		return
	if _intro:
		if _ptr_drawn:
			var ih = _intro.hover(ray[0], ray[1]) if _intro_begun else null
			if ih != null:
				ih["pressed"] = down
				ih["ui"] = true
			rig.set_pointer(_hand, ih, true)
		if pressed and _intro_begun:
			_intro.press()
		return
	if card:
		var h = card.hover(ray[0], ray[1])
		if _ptr_drawn:
			if h != null:
				h["pressed"] = down
				h["ui"] = true
			rig.set_pointer(_hand, h, true)
		if pressed:
			_swallow = true
			card.press()
		if level and diorama:
			level.pointer(false, null)
		_show_hover({})
		return
	if _placing and _placer:
		var save := _save()
		var st := rig.stick("right" if save and save.left_handed else "left") if xr else Vector2.ZERO
		_placer.update(ray, _head(), st, dt)
		if _ptr_drawn:
			rig.set_pointer(_hand, {"point": _placer.spot(), "interactive": true, "ui": true, "pressed": down} if _placer.has_spot else null, true)
		if pressed and _placer.has_spot:
			_swallow = true
			_finish_place()
		if level:
			level.pointer(false, null)
		return
	if diorama == null or level == null:
		if _ptr_drawn:
			rig.set_pointer(_hand, null, true)   # between levels: a plain ray, never one left frozen
		return
	# the first thing the ray meets in the scene: pieces behind it cannot be picked through it
	var wall := _scene_hit(ray)
	TableKit.set_wall(ray[0], (ray[0] as Vector3).distance_to(wall.point) if not wall.is_empty() else INF,
		diorama.model.global_basis.x.length() * 0.6, _hover_id)
	var info := _level_hover(ray, wall)
	_show_hover(info)
	if pressed and info.get("id", "") == "__gem":
		_swallow = true
		TableFx.collect(_gem)
		_gem = null
		var save := _save()
		if save:
			save.table_gems[stage] = true
			save.save()
		if _ptr_drawn:
			rig.pulse(_hand, 0.5, 0.08)
	if level.has_method("aim"):
		level.aim(ray[0], ray[1])
	var p = diorama.model_point(ray[0], ray[1])
	level.pointer(down and not _swallow, p)
	if _ptr_drawn:
		var at = info.get("point", null)
		var hit = null
		if at != null:
			hit = {"point": at, "normal": info.get("normal", diorama.model.global_basis.y.normalized()),
				"interactive": info.has("id") or info.get("target", false), "pressed": down}
		rig.set_pointer(_hand, hit, true)


## What the ray is on: a level's target or the gem ({id, box, point, normal} with a world
## point), else the ground ({point}), else {}.
func _level_hover(ray: Array, wall: Dictionary) -> Dictionary:
	var boxes := {}
	if level.has_method("hover_boxes"):
		boxes = level.hover_boxes()
	else:
		var b = level.get("_boxes")
		if b is Dictionary:
			boxes = b
	var assist = level.get("assist")
	if _gem:
		boxes = boxes.duplicate()
		boxes["__gem"] = AABB(_gem.position - Vector3(0.5, 0, 0.5), Vector3(1.0, 1.2, 1.0))
	var h := TableKit.ray_hit(diorama.stage, ray, boxes, assist != false, _hover_id)
	if h.is_empty() and _gem:
		# the gem is small: it alone gets a wider snap
		var g := TableKit.ray_hit(diorama.stage, ray, {"__gem": boxes["__gem"]}, true)
		if not g.is_empty():
			h = g
	if not h.is_empty():
		if h.get("snapped", false):
			# the magnet: near a piece the pointer jumps onto it; its ring lies at the piece's
			# foot (not on its box's top in the air) and the short line leans towards it
			var b: AABB = h.box
			h.point = diorama.stage.to_global(Vector3(b.get_center().x, b.position.y, b.get_center().z))
			h.normal = diorama.stage.global_basis.y.normalized()
			return h
		if not wall.is_empty() and (h.box as AABB).grow(0.2).has_point(diorama.stage.to_local(wall.point)):
			# the ray reaches the ground (or roof) inside the piece's box: the ring lies there,
			# under the piece, not on the box's invisible top in the air
			h.point = wall.point
			h.normal = wall.normal
			return h
		h.point = diorama.stage.to_global(h.point)
		h.normal = (diorama.stage.global_basis * (h.normal as Vector3)).normalized()
		return h
	if level.has_method("hover_point"):   # a level with targets that are not boxes (the sky)
		var hp = level.hover_point(ray)
		if hp != null:
			return {"point": hp, "normal": -(ray[1] as Vector3), "target": true}
	# nothing to pick: the ray stops on the first thing it meets in the scene (a wall, a
	# roof, a dune), never passing through it to the ground behind
	if not wall.is_empty():
		return wall
	# off the scene mesh: the ground plane, but only on the island itself (past its edge the
	# ray goes on into the room instead of stopping on nothing in mid-air)
	var p = diorama.model_point(ray[0], ray[1])
	if p != null and Vector2(p.x, p.z).length() < ISLAND_R:
		return {"point": diorama.model.to_global(p)}
	return {}


## The first thing the ray meets in the scene itself (the ground, the roofs, the palms; not the
## level's moving pieces, the animals or anything hidden): {point, normal} or {}. Walls do not
## stop it: the pointer goes through a wall's side and over its thin top to what is behind,
## so a courtyard's wall is never in the way of what is inside.
func _scene_hit(ray: Array) -> Dictionary:
	if diorama == null or diorama.model == null:
		return {}
	var tm := diorama.scene_mesh()
	if tm == null:
		return {}
	var o := diorama.model.to_local(ray[0])
	var d := (diorama.model.to_local((ray[0] as Vector3) + (ray[1] as Vector3)) - o).normalized()
	for i in 8:
		var hit := tm.intersect_ray(o, d)
		if hit.is_empty():
			return {}
		var n: Vector3 = hit.get("normal", Vector3.UP)
		if n.dot(d) > 0.0:
			n = -n   # the face the ray meets, so the ring lies on the near side
		var at: Vector3 = hit.position
		if absf(n.y) > WALL_NY and not _thin_top(at):
			return {"point": diorama.model.to_global(at), "normal": (diorama.model.global_basis * n).normalized()}
		o = at + d * 0.05   # a wall's side or its top: on through it
	return {}


const WALL_NY := 0.55   # a face steeper than this is a wall's side


## A wall's top: a narrow ledge high above the ground on either side of it (model metres).
func _thin_top(at: Vector3) -> bool:
	if at.y < 0.8:
		return false
	var low := 0
	for off in [Vector2(0.8, 0), Vector2(-0.8, 0), Vector2(0, 0.8), Vector2(0, -0.8)]:
		if diorama.top_at(at.x + off.x, at.z + off.y) < at.y - 1.0:
			low += 1
	return low >= 2


## Rings the thing under the pointer (and a light tick in the hand when it changes).
func _show_hover(info: Dictionary) -> void:
	var id: String = info.get("id", "")
	if _hover_mark == null or not is_instance_valid(_hover_mark):
		return
	if id != _hover_id:
		_hover_id = id
		if id != "" and xr:
			rig.pulse(_hand, 0.12, 0.015)
	_hover_mark.visible = id != ""
	if id == "":
		return
	var b: AABB = info.box
	var pulse := 1.0 + 0.05 * sin(_t * 6.0)
	_hover_mark.position = Vector3(b.get_center().x, b.position.y + 0.05, b.get_center().z)
	_hover_mark.scale = Vector3(maxf(b.size.x * 0.62, 0.45) * pulse, 1.0, maxf(b.size.z * 0.62, 0.45) * pulse)


## The stick that walks the old man (right; left when the player is left-handed), or the
## arrow keys on desktop, turned into a direction on the diorama's ground (its x, z).
func _hero_stick() -> Vector2:
	var st := Vector2.ZERO
	var basis := Basis()
	if xr:
		var save := _save()
		st = rig.stick("left" if save and save.left_handed else "right")
		if st.length() < 0.2:
			return Vector2.ZERO
		basis = rig.head_transform().basis
	else:
		st = Vector2(float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)),
			float(Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_DOWN)))
		if st == Vector2.ZERO or desk_cam == null:
			return Vector2.ZERO
		basis = desk_cam.global_basis
	var fwd := -basis.z
	fwd.y = 0
	var right := basis.x
	right.y = 0
	var world := right.normalized() * st.x + fwd.normalized() * st.y
	var local := diorama.model.global_basis.inverse() * world
	var v := Vector2(local.x, local.z)
	return v.normalized() * minf(st.length(), 1.0) if v.length() > 0.0001 else Vector2.ZERO


func _unhandled_input(e: InputEvent) -> void:
	if xr:
		return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_mouse_down = mb.pressed
	elif e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_yaw -= (e as InputEventMouseMotion).relative.x * 0.005
		_pitch = clampf(_pitch - (e as InputEventMouseMotion).relative.y * 0.005, -1.4, 1.2)
	elif e is InputEventKey and e.pressed:
		match (e as InputEventKey).physical_keycode:
			KEY_ESCAPE: _toggle_menu()
			KEY_Q: if diorama: diorama.rotate_y(0.2)
			KEY_E: if diorama: diorama.rotate_y(-0.2)


func _desk_move(dt: float) -> void:
	if desk_cam == null:
		return
	desk_cam.rotation = Vector3(_pitch, _yaw, 0)
	var v := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if v != Vector2.ZERO:
		var b := Basis(Vector3.UP, _yaw)
		rig.position += (b.x * v.x + b.z * v.y) * 1.0 * dt


# --- screenshots ----------------------------------------------------------------------------

## Store art: the game's name (and the studio's) in the sky above the table. "line": a wide
## picture; "stack": a tall or square one (the same words, smaller).
func _store_title(kind: String) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var vp := get_viewport().get_visible_rect().size
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.size = Vector2(vp.x, vp.y * 0.34)
	box.position = Vector2(0, vp.y * (0.06 if kind == "stack" else 0.05))
	layer.add_child(box)
	var big := minf(vp.x * (0.1 if kind == "stack" else 0.075), vp.y * 0.15)
	for row in [["مفاتيح — Mafateeh", big, int(big * 0.09)], ["عبودين قيمز — Aboden Games", big * 0.34, int(big * 0.05)]]:
		var l := Label.new()
		l.text = row[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", TableMenu.font())
		l.add_theme_font_size_override("font_size", int(row[1]))
		l.add_theme_color_override("font_color", Color("4a2c16"))
		l.add_theme_color_override("font_outline_color", Color("fbf0da"))
		l.add_theme_constant_override("outline_size", row[2])
		box.add_child(l)


## Store art: a plain room round the diorama, as the player sees it through passthrough: a
## wooden table under it, a floor, the wall behind. Nothing of the game's own UI.
func _store_room() -> void:
	var at := diorama.global_position
	var half := 0.66 * table_k * 0.5
	var room := Node3D.new()
	add_child(room)
	var wood := TableKit.mat(Color("8a5a36"), 0.55)
	var floor_m := TableKit.mat(Color("b9a184"), 0.8)
	var top := Vector3(half * 2.8, 0.04, half * 2.5)
	TableKit.box(room, top, wood, at - Vector3(0, 0.02, 0))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			TableKit.box(room, Vector3(0.05, at.y - 0.04, 0.05), wood,
				Vector3(at.x + sx * (top.x / 2 - 0.06), (at.y - 0.04) / 2, at.z + sz * (top.z / 2 - 0.06)))
	TableKit.box(room, Vector3(12, 0.02, 12), floor_m, Vector3(at.x, -0.01, at.z))
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("e9dfd0")
	if _hover_mark:
		_hover_mark.visible = false


func _screenshot() -> void:
	for i in 20:
		await get_tree().process_frame
	if diorama:
		table_k = float(_args.get("k", "1"))  # --k=N: the diorama N times its usual size
		_place_table()
		if _args.has("room"):   # store art: the scene on a table in a room, as in mixed reality
			_store_room()
		diorama.rotate_y(deg_to_rad(float(_args.get("turn", "0"))))  # --turn=deg: see another side
	if card:
		_place_card(true)
	if level and _args.has("demo"):
		level.demo()
	if _args.has("place"):
		_begin_place()
	if _weather and _args.has("weather"):   # --weather=rain|gust|dust: show it now
		match str(_args.weather):
			"rain": _weather.shower(30.0)
			"gust": _weather.gust_now()
			"dust": _weather.dust(true)
	if _args.has("hand"):   # --hand=x,y,z,tx,ty,tz: the right hand at x,y,z pointing at tx,ty,tz (world)
		var h := str(_args.hand).split_floats(",")
		var o := Vector3(h[0], h[1], h[2])
		rig.fake_ray = [o, (Vector3(h[3], h[4], h[5]) - o).normalized()]
		_hand = "right"
	if _args.has("solved") and level and level.has_method("_win"):   # --solved=1: the level's own ending, now
		level._win()
	if _args.has("win"):   # --win=1: as if the level were just won (stars, weather, the end)
		_on_level_won()
	for i in int(_args.get("wait", "40")):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_args.screenshot)
	get_tree().quit()
