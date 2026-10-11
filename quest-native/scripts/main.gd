extends Node3D
## Entry point. Starts OpenXR straight into the immersive experience (mixed
## reality by default, VR on request or when passthrough is unavailable).
## Without a headset (desktop development / automated screenshots) it falls
## back to an orbit camera with mouse and keyboard.
##
## Command-line (after "--"): --level=N --time=day --weather=rain --mode=vr
##   --screenshot=path.png [--yaw=deg --pitch=deg --zoom=f] [--intro=seconds]

const ROTATE_SPEEDS := [1.0, 1.6, 2.4]  # rad/s at full deflection: slow, normal, fast
const SNAP_ANGLE := PI / 6.0
const DEFAULT_BOARD_SCALE := 0.12
const RESIZE_SPEED := 0.75

var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var rig: XRRig
var board: BoardPlacement
var game: Game
var surfaces: SceneSurfaces
var sky: SkyWeather
var audio: GameAudio
var menu: SettingsMenu
var desktop_cam: Camera3D
var xr := false
var _placed := false
var _session_time := -1.0
var _args := {}
var _cam_yaw := 0.55
var _cam_pitch := 0.78
var _cam_zoom := 1.0
var _drag_hand := ""
var intro: StudioIntro
var _intro_started := false
var _snap_armed := true
var injected_move := Vector2.ZERO  # automated tests drive the stick through the normal frame path


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.tonemap_exposure = 0.92
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 4.0 if _args.get("xr", "1") != "0" and not _args.has("screenshot") else 40.0
	sun.shadow_blur = 1.5
	add_child(sun)

	rig = XRRig.new()
	rig.name = "XROrigin3D"
	add_child(rig)
	rig.setup(env)

	board = BoardPlacement.new()
	board.name = "Board"
	add_child(board)
	game = Game.new()
	game.name = "Game"
	board.add_child(game)

	sky = SkyWeather.new()
	sky.name = "SkyWeather"
	add_child(sky)
	sky.setup(env, sun, board, game)

	audio = GameAudio.new()
	audio.name = "Audio"
	add_child(audio)
	audio.setup(board, game, sky)

	menu = SettingsMenu.new()
	menu.name = "Settings"
	add_child(menu)
	menu.setup(self)

	game.level_completed.connect(_on_level_completed)
	game.level_loaded.connect(func(_n): apply_sky())
	game.feedback.connect(_haptic_feedback)

	xr = not _args.has("screenshot") and _args.get("xr", "1") != "0" and rig.start()
	if xr:
		rig.trigger_pressed.connect(_on_trigger)
		rig.grip_tapped.connect(_on_grip_tap)
		rig.grip_drag_started.connect(_on_drag_start)
		rig.grip_drag_ended.connect(_on_drag_end)
		rig.menu_pressed.connect(_on_menu_button)
		rig.focus_changed.connect(_on_focus)
		rig.session_started.connect(_on_session)
		surfaces = SceneSurfaces.new()
		add_child(surfaces)
		surfaces.attach(rig)
		surfaces.surfaces_changed.connect(func(): board.surfaces = surfaces.surfaces())
		board.set_board_scale(Save.board_scale)
		board.visible = false
	else:
		_setup_desktop()
	var start := int(_args.get("level", Save.current_level))
	if not Save.can_play(start) and not (_args.has("screenshot") or _args.has("level")):
		start = Save.current_level
	game.load_level(start)
	if not xr and _args.has("intro"):
		_start_intro.call_deferred()
	if _args.has("screenshot"):
		_screenshot.call_deferred()
	# Store builds only: verify the purchase within the first seconds of launch.
	var entitlement := StoreEntitlement.new()
	entitlement.name = "StoreEntitlement"
	add_child(entitlement)
	entitlement.run.call_deferred()


# --- XR -------------------------------------------------------------------------------

func _on_session() -> void:
	_session_time = 0.0
	var m := rig.set_mode(_args.get("mode", Save.mode))
	sky.set_mixed_reality(m == "mr")


## Weather follows the level unless the player chose "always clear"; command-line
## and developer overrides still win.
func apply_sky() -> void:
	var weather: String = _args.get("weather", "")
	if weather == "" and Save.weather_pref == "clear":
		weather = "clear"
	sky.apply_level(game.level, _args.get("time", ""), weather)


