extends Node3D
## Entry point. Starts OpenXR straight into the immersive experience (mixed
## reality by default, VR on request or when passthrough is unavailable).
## Without a headset (desktop development / automated screenshots) it falls
## back to an orbit camera with mouse and keyboard.
##
## Command-line (after "--"): --level=N --time=day --weather=rain --mode=vr
##   --screenshot=path.png [--yaw=deg --pitch=deg --zoom=f]

const ROTATE_SPEED := 1.6  # rad/s at full left-stick deflection
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
	game.level_loaded.connect(func(n): sky.apply_level(n, _args.get("time", ""), _args.get("weather", "")))

	xr = not _args.has("screenshot") and _args.get("xr", "1") != "0" and rig.start()
	if xr:
		rig.trigger_pressed.connect(_on_trigger)
		rig.grip_tapped.connect(_on_grip_tap)
		rig.grip_drag_started.connect(_on_drag_start)
		rig.grip_drag_ended.connect(_on_drag_end)
		rig.menu_pressed.connect(func(): menu.toggle(rig.head_transform()))
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
	if _args.has("screenshot"):
		_screenshot.call_deferred()


# --- XR -------------------------------------------------------------------------------

func _on_session() -> void:
	_session_time = 0.0
	var m := rig.set_mode(_args.get("mode", Save.mode))
	sky.set_mixed_reality(m == "mr")


func _place_board() -> void:
	var head := rig.head_transform()
	if rig.mode == "mr" and board.surfaces.size() > 0 and board.place_on_surface(head):
		pass
	else:
		board.place_in_front(head, 0.62)
	board.visible = true
	_placed = true
	menu.notify_placement(board.placement_source)


func _on_trigger(hand: String, origin: Vector3, direction: Vector3) -> void:
	if menu.handle_ray(origin, direction):
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
	var raw := HeroMotor.read_stick(rig.stick("right"))
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
			if _session_time > 0.6:
				_place_board()
		if _placed and rig.focused and not menu.is_open():
			var left := HeroMotor.read_stick(rig.stick("left"), 0.25)
			if left.x != 0.0:
				board.rotate_board(-left.x * ROTATE_SPEED * delta)
			if left.y != 0.0:
				board.set_board_scale(board.board_scale * exp(left.y * RESIZE_SPEED * delta))
				Save.board_scale = board.board_scale
		if _drag_hand != "":
			board.update_drag(rig.hands[_drag_hand].grip.global_transform)
		var move := _move_vector() if (_placed and rig.focused and not menu.is_open()) else Vector2.ZERO
		if not rig.tracked("right"):
			move = Vector2.ZERO
		game.tick(delta, move)
		_update_pointers()
	else:
		game.tick(delta, _desktop_move())
		_update_desktop_camera()


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


func _screenshot() -> void:
	for i in 20:
		game.tick(1.0 / 60.0, Vector2.ZERO)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_args.screenshot)
	get_tree().quit()
