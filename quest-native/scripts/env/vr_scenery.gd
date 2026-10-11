class_name VRScenery
extends Node3D
## Calm virtual surroundings for VR mode only (hidden in mixed reality):
## a sandy floor, low dunes and distant Najdi houses and palms. Built once,
## all low-poly, sharing a handful of materials.

var ground_mat: StandardMaterial3D
var far_mat: StandardMaterial3D
var stand: Node3D


func _ready() -> void:
	ground_mat = StandardMaterial3D.new()
	ground_mat.albedo_color = Color("c9a57a")
	ground_mat.roughness = 1.0
	far_mat = StandardMaterial3D.new()
	far_mat.albedo_color = Color("b98a5c")
	far_mat.roughness = 1.0
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 60.0
	disc.bottom_radius = 60.0
	disc.height = 0.02
	disc.radial_segments = 48
	ground.mesh = disc
	ground.material_override = ground_mat
	ground.position.y = -0.011
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	# Low wooden stand that carries the board in VR (follows the board).
	stand = Node3D.new()
	add_child(stand)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("6b4426")
	wood.roughness = 0.85
	var top := MeshInstance3D.new()
	top.mesh = BoxMesh.new()
	top.material_override = wood
	top.position.y = -0.02
	top.scale = Vector3(1.0, 0.04, 1.0)
	stand.add_child(top)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var leg := MeshInstance3D.new()
			leg.mesh = BoxMesh.new()
			leg.material_override = wood
			leg.set_meta("corner", Vector2(sx, sz))
			stand.add_child(leg)
	var rug := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rug.mesh = rm
	var rug_mat := StandardMaterial3D.new()
	rug_mat.albedo_color = Color("8e3b2e")
	rug_mat.roughness = 1.0
	rug.material_override = rug_mat
	rug.set_meta("rug", true)
	stand.add_child(rug)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2131
	# Dunes.
	for i in 18:
		var a := i / 18.0 * TAU + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(22.0, 34.0)
		var d := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 16
		s.rings = 8
		d.mesh = s
		d.material_override = ground_mat
		d.scale = Vector3(rng.randf_range(6, 11), rng.randf_range(0.8, 2.2), rng.randf_range(4, 7))
		d.position = Vector3(cos(a) * r, -0.3, sin(a) * r)
		d.rotation.y = -a
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(d)
	# Distant Najdi houses with crenellated parapets.
	for i in 9:
		var a := -PI / 2 + (i - 4) * 0.22 + rng.randf_range(-0.05, 0.05)
		var r := rng.randf_range(13.0, 18.0)
		var house := Node3D.new()
		house.position = Vector3(cos(a) * r, 0, sin(a) * r)
		house.rotation.y = -a + PI / 2
		add_child(house)
		var w := rng.randf_range(2.0, 4.0)
		var h := rng.randf_range(2.2, 4.2)
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, h, rng.randf_range(2.0, 3.0))
		b.mesh = bm
		b.material_override = far_mat
		b.position.y = h / 2.0
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		house.add_child(b)
		for j in int(w / 0.5):
			var c := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(0.3, 0.32, 0.25)
			c.mesh = pm
			c.material_override = far_mat
			c.position = Vector3(-w / 2.0 + 0.25 + j * 0.5, h + 0.16, bm.size.z / 2.0 - 0.1)
			house.add_child(c)
	# Palm groves.
	var trunk := StandardMaterial3D.new()
	trunk.albedo_color = Color("6e5134")
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color("5c7a37")
	leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 14:
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(7.0, 16.0)
		if absf(wrapf(a + PI / 2, -PI, PI)) < 0.5:
			continue  # keep the view toward the board open
		var p := Node3D.new()
		p.position = Vector3(cos(a) * r, 0, sin(a) * r)
		add_child(p)
		var height := rng.randf_range(3.0, 5.0)
		var t := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.12
		tm.bottom_radius = 0.2
		tm.height = height
		tm.radial_segments = 8
		t.mesh = tm
		t.material_override = trunk
		t.position.y = height / 2.0
		t.rotation.z = rng.randf_range(-0.12, 0.12)
		p.add_child(t)
		for k in 9:
			var f := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(0.35, 0.03, 1.9)
			f.mesh = fm
			f.material_override = leaf
			var fa := k / 9.0 * TAU
			f.position = Vector3(sin(fa) * 0.8, height - 0.15, cos(fa) * 0.8)
			f.rotation = Vector3(0.45, fa, 0)
			p.add_child(f)


func set_tint(p: Dictionary, wet: float) -> void:
	if ground_mat == null:
		return
	ground_mat.albedo_color = Color("c9a57a").lerp(p.ground, 0.35).darkened(wet * 0.25)
	far_mat.albedo_color = Color("b98a5c").lerp(p.horizon, 0.25).darkened(wet * 0.2)


## Keep the stand under the board footprint (world space, meters).
func follow(board: BoardPlacement) -> void:
	if stand == null:
		return
	var s := board.board_scale
	var w := 10.1 * s
	var d := 9.4 * s
	var h := board.surface_height
	stand.global_transform = Transform3D(Basis(Vector3.UP, board.rotation.y), Vector3(board.global_position.x, h, board.global_position.z) + board.global_transform.basis.z.normalized() * -0.3 * s)
	for c in stand.get_children():
		if c.has_meta("corner"):
			var k: Vector2 = c.get_meta("corner")
			c.scale = Vector3(0.06, h, 0.06)
			c.position = Vector3(k.x * (w / 2.0 - 0.06), -h / 2.0, k.y * (d / 2.0 - 0.06))
		elif c.has_meta("rug"):
			c.scale = Vector3(w * 1.6, 0.006, d * 1.6)
			c.position = Vector3(0, -h + 0.003, 0)
		else:
			c.scale = Vector3(w + 0.04, 0.04, d + 0.04)
