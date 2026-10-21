class_name VRScenery
extends Node3D
## Calm virtual surroundings for VR mode only (hidden in mixed reality): a sandy
## floor, low dunes, a Diriyah-style skyline of Najdi mud houses and watchtowers,
## and date palms. All geometry is generated once and merged into a few meshes
## (one per material), so the whole backdrop costs only a handful of draw calls.
##
## Najdi details: slightly battered (tapering) mud walls, stepped triangular
## crenellations (sharafat), rows of small triangular vents, palm-trunk beam ends
## and wooden water spouts below the parapet, carved wooden doors, corner turrets.
## Palms: ringed, gently curved trunks, arching pinnate fronds with drooping
## leaflets, a skirt of dry fronds and hanging date clusters.

var ground_mat: StandardMaterial3D
var far_mat: StandardMaterial3D  # mud plaster (tinted by time of day)
var stand: Node3D
var _rng := RandomNumberGenerator.new()


## Collects triangles per material, then emits one ArrayMesh with a surface each.
class Builder:
	var tools := {}  # material key -> SurfaceTool
	var order: Array = []

	func st(key: String) -> SurfaceTool:
		if not tools.has(key):
			var t := SurfaceTool.new()
			t.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[key] = t
			order.append(key)
		return tools[key]

	func tri(key: String, a: Vector3, b: Vector3, c: Vector3, col := Color.WHITE) -> void:
		var t := st(key)
		var n := (c - a).cross(b - a).normalized()
		for v in [a, b, c]:
			t.set_color(col)
			t.set_normal(n)
			t.add_vertex(v)

	func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col := Color.WHITE) -> void:
		tri(key, a, b, c, col)
		tri(key, a, c, d, col)

	## Box with a tapered top (inset per side), transformed by xf.
	func block(key: String, xf: Transform3D, size: Vector3, taper := 0.0, col := Color.WHITE) -> void:
		var hx := size.x / 2.0
		var hz := size.z / 2.0
		var tx := hx - taper
		var tz := hz - taper
		var b := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
		var t := [Vector3(-tx, size.y, -tz), Vector3(tx, size.y, -tz), Vector3(tx, size.y, tz), Vector3(-tx, size.y, tz)]
		for i in 4:
			b[i] = xf * b[i]
			t[i] = xf * t[i]
		for i in 4:
			var j := (i + 1) % 4
			quad(key, b[i], b[j], t[j], t[i], col)
		quad(key, t[0], t[1], t[2], t[3], col)

	## Triangular prism standing on xf's XZ plane (a crenellation / vent), facing +z.
	func gable(key: String, xf: Transform3D, w: float, h: float, d: float, col := Color.WHITE) -> void:
		var p := [Vector3(-w / 2, 0, d / 2), Vector3(w / 2, 0, d / 2), Vector3(0, h, d / 2),
			Vector3(-w / 2, 0, -d / 2), Vector3(w / 2, 0, -d / 2), Vector3(0, h, -d / 2)]
		for i in 6:
			p[i] = xf * p[i]
		tri(key, p[0], p[2], p[1], col)
		tri(key, p[3], p[4], p[5], col)
		quad(key, p[1], p[2], p[5], p[4], col)
		quad(key, p[0], p[3], p[5], p[2], col)

	## Open cylinder (or cone) along xf's +y, with optional ring bulges.
	func tube(key: String, xf: Transform3D, r0: float, r1: float, h: float, sides: int, col := Color.WHITE) -> void:
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var b0 := xf * Vector3(cos(a0) * r0, 0, sin(a0) * r0)
			var b1 := xf * Vector3(cos(a1) * r0, 0, sin(a1) * r0)
			var t0 := xf * Vector3(cos(a0) * r1, h, sin(a0) * r1)
			var t1 := xf * Vector3(cos(a1) * r1, h, sin(a1) * r1)
			quad(key, b0, t0, t1, b1, col)

	func commit(materials: Dictionary) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for key in order:
			var t: SurfaceTool = tools[key]
			t.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, materials[key])
		return mesh


