extends Node3D
## Mafateeh v3 entry: a wordless start card (play in VR or in your room, or see the tabletop
## diorama of scene 1), then level 1.
##   VR: you stand life size in the Diriyah courtyard (left stick walks, right stick turns).
##   MR: passthrough; the old man, his cat, sparrows and a villager appear on your floor.
## Draw with either trigger: point at the sand and hold. Menu button: back to the card.
## Desktop (no headset): mouse drag draws, WASD walks, right-drag looks, V / M switch mode.
## Screenshot args: --screenshot=path --mode=vr|mr --cam=x,y,z,yaw,pitch --demo=n (n = path drawn and walked)

const ICONS := "res://assets/ui/icons/"
const GREEN := Color("3f8f5a")

var env: Environment
var rig: XRRig
var xr := false
var level: SandLevel
var mode := "vr"
var card: Node3D
var _buttons: Array = []  # {node, center: Vector3, r, action}
var _args := {}
var desk_cam: Camera3D
var _yaw := 0.0
var _pitch := -0.15
var _mouse_draw := false
var _snap_ready := true
var _demo := false  # screenshot demo feeds the pointer itself
var mr_scale := 0.5   # mixed reality: the scene starts at half size; left stick y resizes it
var _drag := {}       # grip drag of the mixed-reality scene: {hand, ctrl, pos}
var diorama: Diorama  # tabletop preview of scene 1 (mixed reality, no gameplay)
var table_k := 1.0    # its size on top of Diorama.BASE_SCALE (left stick y)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	env = Environment.new()
	var sky := Sky.new()
	var sm := PanoramaSkyMaterial.new()
	sm.panorama = load("res://assets/world/sky_day.jpg")
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_white = 1.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 32, 0)
	sun.light_energy = 0.95
	sun.shadow_enabled = false  # no shadows (owner's choice; also cheaper on Quest)
	add_child(sun)
	rig = XRRig.new()
	rig.name = "XRRig"
	add_child(rig)
	rig.setup(env)
	xr = not _args.has("screenshot") and rig.start()
	if not xr:
		desk_cam = Camera3D.new()
		desk_cam.fov = 70
		rig.add_child(desk_cam)
		desk_cam.position = Vector3(0, 1.62, 0)
		desk_cam.current = true
	rig.menu_pressed.connect(_show_card)
	rig.trigger_pressed.connect(_on_trigger)
	rig.grip_tapped.connect(_on_grip_tap)
	if _args.has("mode"):
		_start(str(_args.mode))
	else:
		_show_card()
	if _args.has("screenshot"):
		_screenshot.call_deferred()


# --- start card: white, palm-green icons, a row of vent triangles; no words -----------

func _show_card() -> void:
	if card:
		card.queue_free()
	card = Node3D.new()
	add_child(card)
	var head := _head()
	var fwd := -head.basis.z
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	card.global_position = head.origin + fwd * 0.9
	if head.origin.length() > 0.01:
		card.look_at(head.origin, Vector3.UP, true)
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.62, 0.36)
	bg.mesh = q
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color(1, 1, 1, 0.96)
	white.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg.material_override = white
	card.add_child(bg)
	for i in 3:
		var tri := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.026, 0.026, 0.004)
		tri.mesh = pm
		tri.material_override = _flat(GREEN)
		tri.position = Vector3((i - 1) * 0.036, 0.14, 0.003)
		card.add_child(tri)
	_buttons.clear()
	_icon_button("vr", Vector3(-0.19, -0.01, 0.004), 0.07, func(): _start("vr"))
	_icon_button("mr", Vector3(0.0, -0.01, 0.004), 0.07, func(): _start("mr"))
	_icon_button("board", Vector3(0.19, -0.01, 0.004), 0.07, func(): _start("table"))


func _icon_button(icon: String, at: Vector3, r: float, action: Callable) -> void:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.004
	cm.radial_segments = 40
	disc.mesh = cm
	disc.rotation.x = PI / 2
	disc.material_override = _flat(GREEN)
	disc.position = at
	card.add_child(disc)
	var ic := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(r * 1.15, r * 1.15)
	ic.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = load(ICONS + icon + ".png")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	ic.material_override = m
	ic.position = at + Vector3(0, 0, 0.004)
	card.add_child(ic)
	_buttons.append({"node": disc, "local": at, "r": r, "action": action})


static func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _card_hit(origin: Vector3, dir: Vector3) -> Dictionary:
	if card == null:
		return {}
	var plane := Plane(card.global_basis.z, card.global_position)
	var p = plane.intersects_ray(origin, dir)
	if p == null:
		return {}
	for b in _buttons:
		if (p as Vector3).distance_to(card.to_global(b.local)) < b.r:
			return b
	return {}


