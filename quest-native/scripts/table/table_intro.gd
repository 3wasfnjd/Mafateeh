class_name TableIntro
extends Node3D
## The way into the game, before any menu: the studio's logo held in the air a few seconds,
## then a painted Najdi gate rises in the room, a golden key comes to its lock and turns,
## the two leaves swing open on a warm light with drifting motes, and the name «مفاتيح»
## comes out of it. The trigger skips ahead; at the end it starts the game (`finished`).
## Placed once in front of the player and left there (it does not follow the head).

signal finished

const LOGO := "res://assets/brand/aboden_logo.png"
const DOOR_TEX := "res://assets/world/door_arch_door.jpg"
const MUD_TEX := "res://assets/world/courtyard_mud.jpg"
const GOLD := Color("e3a83a")
const CREAM := Color("fff1d0")
const DIST := 2.1           # metres in front of the player
const LOGO_IN := 1.2
const LOGO_HOLD := 5.0      # the studio's name stays a good while (shown only here: the system splash is off)
const LOGO_OUT := 1.2
const GATE_W := 1.0         # the doorway
const GATE_H := 1.5

var _logo: MeshInstance3D
var _gate: Node3D
var _leaves: Array[Node3D] = []
var _key: Node3D
var _glow: MeshInstance3D
var _motes: CPUParticles3D
var _title: Node3D
var _prompt: Label3D
var _step := ""             # logo, gate, title, leaving
var _tw: Tween
var _t := 0.0


## Starts it in front of the head.
func begin(head: Transform3D) -> void:
	var fwd := -head.basis.z
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	global_position = head.origin + fwd * DIST + Vector3(0, -0.15, 0)
	look_at(head.origin + Vector3(0, -0.15, 0), Vector3.UP, true)   # +z towards the player
	_build_logo()
	_build_gate()
	_step = "logo"
	_logo.visible = true
	_tw = create_tween()
	_tw.tween_method(_logo_alpha, 0.0, 1.0, LOGO_IN).set_trans(Tween.TRANS_SINE)
	_tw.tween_interval(LOGO_HOLD)
	_tw.tween_method(_logo_alpha, 1.0, 0.0, LOGO_OUT).set_trans(Tween.TRANS_SINE)
	_tw.tween_callback(_open_gate)
	TableKit.sfx(self, "intro_sting", Vector3.ZERO, -6.0)


func _process(dt: float) -> void:
	_t += dt
	if _prompt and _prompt.visible:
		_prompt.modulate.a = 0.55 + 0.45 * sin(_t * 3.0)
	if _title and _title.visible:
		_title.position.y = GATE_H * 0.62 + 0.012 * sin(_t * 1.4)


## The trigger: past the logo, past the gate, or (on the name) into the game.
func press() -> void:
	match _step:
		"logo":
			_kill()
			_logo_alpha(0.0)
			_open_gate()
		"gate":
			_kill()
			_show_open()
		"title":
			_leave()


func _kill() -> void:
	if _tw and _tw.is_valid():
		_tw.kill()


# --- the logo --------------------------------------------------------------------------------