func _ready() -> void:
	_rng.seed = 2131
	ground_mat = StandardMaterial3D.new()
	ground_mat.albedo_color = Color("dcc6a4")
	ground_mat.roughness = 1.0
	# Fine sand grain from the plaster texture, world-mapped so it never stretches.
	ground_mat.albedo_texture = Kit.tex("plaster_albedo.png")
	ground_mat.uv1_triplanar = true
	ground_mat.uv1_world_triplanar = true
	ground_mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	ground_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	far_mat = StandardMaterial3D.new()
	far_mat.albedo_color = Color("d4b08c")
	far_mat.roughness = 1.0
	far_mat.vertex_color_use_as_albedo = true
	far_mat.albedo_texture = Kit.tex("plaster_albedo.png")
	far_mat.normal_enabled = true
	far_mat.normal_texture = Kit.tex("plaster_normal.png")
	far_mat.normal_scale = 0.8
	far_mat.uv1_triplanar = true
	far_mat.uv1_world_triplanar = true
	far_mat.uv1_scale = Vector3(0.45, 0.45, 0.45)
	far_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_build_ground()
	_build_stand()
	_build_dunes()
	_build_town()
	_build_palms()


func _build_ground() -> void:
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


## Low wooden stand that carries the board in VR (follows the board).
func _build_stand() -> void:
	stand = Node3D.new()
	add_child(stand)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("6b4426")
	wood.albedo_texture = Kit.tex("wood_albedo.png")
	wood.roughness = 0.8
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
	rug.mesh = BoxMesh.new()
	var rug_mat := StandardMaterial3D.new()
	rug_mat.albedo_color = Color("8e3b2e")
	rug_mat.roughness = 1.0
	rug.material_override = rug_mat
	rug.set_meta("rug", true)
	stand.add_child(rug)


func _build_dunes() -> void:
	for i in 18:
		var a := i / 18.0 * TAU + _rng.randf_range(-0.1, 0.1)
		var r := _rng.randf_range(24.0, 36.0)
		var d := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 24
		s.rings = 10
		d.mesh = s
		d.material_override = ground_mat
		d.scale = Vector3(_rng.randf_range(6, 11), _rng.randf_range(0.8, 2.2), _rng.randf_range(4, 7))
		d.position = Vector3(cos(a) * r, -0.3, sin(a) * r)
		d.rotation.y = -a
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(d)


# --- Najdi town -------------------------------------------------------------------------