func _start_intro() -> void:
	_intro_started = true
	if not Save.show_intro and not _args.has("intro"):
		return
	intro = StudioIntro.new()
	intro.name = "StudioIntro"
	add_child(intro)
	if not xr:
		_update_desktop_camera()
	var head := rig.head_transform() if xr else desktop_cam.global_transform
	intro.play(head, not _args.has("noveil"), xr)
	intro.finished.connect(func(): intro = null)


func intro_playing() -> bool:
	return intro != null and intro.is_playing()


func _on_menu_button() -> void:
	if intro_playing():
		intro.skip()
		return
	menu.toggle(rig.head_transform())


## Hands: by default the right stick moves the hero and the left turns/resizes the
## board; "left-handed" in the settings swaps them.
func move_hand() -> String:
	return "left" if Save.left_handed else "right"


func board_hand() -> String:
	return "right" if Save.left_handed else "left"


func pulse_ui() -> void:
	if xr:
		rig.pulse("right", 0.2, 0.03)
		rig.pulse("left", 0.2, 0.03)


func _haptic_feedback(event: String, _at: Vector3) -> void:
	if not xr:
		return
	match event:
		"reject", "sequence_wrong": rig.pulse(move_hand(), 0.35, 0.06)
		"push_start": rig.pulse(move_hand(), 0.2, 0.12)
		"key", "gem", "unlock", "lever", "circuit", "sequence", "mirror", "dial", "portal", \
		"pickup_weight", "place_weight", "pickup_brick", "place_brick":
			rig.pulse(move_hand(), 0.25, 0.04)
		"solved", "exit": rig.pulse(move_hand(), 0.5, 0.12)


func reset_board_size() -> void:
	board.set_board_scale(DEFAULT_BOARD_SCALE)
	Save.board_scale = board.board_scale
	Save.save()
	menu.toast("أُعيد حجم اللوحة الافتراضي", 2.5)


func _place_board() -> void:
	var head := rig.head_transform()
	if rig.mode == "mr" and board.surfaces.size() > 0 and board.place_on_surface(head):
		pass
	else:
		board.place_in_front(head, 0.62)
	board.visible = true
	_placed = true
	menu.notify_placement(board.placement_source)
	if not Save.hint_shown:
		show_controller_hints()


var _hints: Array = []
var _hint_t := 0.0


## Compact labels on the controllers (no instruction panel): shown once on first
## launch, and again on request from the settings.
func show_controller_hints() -> void:
	if not xr:
		return
	for l in _hints:
		l.queue_free()
	_hints.clear()
	var texts := {move_hand(): "عصا التحكم: تحريك الشخصية\nالزناد: تفاعل",
		board_hand(): "عصا التحكم: تدوير وتكبير\nالقبضة: تموضع اللوحة"}
	texts["left"] += "\n☰ الإعدادات"
	for hand in texts:
		var l := Label3D.new()
		l.text = texts[hand]
		l.pixel_size = 0.00035
		l.font_size = 40
		l.outline_size = 8
		l.font = menu._font
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = Vector3(0, 0.06, 0.02)
		rig.hands[hand].grip.add_child(l)
		_hints.append(l)
	_hint_t = 15.0


func _update_hints(delta: float, moved: bool) -> void:
	if _hints.is_empty():
		return
	_hint_t -= delta * (3.0 if moved else 1.0)
	for l in _hints:
		l.modulate.a = clampf(_hint_t / 2.0, 0.0, 1.0)
		l.outline_modulate.a = l.modulate.a
	if _hint_t <= 0.0:
		for l in _hints:
			l.queue_free()
		_hints.clear()
		Save.hint_shown = true
		Save.save()


func _on_trigger(hand: String, origin: Vector3, direction: Vector3) -> void:
	if intro_playing():
		intro.skip()
		return
	if menu.handle_ray(origin, direction):
		rig.pulse(hand, 0.15, 0.025)
		return
	if not _placed or not board.visible:
		return
	var r := board.to_local_ray(origin, direction)
	game.activate(game.pick(r[0], r[1]))


func _on_grip_tap(_hand: String) -> void:
	if surfaces:
		board.surfaces = surfaces.surfaces()
	_place_board()
	audio.ui("recenter")