func _on_trigger(_hand: String, origin: Vector3, dir: Vector3) -> void:
	var b := _card_hit(origin, dir)
	if not b.is_empty():
		b.action.call()


# --- play ----------------------------------------------------------------------------

func _start(m: String) -> void:
	mode = m
	if card:
		card.queue_free()
		card = null
	if level:
		level.queue_free()
		level = null
	if diorama:
		diorama.queue_free()
		diorama = null
	if m == "table":
		_start_table()
		return
	rig.set_mode(m)
	level = SandLevel.new()
	add_child(level)
	if m == "vr":
		rig.position = Vector3(1.6, 0, 4.4)
		rig.rotation.y = deg_to_rad(18)
		level.setup("vr", Transform3D())
	else:
		var head := _head()
		var fwd := -head.basis.z
		fwd.y = 0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
		var basis := Basis.looking_at(fwd, Vector3.UP)
		level.setup("mr", Transform3D(basis, Vector3(head.origin.x, 0, head.origin.z)))
		_place_mr()
		if not xr:
			get_viewport().transparent_bg = false
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color("8f8a82")  # stand-in for the room on desktop
	level.level_won.connect(func(): get_tree().create_timer(5.0).timeout.connect(_show_card))


func _on_grip_tap(_hand: String) -> void:
	if level and mode == "mr" and card == null:
		_place_mr()
	elif diorama and card == null:
		_place_table()


# --- tabletop diorama (mixed reality preview of scene 1) ------------------------------

func _start_table() -> void:
	rig.set_mode("mr")
	diorama = Diorama.new()
	add_child(diorama)
	diorama.setup()
	table_k = 1.0
	_place_table()
	if not xr:
		get_viewport().transparent_bg = false
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("8f8a82")


## Puts the diorama in front of the player at about table height (a little below the hands).
func _place_table() -> void:
	var head := _head()
	var fwd := -head.basis.z
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var y := maxf(0.55, head.origin.y - 0.55) if head.origin.y > 0.3 else 0.75
	var basis := Basis.looking_at(fwd, Vector3.UP)  # model front (+Z) faces back towards you: the gate side
	diorama.global_transform = Transform3D(basis.scaled(Vector3.ONE * table_k), Vector3(head.origin.x, y, head.origin.z) + fwd * 0.75)


## Left stick: x turns the diorama, y resizes it (0.4x to 3x). Hold grip and move the hand
## to carry it, up and down too. Tap grip to bring it back in front of you.
func _table_controls(dt: float) -> void:
	var st := rig.stick("left")
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
		diorama.global_position = _drag.pos + (c - _drag.ctrl)
	else:
		_drag = {}


## Mixed reality: put the scene on the floor in front of the player at the current size.
func _place_mr() -> void:
	var head := _head()
	var fwd := -head.basis.z
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var basis := Basis.looking_at(fwd, Vector3.UP)
	level.global_transform = Transform3D(basis.scaled(Vector3.ONE * mr_scale), Vector3(head.origin.x, 0, head.origin.z) + fwd * 0.3)


## Mixed reality scene control: left stick x turns it, y resizes it; hold grip to drag it,
## tap grip to bring it back in front of you.
func _mr_controls(dt: float) -> void:
	var st := rig.stick("left")
	if absf(st.x) > 0.25:
		level.rotate_y(-st.x * 1.4 * dt)
	if absf(st.y) > 0.25:
		var ns := clampf(mr_scale * exp(st.y * 0.9 * dt), 0.2, 1.0)
		var k := ns / mr_scale
		mr_scale = ns
		var t := level.global_transform
		level.global_transform = Transform3D(t.basis.scaled(Vector3.ONE * k), t.origin)
	var dh := rig.dragging_hand()
	if dh != "":
		var c: Vector3 = rig.hands[dh].grip.global_position
		if _drag.get("hand", "") != dh:
			_drag = {"hand": dh, "ctrl": c, "pos": level.global_position}
		var d: Vector3 = c - _drag.ctrl
		d.y = 0
		level.global_position = _drag.pos + d * 1.5
	else:
		_drag = {}


func _follow_card(dt: float) -> void:
	var head := _head()
	if head.origin.length() < 0.01:
		return  # tracking not ready yet
	var fwd := -head.basis.z
	fwd.y = 0
	if fwd.length() < 0.01:
		return
	fwd = fwd.normalized()
	var target := head.origin + fwd * 0.9 + Vector3(0, -0.04, 0)
	var k := 1.0 if card.global_position.distance_to(target) > 2.0 else clampf(dt * 3.0, 0.0, 1.0)
	card.global_position = card.global_position.lerp(target, k)
	card.look_at(head.origin, Vector3.UP, true)


func _head() -> Transform3D:
	if xr:
		return rig.head_transform()
	return desk_cam.global_transform if desk_cam else Transform3D()