func _build_town() -> void:
	var b := Builder.new()
	# A loose arc of houses ahead and to the sides, with a few watchtowers and
	# stretches of town wall between them.
	var count := 11
	for i in count:
		var a := -PI / 2 + (i - (count - 1) / 2.0) * 0.2 + _rng.randf_range(-0.04, 0.04)
		var r := _rng.randf_range(14.0, 19.0)
		var pos := Vector3(cos(a) * r, 0, sin(a) * r)
		var xf := Transform3D(Basis(Vector3.UP, -a - PI / 2), pos)  # front (+z) faces the player
		if i % 4 == 2:
			_tower(b, xf)
		else:
			_house(b, xf)
		if i < count - 1 and _rng.randf() < 0.6:
			var a2 := a + 0.1
			var wx := Transform3D(Basis(Vector3.UP, -a2 - PI / 2), Vector3(cos(a2), 0, sin(a2)) * (r + 1.2))
			_wall(b, wx, _rng.randf_range(2.2, 3.2), 1.7)
	var mats := {
		"mud": far_mat,
		"wood": _mat(Color("5a3a22"), 0.85, Kit.tex("wood_albedo.png")),
		"dark": _mat(Color("2a1d15"), 1.0, null),
	}
	var mi := MeshInstance3D.new()
	mi.name = "Town"
	mi.mesh = b.commit(mats)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _mat(c: Color, rough: float, tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.vertex_color_use_as_albedo = true
	if tex:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(1.2, 1.2, 1.2)
	return m


func _mud_shade() -> Color:
	var v := _rng.randf_range(0.9, 1.06)
	return Color(v, v * _rng.randf_range(0.97, 1.0), v * _rng.randf_range(0.93, 1.0))


func _house(b: Builder, xf: Transform3D) -> void:
	var w := _rng.randf_range(3.0, 5.0)
	var d := _rng.randf_range(2.6, 3.6)
	var h := _rng.randf_range(2.8, 4.0)
	var col := _mud_shade()
	b.block("mud", xf, Vector3(w, h, d), 0.08, col)  # battered walls: wider at the base
	_parapet(b, xf.translated_local(Vector3(0, h, 0)), w - 0.16, d - 0.16, col)
	_facade(b, xf, w - 0.16, h, d / 2.0 - 0.06)
	# Upper storey on the larger houses.
	if w > 3.8 and _rng.randf() < 0.7:
		var uw := w * _rng.randf_range(0.45, 0.6)
		var ud := d * 0.7
		var ux := xf.translated_local(Vector3((w - uw) / 2.0 - 0.15, h, -0.2))
		var uh := _rng.randf_range(1.6, 2.2)
		b.block("mud", ux, Vector3(uw, uh, ud), 0.05, col.darkened(0.03))
		_parapet(b, ux.translated_local(Vector3(0, uh, 0)), uw - 0.1, ud - 0.1, col)
		_vents(b, ux.translated_local(Vector3(0, uh - 0.55, ud / 2.0 - 0.03)), uw - 0.6)


func _tower(b: Builder, xf: Transform3D) -> void:
	# Diriyah watchtower: tall, strongly tapering, with a crenellated crown.
	var base := _rng.randf_range(2.2, 2.8)
	var h := _rng.randf_range(6.5, 8.0)
	var col := _mud_shade()
	b.block("mud", xf, Vector3(base, h, base), 0.42, col)
	var top := base - 0.84
	_parapet(b, xf.translated_local(Vector3(0, h, 0)), top, top, col)
	for k in 3:  # slit windows climbing the front
		var y := h * (0.3 + k * 0.22)
		var inset := 0.42 * y / h
		b.block("dark", xf.translated_local(Vector3(0, y, base / 2.0 - inset + 0.01)), Vector3(0.12, 0.42, 0.04), 0.0)
	_vents(b, xf.translated_local(Vector3(0, h - 0.5, top / 2.0 + 0.02)), top - 0.3)


func _wall(b: Builder, xf: Transform3D, length: float, h: float) -> void:
	var col := _mud_shade()
	b.block("mud", xf, Vector3(length, h, 0.45), 0.05, col)
	var n := int(length / 0.42)
	for j in n:
		var x := -length / 2.0 + 0.21 + j * (length - 0.42) / maxf(n - 1, 1)
		_sharafa(b, xf.translated_local(Vector3(x, h, 0)), 0.3, col)


## Stepped triangular crenellations along all four edges, with taller corner turrets.
func _parapet(b: Builder, top: Transform3D, w: float, d: float, col: Color) -> void:
	b.block("mud", top, Vector3(w, 0.32, d), 0.0, col)
	var y := 0.32
	for edge in 4:
		var length := w if edge % 2 == 0 else d
		var basis := Basis(Vector3.UP, edge * PI / 2.0)
		var out := (d if edge % 2 == 0 else w) / 2.0 - 0.09
		var n := maxi(int(length / 0.45), 2)
		for j in n:
			var x := -length / 2.0 + 0.22 + j * (length - 0.44) / (n - 1)
			var p := top * Transform3D(basis, basis * Vector3(x, y, out))
			_sharafa(b, p, 0.3, col)
	for cx in [-1, 1]:
		for cz in [-1, 1]:
			var c := top.translated_local(Vector3(cx * (w / 2.0 - 0.2), y, cz * (d / 2.0 - 0.2)))
			b.block("mud", c, Vector3(0.42, 0.38, 0.42), 0.04, col)
			_sharafa(b, c.translated_local(Vector3(0, 0.38, 0)), 0.34, col)


## One Najdi crenellation: a stepped base with a pointed triangular cap.
func _sharafa(b: Builder, at: Transform3D, size: float, col: Color) -> void:
	b.block("mud", at, Vector3(size, size * 0.35, size * 0.5), 0.0, col)
	b.gable("mud", at.translated_local(Vector3(0, size * 0.35, 0)), size * 0.8, size * 0.75, size * 0.42, col)


## A row of small triangular vents (dark openings) just under the parapet.
func _vents(b: Builder, at: Transform3D, width: float) -> void:
	var n := maxi(int(width / 0.36), 2)
	for j in n:
		var x := -width / 2.0 + j * width / (n - 1)
		b.gable("dark", at.translated_local(Vector3(x, 0, 0)), 0.16, 0.18, 0.04)


## Front of a house: door, small windows, vents, beam ends and water spouts.
func _facade(b: Builder, xf: Transform3D, w: float, h: float, front: float) -> void:
	var f := xf.translated_local(Vector3(0, 0, front))
	var door_x := _rng.randf_range(-w * 0.25, w * 0.25)
	b.block("wood", f.translated_local(Vector3(door_x, 0, 0.03)), Vector3(0.9, 1.75, 0.06), 0.0)
	b.block("dark", f.translated_local(Vector3(door_x, 0.05, 0.065)), Vector3(0.08, 1.6, 0.01), 0.0)  # leaf seam
	b.gable("mud", f.translated_local(Vector3(door_x, 1.78, 0.05)), 1.1, 0.35, 0.12)  # pointed lintel
	for k in range(-1, 2, 2):
		var wx := door_x + k * _rng.randf_range(1.0, 1.5)
		if absf(wx) < w / 2.0 - 0.3:
			b.block("dark", f.translated_local(Vector3(wx, h * 0.55, 0.02)), Vector3(0.36, 0.42, 0.03), 0.0)
			b.block("wood", f.translated_local(Vector3(wx, h * 0.55 - 0.05, 0.05)), Vector3(0.44, 0.05, 0.05), 0.0)
	_vents(b, f.translated_local(Vector3(0, h - 0.62, 0.01)), w - 0.7)
	# Palm-trunk roof beams poke through just under the roof line.
	var n := int(w / 0.6)
	for j in n:
		var x := -w / 2.0 + 0.3 + j * (w - 0.6) / maxf(n - 1, 1)
		b.tube("wood", f.translated_local(Vector3(x, h - 0.2, -0.05)) * Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3.ZERO), 0.05, 0.05, 0.2, 5)
	for sx in [-0.3, 0.3]:  # wooden water spouts (mirzab)
		b.block("wood", f.translated_local(Vector3(sx * w, h - 0.05, 0.2)), Vector3(0.1, 0.08, 0.5), 0.0)


