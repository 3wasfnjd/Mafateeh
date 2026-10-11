extends Node
## Boots the real main scene (desktop fallback, no headset) and drives it:
##   godot --headless --xr-mode off --path quest-native res://tests/integration_test.tscn
## Covers wiring that unit tests cannot: hero animation and footsteps, audio
## events, mechanism sounds, weather/time presets, roof-aware rain, menu,
## level transitions and save on completion.

var failures: Array = []
var main: Node


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		print("  ✗ ", msg)


func _ready() -> void:
	_run.call_deferred()


func frames(n: int, move := Vector2.ZERO) -> void:
	main.injected_move = move
	for i in n:
		await get_tree().process_frame
	main.injected_move = Vector2.ZERO


func _run() -> void:
	Save.reset_progress()
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var game: Game = main.game
	var audio: GameAudio = main.audio
	var sky: SkyWeather = main.sky
	check(not main.xr, "desktop fallback active without a headset")
	check(game.level == 1, "fresh save starts at level 1 (got %d)" % game.level)

	# --- footsteps follow animation contacts while walking -----------------------------------
	var steps := [0]
	game.hero.footstep.connect(func(_s, _a, _k): steps[0] += 1)
	await frames(90, Vector2(0, 1))
	check(steps[0] >= 3, "footsteps emitted while walking (%d)" % steps[0])
	var anim := game.hero.anim
	check(anim != null and anim.current_animation in ["walk", "carry"], "walk clip playing while moving (%s)" % (anim.current_animation if anim else "none"))
	await frames(10)
	var before: int = steps[0]
	await frames(60)
	check(steps[0] == before, "no footsteps after the stick is released")
	check(anim.current_animation in ["idle", "turn"], "idle after stopping (%s)" % anim.current_animation)

	# --- level 21 played through the game's own paths -----------------------------------------
	game.load_level(21)
	await frames(2)
	var played := {}
	game.feedback.connect(func(e, _a): played[e] = true)
	var mech := {}
	game.mechanism.connect(func(k, o, _a): mech[k + (":open" if o else ":closed")] = true)
	for type in ["brick", "brickSocket", "key", "lock", "gem"]:
		var o: Dictionary = game.state.objects.filter(func(q): return q.type == type)[0]
		check(game.motor.use_object(o), "level 21: can use %s" % type)
		for i in 72 * 14:
			main.game.tick(1.0 / 72.0, Vector2.ZERO)
			if game.motor.mode == "idle" and game.motor.route.is_empty():
				break
		await get_tree().process_frame
	check(game.state.solved, "level 21 solved through the game controller")
	for e in ["pickup_brick", "place_brick", "key", "unlock", "gem", "solved"]:
		check(played.has(e), "feedback event '%s' fired" % e)
	check(mech.has("pool_bridge:open") and mech.has("door:open") and mech.has("exit:open"),
		"mechanism sounds fire for stones, door and exit (%s)" % str(mech.keys()))
	var busy := 0
	for p in audio._pool:
		if p.stream != null:
			busy += 1
	check(busy >= 4, "audio voices were used from the pool (%d)" % busy)
	check(audio._pool.size() == GameAudio.VOICES, "voice pool is fixed size")

	# --- weather and time never touch puzzle state -------------------------------------------
	var key_before := game.state.state_key()
	for t in SkyWeather.TIMES:
		for w in [false, true]:
			sky.set_time(t, false)
			sky.set_rain(w, false)
			await frames(3)
			check(game.state.state_key() == key_before, "weather %s/%s changed puzzle state" % [t, w])
			check(main.env.ambient_light_energy >= 0.5, "ambient stays readable at %s rain=%s" % [t, w])
	# Rain stops on solid roofs.
	var roof: Array = LevelData.get_level(21).roofs[0]
	check(RainField.floor_height(game.state.def, roof[0], roof[1]) > 1.3, "rain lands on the roof, not through it")
	check(RainField.floor_height(game.state.def, -3.0, 2.5) < 0.2, "rain reaches open paving")
	# Indoors muffles rain.
	sky.set_rain(true, false)
	game.motor.pos = Vector2(roof[0], roof[1])
	await frames(150)
	check(audio._rain_lpf.cutoff_hz < 3000.0, "rain low-passed under a roof (%.0f Hz)" % audio._rain_lpf.cutoff_hz)
	game.motor.pos = Vector2(0, 2.6)
	await frames(150)
	check(audio._rain_lpf.cutoff_hz > 15000.0, "rain unfiltered outdoors")

	# --- pause / mute --------------------------------------------------------------------------
	audio.set_paused(true)
	check(AudioServer.is_bus_mute(0), "master muted while paused")
	audio.set_paused(false)
	Save.muted = true
	audio.apply_volume()
	check(AudioServer.is_bus_mute(0), "mute setting mutes master")
	Save.muted = false
	audio.apply_volume()
	check(not AudioServer.is_bus_mute(0), "unmute restores audio")

	# --- exit, completion and save --------------------------------------------------------------
	sky.set_rain(false, false)
	game.load_level(3)
	await frames(2)
	for type in ["key", "lock", "gem"]:
		var o: Dictionary = game.state.objects.filter(func(q): return q.type == type)[0]
		game.motor.use_object(o)
		for i in 72 * 14:
			main.game.tick(1.0 / 72.0, Vector2.ZERO)
			if game.motor.mode == "idle" and game.motor.route.is_empty():
				break
	check(game.motor.start_exit(), "exit reachable when solved")
	for i in 72 * 12:
		main.game.tick(1.0 / 72.0, Vector2.ZERO)
		if game.level != 3:
			break
	await frames(80)
	check(Save.unlocked_level >= 4, "completing level 3 unlocks level 4 (unlocked=%d)" % Save.unlocked_level)
	check(game.level == 4, "next level loads after the exit transition (level=%d)" % game.level)

	# --- settings menu ----------------------------------------------------------------------------
	main.menu.toggle(Transform3D(Basis(), Vector3(0, 1.4, 1.0)))
	check(main.menu.is_open(), "settings opens")
	check(not main.menu.buttons.is_empty(), "settings has buttons")
	var labels := []
	for c in main.menu.panel.get_children():
		if c is Label3D:
			labels.append(c.text)
	check(not labels.any(func(t): return t.contains("أدوات المطوّر")) or Save.dev_tools_available(),
		"developer tools hidden in the player build")
	main.menu.close()
	check(not main.menu.is_open(), "settings closes")

	Save.reset_progress()
	print("INTEGRATION: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	for f in failures:
		print("  FAIL: ", f)
	get_tree().quit(0 if failures.is_empty() else 1)
