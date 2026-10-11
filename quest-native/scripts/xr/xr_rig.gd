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
		var ray := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.0012
		cyl.bottom_radius = 0.0025
		cyl.height = 1.0
		cyl.radial_segments = 6
		cyl.rings = 1
		ray.mesh = cyl
		ray.material_override = _unshaded(Color(1.0, 0.92, 0.7, 0.55), true)
		ray.rotation.x = -PI / 2
		ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		aim.add_child(ray)
		var dot := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.008
		torus.outer_radius = 0.012
		torus.rings = 16
		torus.ring_segments = 6
		dot.mesh = torus
		dot.material_override = _unshaded(Color(1.0, 0.86, 0.45, 0.95), false)
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.top_level = true
		dot.visible = false
		add_child(dot)
		hands[hand] = {"aim": aim, "grip": grip, "ray": ray, "dot": dot}
		_prev[hand] = {}


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
	xr_interface.render_target_size_multiplier = 1.3 if high else 1.0
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


func stick(hand: String) -> Vector2:
	if not tracked(hand):
		return Vector2.ZERO
	return hands[hand].aim.get_vector2("primary")


func ray(hand: String) -> Array:
	var c: XRController3D = hands[hand].aim
	var t := c.global_transform
	return [t.origin, -t.basis.z.normalized()]


## Short controller vibration (OpenXR "haptic" output); off when disabled in settings.
func pulse(hand: String, amplitude := 0.3, seconds := 0.04) -> void:
	if xr_active and Save.haptics and hands.has(hand) and tracked(hand):
		hands[hand].aim.trigger_haptic_pulse("haptic", 0.0, amplitude, seconds, 0.0)


func head_transform() -> Transform3D:
	return camera.global_transform


func dragging_hand() -> String:
	return _dragging


func set_pointer(hand: String, hit, show_ray: bool) -> void:
	var h: Dictionary = hands[hand]
	var length := 0.6
	h.dot.visible = false
	if hit != null:
		var origin: Vector3 = ray(hand)[0]
		length = origin.distance_to(hit.point)
		h.dot.visible = true
		h.dot.global_position = hit.point + Vector3.UP * 0.002
		h.dot.scale = Vector3.ONE * (1.6 if hit.get("interactive", false) else 1.0)
	h.ray.visible = show_ray and tracked(hand)
	h.ray.scale = Vector3(1, length, 1)
	h.ray.position = Vector3(0, 0, -length / 2.0)


func _process(delta: float) -> void:
	if not xr_active:
		return
	for hand in ["left", "right"]:
		var c: XRController3D = hands[hand].aim
		var now := {
			"trigger": c.is_button_pressed("trigger_click") or c.get_float("trigger") > 0.75,
			"grip": c.is_button_pressed("grip_click") or c.get_float("grip") > 0.75,
			"menu": c.is_button_pressed("menu_button"),
		}
		var was: Dictionary = _prev[hand]
		var ok := tracked(hand)
		if ok and now.trigger and not was.get("trigger", false):
			var r := ray(hand)
			trigger_pressed.emit(hand, r[0], r[1])
		if now.menu and not was.get("menu", false) and focused:
			menu_pressed.emit()
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
