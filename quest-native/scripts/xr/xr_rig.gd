class_name XRRig
extends XROrigin3D
## OpenXR session, passthrough and controller input. Exposes plain values and
## signals; it knows nothing about puzzles or the board.
##
## Controller mapping (Godot default OpenXR action map):
##   right "primary" stick  -> character movement (read by the game)
##   left  "primary" stick  -> x: rotate board, y: resize board
##   "trigger_click"         -> select / interact (either hand)
##   "grip_click"            -> tap: recenter / re-place, hold: drag the board
##   left "menu_button"      -> settings panel

signal trigger_pressed(hand: String, origin: Vector3, direction: Vector3)
signal grip_tapped(hand: String)
signal grip_drag_started(hand: String)
signal grip_drag_ended(hand: String)
signal menu_pressed
signal undo_pressed  # B / Y: step back one action
signal focus_changed(focused: bool)
signal session_started
signal mode_changed(mode: String)

const GRIP_TAP_TIME := 0.35

var xr_interface: OpenXRInterface
var xr_active := false
var focused := true
var passthrough_supported := false
var mode := "vr"

var camera: XRCamera3D
var hands := {}  # "left"/"right" -> {aim: XRController3D, grip: XRController3D, ray: MeshInstance3D, dot: MeshInstance3D}
var _prev := {}
var _grip_time := {"left": -1.0, "right": -1.0}
var _dragging := ""
var _environment: Environment
# Aim smoothing (a one-euro filter) on the direction only: strong while the hand is nearly
# still, so tremor does not shake the pointer, light when it turns fast, so it never lags. The
# ray always starts at the controller itself (smoothing where it starts made it trail behind the
# hand and lean). A few recent rays are kept, because pulling the trigger dips the controller: a
# press uses the aim from just before it.
const AIM_MIN_CUTOFF := 1.3   # Hz, at rest
const AIM_BETA := 0.05        # extra Hz per degree a second of turning
const PRESS_LOOKBACK := 3     # frames (about 40 ms at 72 Hz)
var _aim := {}                # hand -> {o, d, hist: [[o, d], ...] newest first}
# The drawn pointer: its end glides to where the ray lands (no jumps between a roof and the
# ground behind it), and a moment of lost tracking (the hand out of the cameras' view) keeps the
# last ray instead of blinking it away.
const RAY_FREE := 1.4         # metres drawn when the ray is on nothing
const RAY_SEGS := 24
const END_RATE := 26.0        # 1/s: how fast the end follows (about 40 ms)
const LOST_GRACE := 0.3       # s
const RAY_COLOUR := Color(1.0, 0.9, 0.62)
const DRAW_LINE := true
const RAY_MAX := 0.28         # m: the line is a short pointer out of the hand, not a laser across the room
var _ptr := {}                # hand -> {has, end, n, size, lost}
var fake_ray := []            # screenshots only: a right-hand ray [origin, direction] with no headset


func setup(environment: Environment) -> void:
	_environment = environment
	camera = XRCamera3D.new()
	camera.name = "XRCamera3D"
	camera.near = 0.02
	camera.far = 200.0
	add_child(camera)
	for hand in ["left", "right"]:
		var aim := XRController3D.new()
		aim.name = hand.capitalize() + "Aim"
		aim.tracker = hand + "_hand"
		aim.pose = "aim"
		add_child(aim)
		var grip := XRController3D.new()
		grip.name = hand.capitalize() + "Grip"
		grip.tracker = hand + "_hand"
		grip.pose = "grip"
		add_child(grip)
		if ClassDB.class_exists("OpenXRFbRenderModel"):
			var model: Node3D = ClassDB.instantiate("OpenXRFbRenderModel")
			if hand == "right":
				model.set("render_model_type", 1)
			grip.add_child(model)
		else:
			grip.add_child(_fallback_controller())
		# the ray: a thin ribbon built each frame, turned to face the eyes; it curves gently from
		# the hand to the target when the target assist pulls the end onto a piece
		var ray := MeshInstance3D.new()
		ray.mesh = ImmediateMesh.new()
		var rm := _unshaded(Color.WHITE, true)
		rm.vertex_color_use_as_albedo = true
		rm.cull_mode = BaseMaterial3D.CULL_DISABLED
		rm.no_depth_test = true   # never cut by a wall it passes beside
		rm.render_priority = 19
		ray.material_override = rm
		ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ray.extra_cull_margin = 16384.0
		ray.top_level = true
		ray.visible = false
		add_child(ray)
		# where it lands: a ring with a soft centre, lying on the surface
		var dot := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.008
		torus.outer_radius = 0.011
		torus.rings = 24
		torus.ring_segments = 6
		dot.mesh = torus
		dot.material_override = _unshaded(Color(1.0, 0.86, 0.45, 0.95), true)
		(dot.material_override as StandardMaterial3D).no_depth_test = true   # always seen where the ray ends
		(dot.material_override as StandardMaterial3D).render_priority = 20
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.top_level = true
		dot.visible = false
		add_child(dot)
		var centre := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.0035
		disc.bottom_radius = 0.0035
		disc.height = 0.0004
		disc.radial_segments = 16
		disc.rings = 1
		centre.mesh = disc
		centre.material_override = dot.material_override
		centre.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.add_child(centre)
		hands[hand] = {"aim": aim, "grip": grip, "ray": ray, "dot": dot}
		_prev[hand] = {}
		_ptr[hand] = {"has": false, "end": Vector3.ZERO, "n": Vector3.UP, "size": 1.0, "lost": 0.0}