func _build_logo() -> void:
	_logo = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.8 * 989.0 / 1024.0, 0.8)
	_logo.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = load(LOGO)
	m.albedo_color = Color(1, 1, 1, 0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.no_depth_test = true
	m.render_priority = 10
	_logo.material_override = m
	_logo.position = Vector3(0, 0.12, 0)
	_logo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_logo.visible = false
	add_child(_logo)


func _logo_alpha(a: float) -> void:
	(_logo.material_override as StandardMaterial3D).albedo_color.a = a
	_logo.scale = Vector3.ONE * (0.94 + 0.06 * a)
	_logo.visible = a > 0.001


# --- the gate --------------------------------------------------------------------------------

func _mat(tex: String, tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(tex)
	m.albedo_color = tint
	m.roughness = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _build_gate() -> void:
	_gate = Node3D.new()
	_gate.position.y = -GATE_H * 0.5
	_gate.visible = false
	add_child(_gate)
	var mud := _mat(MUD_TEX, Color("e9c9a0"))
	mud.uv1_triplanar = true
	mud.uv1_scale = Vector3(1.6, 1.6, 1.6)
	var pw := 0.26                     # the mud pillars either side
	for s in [-1, 1]:
		_box(_gate, Vector3(pw, GATE_H + 0.26, 0.3), Vector3(s * (GATE_W / 2 + pw / 2), (GATE_H + 0.26) / 2, 0), mud)
	_box(_gate, Vector3(GATE_W + pw * 2 + 0.08, 0.26, 0.34), Vector3(0, GATE_H + 0.13, 0), mud)
	# the Najdi crenels along the top
	var n := 7
	for i in n:
		var x := -(GATE_W / 2 + pw) + (GATE_W + pw * 2) * (i + 0.5) / n
		var c := _box(_gate, Vector3(0.1, 0.12, 0.1), Vector3(x, GATE_H + 0.32, 0), mud)
		c.rotation.z = PI / 4 if i % 2 == 0 else 0.0
	# the two painted leaves, hinged at the pillars, opening away from the player
	var door := _mat(DOOR_TEX)
	for s in [-1, 1]:
		var hinge := Node3D.new()
		hinge.position = Vector3(s * GATE_W / 2, 0, -0.04)
		_gate.add_child(hinge)
		var leaf := _box(hinge, Vector3(GATE_W / 2, GATE_H, 0.05), Vector3(-s * GATE_W / 4, GATE_H / 2, 0), door)
		var ring := MeshInstance3D.new()   # an iron ring to pull it by
		var t := TorusMesh.new()
		t.inner_radius = 0.022
		t.outer_radius = 0.03
		ring.mesh = t
		var iron := StandardMaterial3D.new()
		iron.albedo_color = Color("3a3430")
		iron.metallic = 0.6
		iron.roughness = 0.5
		ring.material_override = iron
		ring.rotation.x = PI / 2
		ring.position = Vector3(s * GATE_W / 4 - s * 0.06, 0, 0.035)
		leaf.add_child(ring)
		_leaves.append(hinge)
	# the light behind the leaves
	_glow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(GATE_W * 1.9, GATE_H * 1.5)
	_glow.mesh = q
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.55)
	g.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.72, 0.36, 1.0))
	grad.set_color(1, Color(1.0, 0.7, 0.3, 0.0))
	g.gradient = grad
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.albedo_texture = g
	gm.albedo_color = Color(1, 1, 1, 0)
	_glow.material_override = gm
	_glow.position = Vector3(0, GATE_H * 0.5, -0.12)
	_gate.add_child(_glow)
	# golden motes drifting out of the doorway
	_motes = CPUParticles3D.new()
	_motes.emitting = false
	_motes.amount = 60
	_motes.lifetime = 3.0
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_motes.emission_box_extents = Vector3(GATE_W * 0.4, GATE_H * 0.4, 0.05)
	_motes.direction = Vector3(0, 0.25, 1)
	_motes.spread = 25.0
	_motes.initial_velocity_min = 0.08
	_motes.initial_velocity_max = 0.22
	_motes.gravity = Vector3.ZERO
	_motes.scale_amount_min = 0.5
	_motes.scale_amount_max = 1.2
	var dot := SphereMesh.new()
	dot.radius = 0.005
	dot.height = 0.01
	dot.radial_segments = 6
	dot.rings = 3
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(1.0, 0.85, 0.5)
	dot.material = dm
	_motes.mesh = dot
	_motes.position = Vector3(0, GATE_H * 0.5, -0.05)
	_gate.add_child(_motes)
	_key = _build_key()
	_key.position = Vector3(0, GATE_H * 0.48, 0.9)
	_key.visible = false
	_gate.add_child(_key)
	_title = Node3D.new()
	_title.visible = false
	_title.position = Vector3(0, GATE_H * 0.62, 0.25)
	_gate.add_child(_title)
	var save = get_node_or_null("/root/Save")
	var name_l := _label("مفاتيح", 0.0, 220, GOLD)
	name_l.outline_size = 18
	name_l.outline_modulate = Color("4f3826")
	_title.add_child(name_l)
	_title.add_child(_label("MAFATEEH", -0.21, 70, CREAM))
	_prompt = _label(save.text("اضغط الزناد لتبدأ", "Press the trigger to start") if save else "اضغط الزناد لتبدأ", -GATE_H * 0.62 + 0.08, 64, CREAM)
	_prompt.visible = false
	_title.add_child(_prompt)


func _label(s: String, y: float, size: int, c: Color) -> Label3D:
	var l := TableMenu.text(s, Vector3(0, y, 0), size, c)
	l.pixel_size = 0.001
	l.outline_size = 14
	l.outline_modulate = Color(0.25, 0.17, 0.1, 0.95)
	l.no_depth_test = true
	l.render_priority = 12
	return l