func _process(dt: float) -> void:
	if card and xr:
		_follow_card(dt)
	if diorama:
		if xr and card == null:
			_table_controls(dt)
		elif not xr:
			_desk_move(dt)
		return
	if level == null:
		return
	if xr and mode == "mr" and card == null:
		_mr_controls(dt)
	var held := false
	var hit = null
	if xr:
		for hand in ["right", "left"]:
			if not rig.tracked(hand):
				continue
			var c: XRController3D = rig.hands[hand].aim
			var down: bool = c.is_button_pressed("trigger_click") or c.get_float("trigger") > 0.6
			var r := rig.ray(hand)
			var p = Plane(Vector3.UP, level.global_position.y).intersects_ray(r[0], r[1])
			rig.set_pointer(hand, {"point": p, "interactive": down} if p != null else null, true)
			if down:
				held = true
				hit = p
				break
		if mode == "vr":
			_locomotion(dt)
	else:
		held = _mouse_draw
		if held:
			var mp := get_viewport().get_mouse_position()
			var o := desk_cam.project_ray_origin(mp)
			var d := desk_cam.project_ray_normal(mp)
			hit = Plane(Vector3.UP, 0.0).intersects_ray(o, d)
		_desk_move(dt)
	if not _demo:
		level.pointer(held, hit)


func _locomotion(dt: float) -> void:
	var mv := rig.stick("left")
	if mv.length() > 0.15:
		var head := rig.head_transform().basis
		var f := -head.z
		f.y = 0
		f = f.normalized()
		var r := head.x
		r.y = 0
		r = r.normalized()
		rig.position += (f * mv.y + r * mv.x) * 1.5 * dt
	var t := rig.stick("right").x
	if absf(t) > 0.7 and _snap_ready:
		_snap_ready = false
		var pivot := rig.head_transform().origin
		var rot := Transform3D(Basis(Vector3.UP, -signf(t) * deg_to_rad(30)), Vector3.ZERO)
		rig.global_transform = Transform3D().translated(pivot) * rot * Transform3D().translated(-pivot) * rig.global_transform
	elif absf(t) < 0.3:
		_snap_ready = true


# --- desktop -------------------------------------------------------------------------

func _unhandled_input(e: InputEvent) -> void:
	if xr:
		return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and card:
				var o := desk_cam.project_ray_origin(mb.position)
				var b := _card_hit(o, desk_cam.project_ray_normal(mb.position))
				if not b.is_empty():
					b.action.call()
					return
			_mouse_draw = mb.pressed
	elif e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_yaw -= (e as InputEventMouseMotion).relative.x * 0.005
		_pitch = clampf(_pitch - (e as InputEventMouseMotion).relative.y * 0.005, -1.4, 1.2)
	elif e is InputEventKey and e.pressed:
		match (e as InputEventKey).physical_keycode:
			KEY_V: _start("vr")
			KEY_M: _start("mr")
			KEY_T: _start("table")
			KEY_ESCAPE: _show_card()
			KEY_Q: _desk_turn(0.2)
			KEY_E: _desk_turn(-0.2)


func _desk_turn(a: float) -> void:
	if level and mode == "mr":
		level.rotate_y(a)
	elif diorama:
		diorama.rotate_y(a)


func _desk_move(dt: float) -> void:
	desk_cam.rotation = Vector3(_pitch, _yaw, 0)
	var v := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if v != Vector2.ZERO:
		var b := Basis(Vector3.UP, _yaw)
		rig.position += (b.x * v.x + b.z * v.y) * 2.0 * dt


# --- documentation screenshots ---------------------------------------------------------

func _screenshot() -> void:
	if _args.has("cam"):
		var c := str(_args.cam).split_floats(",")
		rig.position = Vector3(c[0], 0, c[2])
		desk_cam.position.y = c[1]
		_yaw = deg_to_rad(c[3])
		_pitch = deg_to_rad(c[4])
	if _args.has("round") and level:
		level._start_round(int(_args.round))
	for i in 30:
		await get_tree().process_frame
	if _args.has("demo") and level:
		_demo = true
		# draw a sample path from the walker towards the door, let it walk a while
		var a: Vector3 = level.walker.global_position
		var g: Vector3 = level.to_global(level.goal)
		var mid := a.lerp(g, 0.5) + level.global_basis.x * (1.6 if mode == "vr" else 0.8)
		for k in 41:
			var t := k / 40.0
			level.pointer(true, a.lerp(mid, t).lerp(mid.lerp(g, t), t))
			await get_tree().process_frame
		if int(_args.demo) > 1:
			level.pointer(false, null)
			for i in int(_args.demo):
				await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_args.screenshot)
	get_tree().quit()