func _fallback_controller() -> Node3D:
	var m := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = 0.02
	c.height = 0.11
	m.mesh = c
	m.rotation.x = PI / 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.22)
	m.material_override = mat
	return m


static func _unshaded(c: Color, transparent: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	return m


func start() -> bool:
	xr_interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr_interface == null or not xr_interface.is_initialized():
		if xr_interface == null or not xr_interface.initialize():
			return false
	xr_active = true
	apply_quality(Save.quality)
	var vp := get_viewport()
	vp.use_xr = true
	# Quest refresh rate: keep the runtime default (72 Hz) unless asked otherwise.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	xr_interface.session_begun.connect(_on_session_begun)
	xr_interface.session_visible.connect(func(): _set_focus(false))
	xr_interface.session_focussed.connect(func(): _set_focus(true))
	xr_interface.session_stopping.connect(func(): _set_focus(false))
	xr_interface.pose_recentered.connect(func(): grip_tapped.emit("recenter"))
	return true


## Render quality: "high" renders above the headset's recommended resolution with
## light foveation; "balanced" uses the recommended size and stronger foveation.
func apply_quality(q: String) -> void:
	if xr_interface == null:
		return
	var high := q == "high"
	xr_interface.render_target_size_multiplier = 1.4 if high else 1.0   # (with 4x MSAA: sharp, still light on a Quest 3)
	xr_interface.foveation_level = 1 if high else 2
	xr_interface.foveation_dynamic = true


func _on_session_begun() -> void:
	passthrough_supported = xr_interface.get_supported_environment_blend_modes().has(
		XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND)
	session_started.emit()


func _set_focus(f: bool) -> void:
	if focused == f:
		return
	focused = f
	_dragging = ""
	focus_changed.emit(f)


## "mr" shows the real room through passthrough; "vr" shows the virtual sky.
## Falls back to VR when the headset does not offer alpha-blend passthrough.
func set_mode(m: String) -> String:
	if m == "mr" and xr_active and not passthrough_supported:
		m = "vr"
	mode = m
	var vp := get_viewport()
	if m == "mr":
		vp.transparent_bg = true
		_environment.background_mode = Environment.BG_COLOR
		_environment.background_color = Color(0, 0, 0, 0)
		if xr_active:
			xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	else:
		vp.transparent_bg = false
		_environment.background_mode = Environment.BG_SKY
		if xr_active:
			xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	mode_changed.emit(m)
	return m


func tracked(hand: String) -> bool:
	var c: XRController3D = hands[hand].aim
	return xr_active and focused and c.get_is_active() and c.get_has_tracking_data()


## Tracked, or lost only a moment ago: the pointer stays drawn from the last aim.
func aiming(hand: String) -> bool:
	if not fake_ray.is_empty() and hand == "right":
		return true
	return tracked(hand) or (xr_active and focused and _aim.has(hand) and _ptr[hand].lost < LOST_GRACE)


func stick(hand: String) -> Vector2:
	if not tracked(hand):
		return Vector2.ZERO
	return hands[hand].aim.get_vector2("primary")


## The hand's smoothed aim ray [origin, direction] (world space).
func ray(hand: String) -> Array:
	if not fake_ray.is_empty() and hand == "right":
		return fake_ray
	var a: Dictionary = _aim.get(hand, {})
	if a.is_empty():
		return raw_ray(hand)
	return [a.o, a.d]


## The aim a moment before now: what the player pointed at as they began pulling the trigger.
func press_ray(hand: String) -> Array:
	var a: Dictionary = _aim.get(hand, {})
	if a.is_empty() or a.hist.is_empty():
		return ray(hand)
	return a.hist[mini(PRESS_LOOKBACK, a.hist.size() - 1)]


func raw_ray(hand: String) -> Array:
	var c: XRController3D = hands[hand].aim
	var t := c.global_transform
	return [t.origin, -t.basis.z.normalized()]


func _smooth_aim(hand: String, delta: float) -> void:
	var r := raw_ray(hand)
	var a: Dictionary = _aim.get(hand, {})
	if a.is_empty() or delta <= 0.0:
		_aim[hand] = {"o": r[0], "d": r[1], "hist": []}
		return
	var turn := rad_to_deg((a.d as Vector3).angle_to(r[1])) / delta
	var cutoff := AIM_MIN_CUTOFF + AIM_BETA * turn
	var k := 1.0 / (1.0 + 1.0 / (TAU * cutoff * delta))
	a.d = (a.d as Vector3).slerp(r[1], k).normalized()
	a.o = r[0]
	a.hist.push_front([a.o, a.d])
	if a.hist.size() > PRESS_LOOKBACK + 1:
		a.hist.pop_back()


## Short controller vibration (OpenXR "haptic" output); off when disabled in settings.
func pulse(hand: String, amplitude := 0.3, seconds := 0.04) -> void:
	if xr_active and Save.haptics and hands.has(hand) and tracked(hand):
		hands[hand].aim.trigger_haptic_pulse("haptic", 0.0, amplitude, seconds, 0.0)


func head_transform() -> Transform3D:
	return camera.global_transform


func dragging_hand() -> String:
	return _dragging


## hit: null, or {point, normal (optional, default up), interactive (a target under it),
## pressed}. The ray is drawn from the hand to the point (curving there when the point is off the
## aim line, as a snapped target is), the ring lies on the surface there.
func set_pointer(hand: String, hit, show_ray: bool) -> void:
	var h: Dictionary = hands[hand]
	var st: Dictionary = _ptr[hand]
	if not (show_ray and aiming(hand)):
		h.ray.visible = false
		h.dot.visible = false
		st.has = false
		return
	var r := ray(hand)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	var target: Vector3 = hit.point if hit != null else o + d * RAY_FREE
	var n: Vector3 = hit.get("normal", Vector3.UP) if hit != null else -d
	var dt := get_process_delta_time()
	if not st.has or not st.get("hit", false) and hit != null:
		st.end = target   # a fresh ray, or one that just landed: start right there
		st.n = n
		st.has = true
	else:
		var k := 1.0 - exp(-END_RATE * dt)
		st.end = (st.end as Vector3).lerp(target, k)
		st.n = (st.n as Vector3).slerp(n.normalized(), k).normalized() if (st.n as Vector3).dot(n) > -0.99 else n
	st.hit = hit != null
	var end: Vector3 = st.end
	var dist := maxf(o.distance_to(end), 0.01)
	var interactive: bool = hit != null and hit.get("interactive", false)
	h.ray.visible = DRAW_LINE
	if DRAW_LINE:
		_draw_ray(h.ray, o, d, end, dist, hit != null, interactive)
	# the ring: on a target, or on a menu (hit.ui); never on bare ground or a wall
	h.dot.visible = hit != null and (interactive or hit.get("ui", false))
	if hit != null:
		var size := clampf(dist / 0.7, 0.7, 2.6)   # about the same size to the eye, near or far
		if interactive:
			size *= 1.55 + 0.07 * sin(Time.get_ticks_msec() * 0.007)
		if hit.get("pressed", false):
			size *= 0.75
		st.size = lerpf(st.size, size, 1.0 - exp(-20.0 * dt))
		var nn: Vector3 = st.n
		var b := Basis.looking_at(nn.cross(Vector3.RIGHT if absf(nn.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD), nn)
		h.dot.global_transform = Transform3D(b.scaled(Vector3.ONE * st.size), end + nn * 0.002)
		(h.dot.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.97, 0.86, 1.0) if interactive else Color(1.0, 0.86, 0.45, 0.9)


## The ribbon from o (going out along d) to end: a quadratic curve, wide and clear at the
## hand, thin at the end; fading out into the air when it is on nothing.
func _draw_ray(node: MeshInstance3D, o: Vector3, d: Vector3, end: Vector3, dist: float, landed: bool, interactive: bool) -> void:
	var im := node.mesh as ImmediateMesh
	im.clear_surfaces()
	node.visible = true
	node.global_transform = Transform3D.IDENTITY
	var ctrl := o + d * dist * 0.5
	var eye := camera.global_position
	var view := get_viewport().get_camera_3d()
	if view:
		eye = view.global_position
	var col := RAY_COLOUR.lerp(Color(1, 1, 1), 0.35) if interactive else RAY_COLOUR
	var reach := minf(dist, RAY_MAX) / dist      # how much of the way to the end is drawn
	var whole := landed and dist <= RAY_MAX       # short enough to reach what it is on
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in RAY_SEGS + 1:
		var f := float(i) / RAY_SEGS
		var t := f * reach
		var u := 1.0 - t
		var p := o * u * u + ctrl * 2.0 * u * t + end * t * t
		var tg := ((ctrl - o) * u + (end - ctrl) * t).normalized()
		var side := tg.cross(p - eye)
		if side.length_squared() < 1e-10:
			side = tg.cross(Vector3.UP)
		side = side.normalized() * lerpf(0.0028, 0.0014, f)
		var a := clampf(t * dist / 0.03, 0.0, 1.0) * 0.85      # out of the controller softly
		if not whole:
			a *= clampf((1.0 - f) / 0.55, 0.0, 1.0)            # the tip fades away
		im.surface_set_color(Color(col.r, col.g, col.b, a))
		im.surface_add_vertex(p + side)
		im.surface_set_color(Color(col.r, col.g, col.b, a))
		im.surface_add_vertex(p - side)
	im.surface_end()


func _process(delta: float) -> void:
	if not xr_active:
		return
	for hand in ["left", "right"]:
		var c: XRController3D = hands[hand].aim
		var now := {
			"trigger": c.is_button_pressed("trigger_click") or c.get_float("trigger") > 0.75,
			"grip": c.is_button_pressed("grip_click") or c.get_float("grip") > 0.75,
			"menu": c.is_button_pressed("menu_button"),
			"undo": c.is_button_pressed("by_button"),
		}
		var was: Dictionary = _prev[hand]
		var ok := tracked(hand)
		if ok:
			_smooth_aim(hand, delta)
			_ptr[hand].lost = 0.0
		else:
			_ptr[hand].lost += delta
			if _ptr[hand].lost >= LOST_GRACE:
				_aim.erase(hand)   # start afresh when it comes back, not from where it was lost
		if ok and now.trigger and not was.get("trigger", false):
			var r := press_ray(hand)
			trigger_pressed.emit(hand, r[0], r[1])
		if now.menu and not was.get("menu", false) and focused:
			menu_pressed.emit()
		if ok and now.undo and not was.get("undo", false) and focused:
			undo_pressed.emit()
		if ok and now.grip and not was.get("grip", false):
			_grip_time[hand] = 0.0
		elif now.grip and _grip_time[hand] >= 0.0:
			_grip_time[hand] += delta
			if _grip_time[hand] > GRIP_TAP_TIME and _dragging == "" and ok:
				_dragging = hand
				grip_drag_started.emit(hand)
		if not now.grip and was.get("grip", false):
			if _dragging == hand:
				_dragging = ""
				grip_drag_ended.emit(hand)
			elif _grip_time[hand] >= 0.0 and _grip_time[hand] <= GRIP_TAP_TIME:
				grip_tapped.emit(hand)
			_grip_time[hand] = -1.0
		if not ok and _dragging == hand:
			_dragging = ""
			grip_drag_ended.emit(hand)
		_prev[hand] = now