## A large old door key in gold: a ring bow, a shaft, the bit.
func _build_key() -> Node3D:
	var k := Node3D.new()
	var gold := StandardMaterial3D.new()
	gold.albedo_color = GOLD
	gold.metallic = 0.35
	gold.roughness = 0.35
	gold.emission_enabled = true
	gold.emission = Color("7a4a10")
	var bow := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.035
	t.outer_radius = 0.055
	bow.mesh = t
	bow.material_override = gold
	bow.rotation.x = PI / 2
	bow.position = Vector3(0, 0, 0.27)
	k.add_child(bow)
	var shaft := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.012
	c.bottom_radius = 0.012
	c.height = 0.24
	shaft.mesh = c
	shaft.material_override = gold
	shaft.rotation.x = PI / 2
	shaft.position = Vector3(0, 0, 0.11)
	k.add_child(shaft)
	_box(k, Vector3(0.012, 0.05, 0.03), Vector3(0, -0.03, 0.015), gold)
	_box(k, Vector3(0.012, 0.03, 0.02), Vector3(0, -0.02, 0.055), gold)
	return k


# --- the gate opening ------------------------------------------------------------------------

func _open_gate() -> void:
	_step = "gate"
	_gate.visible = true
	_gate.position.y = -GATE_H * 0.5 - 1.2
	_gate.scale = Vector3.ONE * 0.85
	TableKit.sfx(self, "gate_lift", Vector3.ZERO, -4.0)
	_tw = create_tween()
	_tw.tween_property(_gate, "position:y", -GATE_H * 0.5, 1.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.parallel().tween_property(_gate, "scale", Vector3.ONE, 1.3).set_trans(Tween.TRANS_SINE)
	_tw.tween_callback(func(): _key.visible = true)
	_tw.tween_property(_key, "position:z", 0.06, 0.9).from(0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tw.tween_callback(func(): TableKit.sfx(self, "unlock", _key.position, -2.0))
	_tw.tween_property(_key, "rotation:z", -PI / 2, 0.45).set_trans(Tween.TRANS_BACK)
	_tw.tween_interval(0.25)
	_tw.tween_callback(_swing)
	_tw.tween_interval(1.3)
	_tw.tween_callback(_show_title)


func _swing() -> void:
	TableKit.sfx(self, "door_creak", Vector3(0, GATE_H * 0.5, 0), -3.0)
	_motes.emitting = true
	var tw := create_tween().set_parallel()
	for i in _leaves.size():
		var s := 1.0 if i == 0 else -1.0   # (the left leaf turns +y, the right -y: both away)
		tw.tween_property(_leaves[i], "rotation:y", s * deg_to_rad(105), 1.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_key, "scale", Vector3.ONE * 0.01, 0.6)
	tw.tween_method(_glow_alpha, 0.0, 0.6, 1.4)


func _glow_alpha(a: float) -> void:
	(_glow.material_override as StandardMaterial3D).albedo_color.a = a


func _show_title() -> void:
	_step = "title"
	_title.visible = true
	_title.scale = Vector3.ONE * 0.2
	TableKit.sfx(self, "portal", _title.position, -6.0)
	var tw := create_tween()
	tw.tween_property(_title, "scale", Vector3.ONE, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _prompt.visible = true)


## Skips straight to the open gate and the name.
func _show_open() -> void:
	_gate.visible = true
	_gate.position.y = -GATE_H * 0.5
	_gate.scale = Vector3.ONE
	_key.visible = false
	for i in _leaves.size():
		_leaves[i].rotation.y = (1.0 if i == 0 else -1.0) * deg_to_rad(105)
	_glow_alpha(0.6)
	_motes.emitting = true
	_show_title()


func _leave() -> void:
	_step = "leaving"
	_prompt.visible = false
	TableKit.sfx(self, "ui_click", _title.position, -4.0)
	var tw := create_tween().set_parallel()
	tw.tween_property(_title, "scale", Vector3.ONE * 0.01, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_gate, "position:y", -GATE_H * 0.5 - 1.4, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_method(_glow_alpha, 0.6, 0.0, 0.6)
	tw.chain().tween_callback(func():
		finished.emit()
		queue_free())


## Where the pointer's ring goes on it (the doorway plane), or null.
func hover(origin: Vector3, dir: Vector3) -> Variant:
	var p = Plane(global_basis.z.normalized(), global_position).intersects_ray(origin, dir)
	if p == null or (p as Vector3).distance_to(global_position) > 1.6:
		return null
	return {"point": p, "normal": global_basis.z.normalized(), "interactive": _step == "title"}