# --- date palms --------------------------------------------------------------------------

func _build_palms() -> void:
	var b := Builder.new()
	var placed := 0
	var tries := 0
	while placed < 16 and tries < 80:
		tries += 1
		var a := _rng.randf_range(0, TAU)
		var r := _rng.randf_range(6.5, 15.0)
		var ahead := absf(wrapf(a + PI / 2, -PI, PI)) < 0.45
		if ahead and r < 11.0:
			continue  # keep the near view toward the board and the town open
		var pos := Vector3(cos(a) * r, 0, sin(a) * r)
		_palm(b, pos, _rng.randf_range(4.0, 6.5))
		placed += 1
		if _rng.randf() < 0.4:  # date palms grow in clumps
			_palm(b, pos + Vector3(_rng.randf_range(-1.4, 1.4), 0, _rng.randf_range(-1.4, 1.4)), _rng.randf_range(2.4, 3.8))
	var trunk := _mat(Color("8a6a48"), 0.95, null)
	var leaf := _mat(Color("ffffff"), 0.7, null)
	leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf.vertex_color_use_as_albedo = true
	var dry := _mat(Color("a07a4a"), 0.95, null)
	dry.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dates := _mat(Color("b4642a"), 0.6, null)
	var mi := MeshInstance3D.new()
	mi.name = "Palms"
	mi.mesh = b.commit({"trunk": trunk, "leaf": leaf, "dry": dry, "dates": dates})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)