func _on_drag_start(hand: String) -> void:
	_drag_hand = hand
	board.begin_drag(rig.hands[hand].grip.global_transform)


func _on_drag_end(_hand: String) -> void:
	_drag_hand = ""
	if surfaces:
		board.surfaces = surfaces.surfaces()
	board.end_drag(rig.head_transform())
	menu.notify_placement(board.placement_source)


func _on_focus(f: bool) -> void:
	game.motor.cancel()
	audio.set_paused(not f)


func set_mode(m: String) -> void:
	m = rig.set_mode(m) if xr else m
	sky.set_mixed_reality(m == "mr")
	Save.mode = m
	Save.save()


## Right stick in the board's frame: up = away from the viewer.
func _move_vector() -> Vector2:
	var raw := HeroMotor.read_stick(rig.stick(move_hand()))
	if raw == Vector2.ZERO:
		return Vector2.ZERO
	var fwd := -rig.head_transform().basis.z
	var local := board.global_transform.basis.inverse() * fwd
	var f := Vector2(local.x, local.z)
	if f.length_squared() < 1e-6:
		return Vector2.ZERO
	f = f.normalized()
	var right := Vector2(-f.y, f.x)
	return (right * raw.x + f * raw.y).limit_length(1.0)


func _process(delta: float) -> void:
	if xr:
		if _session_time >= 0.0 and not _placed:
			_session_time += delta
			if _session_time > 0.3 and not _intro_started:
				_start_intro()
			if _session_time > 0.6 and _intro_started and not intro_playing():
				_place_board()
		if _placed and rig.focused and not menu.is_open():
			_board_stick(delta)
		if _drag_hand != "":
			board.update_drag(rig.hands[_drag_hand].grip.global_transform)
		var move := _move_vector() if (_placed and rig.focused and not menu.is_open()) else Vector2.ZERO
		if not rig.tracked(move_hand()):
			move = Vector2.ZERO
		game.tick(delta, move)
		_update_hints(delta, move != Vector2.ZERO)
		_update_pointers()
	else:
		game.tick(delta, _desktop_move())
		_update_desktop_camera()


## Board stick: x turns the board (smoothly, or in 30° steps), y resizes it.
func _board_stick(delta: float) -> void:
	var raw := rig.stick(board_hand())
	var stick := HeroMotor.read_stick(raw, 0.25)
	if Save.turn_mode == "snap":
		if absf(raw.x) < 0.3:
			_snap_armed = true
		elif _snap_armed and absf(raw.x) > 0.7:
			_snap_armed = false
			board.rotate_board(-signf(raw.x) * SNAP_ANGLE)
			rig.pulse(board_hand(), 0.12, 0.02)
	elif stick.x != 0.0:
		board.rotate_board(-stick.x * ROTATE_SPEEDS[Save.turn_speed] * delta)
	if stick.y != 0.0 and absf(stick.y) > absf(stick.x) * 0.5:
		board.set_board_scale(board.board_scale * exp(stick.y * RESIZE_SPEED * delta))
		Save.board_scale = board.board_scale


func _update_pointers() -> void:
	for hand in ["left", "right"]:
		if not rig.tracked(hand):
			rig.set_pointer(hand, null, false)
			continue
		var r := rig.ray(hand)
		var hit = menu.ray_hit(r[0], r[1])
		if hit == null and _placed:
			var lr := board.to_local_ray(r[0], r[1])
			var h := game.pick(lr[0], lr[1])
			if not h.is_empty():
				hit = {"point": board.to_world_point(h.point), "interactive": h.interactive}
		rig.set_pointer(hand, hit, true)


func _on_level_completed(n: int) -> void:
	Save.mark_completed(n)
	if n < LevelData.COUNT:
		game.go_to_level(n + 1)
	else:
		menu.show_credits()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if game and game.motor:
			game.motor.cancel()
		if audio:
			audio.set_paused(true)
		Save.save()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if audio and (not xr or rig.focused):
			audio.set_paused(false)


# --- desktop fallback ---------------------------------------------------------------------

