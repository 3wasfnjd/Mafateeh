class_name WebView
extends Node3D
## The browser build's view (abodengames.com): with no headset and no room, the table stands
## in a virtual Diriyah (VRScenery: sand, dunes, Najdi houses, palms) under a sky that follows
## the level's time of day, and the camera goes round it.
##   One finger / the mouse: point and press, as the trigger does on the headset.
##   Drag the sky (off the scene), two fingers, or the right mouse button: turn round the table.
##   Pinch, two fingers apart, or the wheel: nearer or further.
##   The round button in the corner: the menu (Esc too).
## table_main owns the camera and the pointer; this node moves the camera and says when a
## gesture has the screen (no press reaches the game then).

signal menu_pressed

const TABLE_TOP := Vector3(0, 0.75, 0)   # where the diorama stands (world metres)
const STAND := 0.8                        # the stand's top, metres across (the island is 0.66)
const PITCH_MIN := deg_to_rad(12.0)
const PITCH_MAX := deg_to_rad(80.0)
const DIST_MIN := 0.42
const DIST_MAX := 1.7
const SKY_LOOKS := {   # top, horizon, ground (as SkyWeather's presets)
	"day": [Color("4f8acb"), Color("cfe0ec"), Color("b49673")],
	"evening": [Color("5a5e9c"), Color("f6a35f"), Color("8d6550")],
	"night": [Color("0e1631"), Color("2c3962"), Color("2a2730")],
	"dawn": [Color("6d82b8"), Color("f2b98e"), Color("8a6e57")],
}

var cam: Camera3D
var env: Environment
var scenery: VRScenery
var sky_mat: ProceduralSkyMaterial
var gesture := false          # two fingers (or an orbit drag) have the screen: no presses
var orbiting := false         # a one-finger / left-button drag round the table, begun off the scene
var yaw := 0.0
var pitch := deg_to_rad(36.0)
var dist := 0.9
var _goal := {}               # where the camera eases to: yaw, pitch, dist, target
var target := TABLE_TOP
var _touches := {}            # finger index -> position
var _pinch := 0.0
var _mid := Vector2.ZERO
var _layer: CanvasLayer
var _tip: Label
var _tip_box: PanelContainer
var _ui_k := 1.0             # the screen's pixels per CSS pixel: the corner button and tip keep their size
var _root: Control
var _intro_view := false
var _card_view := false       # the menu is open: the camera holds still


func setup(environment: Environment, camera: Camera3D) -> void:
	env = environment
	cam = camera
	cam.near = 0.02
	cam.far = 300.0
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.fog_enabled = true
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	scenery = VRScenery.new()
	scenery.name = "Diriyah"
	add_child(scenery)
	scenery.scale = Vector3.ONE * 1.8   # the town further off than in VR: the table is the near thing
	scenery.set_stand(Transform3D(Basis(), TABLE_TOP), STAND, STAND)
	set_mood("day", 0.0)
	dist = _near()
	_goal = {"yaw": yaw, "pitch": pitch, "dist": dist, "target": target}
	# a phone's screen has two or three pixels to each of the page's: the buttons are drawn as
	# large, and the 3D scene at fewer pixels (so it stays smooth), then stretched to fill
	var dpr := DisplayServer.screen_get_scale()
	_ui_k = clampf(dpr, 1.0, 3.0)
	get_viewport().scaling_3d_scale = clampf(1.8 / maxf(dpr, 1.0), 0.6, 1.0)
	_build_hud()


## The sky, the far town and the haze for a time of day ("day", "evening", "night", "dawn").
func set_mood(mood: String, seconds := 0.8) -> void:
	var l: Array = SKY_LOOKS.get(mood, SKY_LOOKS.day)
	var p := {"top": l[0], "horizon": l[1], "ground": l[2]}
	if seconds <= 0.0:
		_sky_colours(l[0], l[1], l[2])
	else:
		var from := [sky_mat.sky_top_color, sky_mat.sky_horizon_color, sky_mat.ground_bottom_color]
		create_tween().tween_method(func(t: float):
			_sky_colours(from[0].lerp(l[0], t), from[1].lerp(l[1], t), from[2].lerp(l[2], t)), 0.0, 1.0, seconds)
	scenery.set_tint(p, 0.0)