func _palm(b: Builder, base: Vector3, height: float) -> void:
	# Trunk: gently curved, made of short ringed segments (old frond bases).
	var lean := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(0.04, 0.12)
	var segs := int(height / 0.32)
	var p := base
	var dir := Vector3.UP
	for i in segs:
		var t := float(i) / segs
		dir = (Vector3.UP + lean * (1.0 + t * 2.0)).normalized()
		var r := lerpf(0.2, 0.15, t)
		var len := height / segs
		var xf := Transform3D(_basis_to(dir), p)
		var shade := Color(1, 1, 1) if i % 2 == 0 else Color(0.82, 0.8, 0.78)
		b.tube("trunk", xf, r * 1.08, r, len * 0.55, 7, shade)  # ring bulge
		b.tube("trunk", xf.translated_local(Vector3(0, len * 0.55, 0)), r, r * 1.08, len * 0.45, 7, shade.darkened(0.08))
		p += dir * len
	var crown := p
	# Fronds: arching rachis with paired leaflets that droop toward the tip.
	var n := _rng.randi_range(14, 18)
	for k in n:
		var yaw := TAU * k / n + _rng.randf_range(-0.15, 0.15)
		var up := _rng.randf_range(-0.15, 0.75) if k % 3 != 0 else _rng.randf_range(0.6, 1.0)
		_frond(b, crown, yaw, up, _rng.randf_range(1.9, 2.6), "leaf")
	for k in 6:  # skirt of dry, hanging fronds
		_frond(b, crown + Vector3(0, -0.25, 0), TAU * k / 6.0 + 0.3, -1.1, 1.3, "dry")
	for k in 3:  # date clusters
		var a := TAU * k / 3.0 + 0.5
		var c := crown + Vector3(cos(a) * 0.28, -0.45, sin(a) * 0.28)
		b.tube("dates", Transform3D(Basis(), c), 0.14, 0.03, 0.4, 6)
		b.tube("dates", Transform3D(Basis(Vector3.RIGHT, PI), c), 0.14, 0.05, 0.12, 6)


func _frond(b: Builder, start: Vector3, yaw: float, rise: float, length: float, key: String) -> void:
	var out := Vector3(cos(yaw), 0, sin(yaw))
	var side := out.cross(Vector3.UP).normalized()
	var steps := 9
	var prev := start
	var base_col := Color("3f5f24") if key == "leaf" else Color("a07a4a")
	var tip_col := Color("7f9a45") if key == "leaf" else Color("8a6640")
	for i in range(1, steps + 1):
		var t := float(i) / steps
		# Parabolic arch: rises first, then bends down under its own weight.
		var pt := start + out * length * t + Vector3.UP * (rise * t - 1.15 * t * t) * length * 0.55
		var col := base_col.lerp(tip_col, t)
		var leaflet := lerpf(0.55, 0.12, t)
		var droop := Vector3.DOWN * leaflet * 0.55
		for s in [-1, 1]:
			var tip: Vector3 = pt + side * s * leaflet + droop + out * leaflet * 0.25
			var mid := prev.lerp(pt, 0.5)
			b.tri(key, prev, pt, tip, col)
			b.tri(key, mid, tip, pt, col.darkened(0.12))
		prev = pt


static func _basis_to(dir: Vector3) -> Basis:
	var axis := Vector3.UP.cross(dir)
	if axis.length_squared() < 1e-6:
		return Basis()
	return Basis(axis.normalized(), Vector3.UP.angle_to(dir))


func set_tint(p: Dictionary, wet: float) -> void:
	if ground_mat == null:
		return
	ground_mat.albedo_color = Color("dcc6a4").lerp(p.ground, 0.25).darkened(wet * 0.25)
	far_mat.albedo_color = Color("d4b08c").lerp(p.horizon, 0.18).darkened(wet * 0.2)


## Keep the stand under the board footprint (world space, meters).
func follow(board: BoardPlacement) -> void:
	if stand == null:
		return
	var s := board.board_scale
	var w := 10.1 * s
	var d := 9.4 * s
	var h := board.surface_height
	set_stand(Transform3D(Basis(Vector3.UP, board.rotation.y), Vector3(board.global_position.x, h, board.global_position.z) + board.global_transform.basis.z.normalized() * -0.3 * s), w, d)


## The stand with its top at `top` (world space), w by d metres across.
func set_stand(top: Transform3D, w: float, d: float) -> void:
	var h := top.origin.y
	stand.global_transform = top
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