func _setup_desktop() -> void:
	desktop_cam = Camera3D.new()
	desktop_cam.fov = 40.0
	add_child(desktop_cam)
	desktop_cam.current = true
	sky.follow_board = false
	rig.visible = false
	board.scale = Vector3.ONE
	board.position = Vector3.ZERO
	board.visible = true
	_placed = true
	_cam_yaw = deg_to_rad(float(_args.get("yaw", 32)))
	_cam_pitch = deg_to_rad(float(_args.get("pitch", 45)))
	_cam_zoom = float(_args.get("zoom", 1.0))
	set_mode(_args.get("mode", "vr"))


func _update_desktop_camera() -> void:
	var target := Vector3(0, 0.6 + (1.0 if game.state and game.state.def.get("storeys", false) else 0.0), -0.4)
	if _args.has("focus_hero") and game.motor:
		target = game.hero.global_position + Vector3(0, 0.55, 0)
	var dist := 15.5 / _cam_zoom
	desktop_cam.position = target + Vector3(sin(_cam_yaw) * cos(_cam_pitch), sin(_cam_pitch), cos(_cam_yaw) * cos(_cam_pitch)) * dist
	desktop_cam.look_at(target)


func _desktop_move() -> Vector2:
	if injected_move != Vector2.ZERO:
		return injected_move
	var v := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)))
	if v == Vector2.ZERO:
		return v
	var f := Vector2(-sin(_cam_yaw), -cos(_cam_yaw))
	var right := Vector2(-f.y, f.x)
	return (right * v.x + f * v.y).limit_length(1.0)


func _unhandled_input(event: InputEvent) -> void:
	if xr:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var o := desktop_cam.project_ray_origin(event.position)
			var d := desktop_cam.project_ray_normal(event.position)
			var r := board.to_local_ray(o, d)
			game.activate(game.pick(r[0], r[1]))
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_zoom = minf(_cam_zoom * 1.1, 3.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_zoom = maxf(_cam_zoom / 1.1, 0.5)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
		_cam_yaw -= event.relative.x * 0.005
		_cam_pitch = clampf(_cam_pitch + event.relative.y * 0.004, 0.2, 1.4)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R: game.restart()
			KEY_N: game.go_to_level(game.level % LevelData.COUNT + 1)
			KEY_P: game.go_to_level((game.level + LevelData.COUNT - 2) % LevelData.COUNT + 1)
			KEY_T: sky.cycle_time()
			KEY_Y: sky.toggle_rain()


func _title_overlay(layout: String) -> void:
	## Store cover art: the exact app name, inside the safe (non-bleed) area.
	var layer := CanvasLayer.new()
	add_child(layer)
	var size := get_viewport().get_visible_rect().size
	var font: FontFile = menu._font
	var lines: Array = ["مفاتيح — Mafateeh"] if layout == "line" else ["مفاتيح", "Mafateeh"]
	var big := size.y * (0.13 if layout == "line" else 0.12)
	var y := size.y * (0.08 if layout != "bottom" else 0.62)
	for i in lines.size():
		var l := Label.new()
		l.text = lines[i]
		l.add_theme_font_override("font", font)
		var fs := int(big if i == 0 else big * 0.55)
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", Color("fff3df"))
		l.add_theme_color_override("font_outline_color", Color(0.22, 0.12, 0.06, 0.95))
		l.add_theme_constant_override("outline_size", int(fs * 0.12))
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
		l.add_theme_constant_override("shadow_offset_y", int(fs * 0.05))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector2(0, y)
		l.size = Vector2(size.x, fs * 1.4)
		layer.add_child(l)
		y += fs * 1.5


func _screenshot() -> void:
	if _args.has("nocard"):
		menu._card_t = 0.0
		menu._card.visible = false
	if _args.has("title"):
		_title_overlay(_args.title)
	if _args.has("noscenery"):
		sky.scenery.visible = false
	for i in 20:
		game.tick(1.0 / 60.0, Vector2.ZERO)
		await get_tree().process_frame
	if _args.has("nocard"):
		menu._card.visible = false
	if _args.has("menu"):  # documentation shots of a menu page, e.g. --menu=levels
		desktop_cam.fov = 52.0
		var head := desktop_cam.global_transform
		menu.toggle(head.translated(Vector3(0, 0.12, 0)))
		menu.open_page(_args.menu)
		await get_tree().process_frame
	if intro:
		intro._t = float(_args.intro)
		intro._update(intro._t)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_args.screenshot)
	get_tree().quit()