func _sky_colours(top: Color, horizon: Color, ground: Color) -> void:
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = ground
	env.fog_light_color = horizon


## Standing back, looking straight ahead: the way in (the gate) is in front.
func view_intro() -> void:
	_intro_view = true
	scenery.stand.visible = false   # the table comes with the first scene
	cam.global_transform = Transform3D(Basis(), Vector3(0, 1.45, 1.5))


## Round the table: the camera eases back to it from wherever it is.
func view_table(k := 1.0) -> void:
	scenery.stand.visible = true
	if _intro_view:
		_intro_view = false
		_goal = {"yaw": 0.0, "pitch": deg_to_rad(36.0), "dist": _near() * k, "target": TABLE_TOP + Vector3(0, 0.04, 0)}
		# from the standing view: start the orbit where the camera already is
		var to: Vector3 = cam.global_position - (_goal.target as Vector3)
		dist = to.length()
		pitch = clampf(asin(to.y / dist), PITCH_MIN, PITCH_MAX)
		yaw = atan2(to.x, to.z)
		target = _goal.target
	else:
		_goal.target = TABLE_TOP + Vector3(0, 0.04, 0)


## The menu's "set the scene down elsewhere" button, in the browser: the first view again.
func reset() -> void:
	_goal = {"yaw": 0.0, "pitch": deg_to_rad(36.0), "dist": _near(), "target": TABLE_TOP + Vector3(0, 0.04, 0)}


## How far the camera stands at first: nearer on a tall phone screen, where the island is
## narrow across it.
func _near() -> float:
	var vp := get_viewport().get_visible_rect().size
	return 0.74 if vp.y > vp.x else 0.9


func hold(on: bool) -> void:
	_card_view = on


## Every frame (from table_main): the field of view for the screen's shape, and the orbit.
func frame(dt: float) -> void:
	_fit_hud()
	var vp := get_viewport().get_visible_rect().size
	var tall := vp.y > vp.x
	cam.keep_aspect = Camera3D.KEEP_WIDTH if tall else Camera3D.KEEP_HEIGHT
	cam.fov = 62.0 if tall else 50.0
	if _intro_view:
		cam.fov = 40.0 if tall else 30.0   # the gate, a little way off, fills the screen
	if _intro_view or _card_view:
		return
	var a := 1.0 - exp(-dt * 10.0)
	yaw = lerp_angle(yaw, _goal.yaw, a)
	pitch = lerpf(pitch, _goal.pitch, a)
	dist = lerpf(dist, _goal.dist, a)
	target = target.lerp(_goal.target, a)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.global_transform = Transform3D(Basis.looking_at(-off, Vector3.UP), target + off)


func _turn(by: Vector2) -> void:
	var vp := get_viewport().get_visible_rect().size
	var s := 3.2 / maxf(minf(vp.x, vp.y), 1.0)
	_goal.yaw -= by.x * s
	_goal.pitch = clampf(_goal.pitch + by.y * s, PITCH_MIN, PITCH_MAX)


func _zoom(f: float) -> void:
	_goal.dist = clampf(_goal.dist * f, DIST_MIN, DIST_MAX)


## A press began off the scene (on the sky, the sand round the table): the drag turns the view.
func begin_orbit() -> void:
	orbiting = true


## Gestures and the camera's own controls. True when the event was the camera's.
func input(e: InputEvent) -> bool:
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
		if _touches.size() >= 2:
			gesture = true
			_pinch = _spread()
			_mid = _centre()
		elif _touches.is_empty():
			gesture = false
			orbiting = false
		return gesture
	if e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		_touches[d.index] = d.position
		if _touches.size() >= 2:
			var c := _centre()
			var s := _spread()
			if not _card_view:
				_turn(c - _mid)
				if _pinch > 1.0 and s > 1.0:
					_zoom(_pinch / s)
			_mid = c
			_pinch = s
			return true
		if orbiting and not _card_view:
			_turn(d.relative)
			return true
		return false
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(0.92)
			return true
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0 / 0.92)
			return true
		if not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _touches.is_empty():
			orbiting = false
		return mb.button_index == MOUSE_BUTTON_RIGHT
	if e is InputEventMouseMotion and _touches.is_empty():
		var mm := e as InputEventMouseMotion
		if (orbiting and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			if not _card_view:
				_turn(mm.relative)
			return true
	if e is InputEventMagnifyGesture:   # a laptop's trackpad
		_zoom(1.0 / maxf((e as InputEventMagnifyGesture).factor, 0.01))
		return true
	return false


func _spread() -> float:
	var p: Array = _touches.values()
	return (p[0] as Vector2).distance_to(p[1]) if p.size() >= 2 else 0.0


func _centre() -> Vector2:
	var p: Array = _touches.values()
	return ((p[0] as Vector2) + (p[1] as Vector2)) * 0.5 if p.size() >= 2 else Vector2.ZERO


# --- the corner button and the first tip ------------------------------------------------------

func _build_hud() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)
	_root = root
	_fit_hud()
	# the menu: a cream disc with the levels icon, in the top corner (right: the game reads
	# right to left)
	var disc := Panel.new()
	disc.name = "MenuButton"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("fbf3e4e6")
	sb.set_corner_radius_all(30)
	sb.border_color = Color("7a5a3a")
	sb.set_border_width_all(2)
	disc.add_theme_stylebox_override("panel", sb)
	root.add_child(disc)
	disc.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	disc.offset_left = -76
	disc.offset_right = -16
	disc.offset_top = 16
	disc.offset_bottom = 76
	var b := TextureButton.new()
	b.texture_normal = load("res://assets/ui/icons/levels.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.self_modulate = Color("4f3826")
	disc.add_child(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
	b.pressed.connect(func(): menu_pressed.emit())
	# the tip: a cream band at the foot of the screen, centred, the words wrapped inside it
	var foot := MarginContainer.new()
	root.add_child(foot)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.add_theme_constant_override("margin_bottom", 22)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(centre)
	_tip_box = PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color("fbf3e4eb")
	tsb.set_corner_radius_all(18)
	tsb.border_color = Color("7a5a3a")
	tsb.set_border_width_all(2)
	tsb.content_margin_left = 18
	tsb.content_margin_right = 18
	tsb.content_margin_top = 8
	tsb.content_margin_bottom = 10
	_tip_box.add_theme_stylebox_override("panel", tsb)
	_tip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_box.visible = false
	centre.add_child(_tip_box)
	_tip = Label.new()
	_tip.add_theme_font_override("font", TableMenu.font())
	_tip.add_theme_font_size_override("font_size", 19)
	_tip.add_theme_color_override("font_color", Color("4f3826"))
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_box.add_child(_tip)


func _fit_hud() -> void:
	var vp := get_viewport().get_visible_rect().size
	_layer.scale = Vector2.ONE * _ui_k
	_root.position = Vector2.ZERO
	_root.size = vp / _ui_k


## A tall phone screen: the menu and the scene are larger with the phone on its side.
func tall() -> bool:
	var vp := get_viewport().get_visible_rect().size
	return vp.y > vp.x


func show_menu_button(on: bool) -> void:
	(_layer.get_node("Root/MenuButton") as Control).visible = on


## A line at the foot of the screen for a few seconds (how to turn the view, the first time).
func tip(text: String, seconds := 7.0) -> void:
	var vp := get_viewport().get_visible_rect().size
	_tip.text = text
	_tip.custom_minimum_size.x = minf(vp.x / _ui_k - 72.0, 520.0)
	_tip.add_theme_font_size_override("font_size", 15 if vp.x / _ui_k < 500.0 else 19)
	_tip_box.modulate.a = 0.0
	_tip_box.visible = true
	var tw := create_tween()
	tw.tween_property(_tip_box, "modulate:a", 1.0, 0.5)
	tw.tween_interval(seconds)
	tw.tween_property(_tip_box, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func(): _tip_box.visible = false)
