class_name Kit
extends RefCounted
## Shared art resources: one material per surface type, cached meshes, and
## the Najdi modular kit (res://assets/kit/najdi_kit.glb, authored in Blender
## by tools/blender/build_kit.py). Every piece has a procedural fallback so
## the game still runs if an asset fails to import.

const KIT_PATH := "res://assets/kit/najdi_kit.glb"
const TEX := "res://assets/textures/"

const PUZZLE_COLORS := [Color("e8b74f"), Color("75b9d3"), Color("bd91ce"), Color("df8b78")]

static var _materials := {}
static var _meshes := {}
static var _kit_meshes := {}
static var _kit_loaded := false


static func tex(name: String) -> Texture2D:
	var path := TEX + name
	if ResourceLoader.exists(path):
		return load(path)
	return null


static func mat(name: String) -> Material:
	if _materials.has(name):
		return _materials[name]
	var m := StandardMaterial3D.new()
	m.roughness = 0.9
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	match name:
		"plaster", "plaster_top":
			m.albedo_color = Color("c8935f") if name == "plaster" else Color("d6a676")
			m.albedo_texture = tex("plaster_albedo.png")
			m.normal_enabled = m.albedo_texture != null and tex("plaster_normal.png") != null
			m.normal_texture = tex("plaster_normal.png")
			m.normal_scale = 0.8
			m.uv1_triplanar = true
			m.uv1_world_triplanar = false
			m.uv1_scale = Vector3(0.9, 0.9, 0.9)
			m.roughness = 0.95
		"stone":
			m.albedo_color = Color("e2cca4")
			m.albedo_texture = tex("stone_albedo.png")
			m.normal_texture = tex("stone_normal.png")
			m.normal_enabled = m.normal_texture != null
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(1.0, 1.0, 1.0)
			m.roughness = 0.88
		"sand":
			m.albedo_color = Color("cfae80")
			m.roughness = 1.0
		"stone_dark":
			m.albedo_color = Color("b79d74")
			m.roughness = 0.9
		"wood":
			m.albedo_color = Color("7a4b2a")
			m.albedo_texture = tex("wood_albedo.png")
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(1.6, 1.6, 1.6)
			m.roughness = 0.8
		"wood_light":
			m.albedo_color = Color("a2703f")
			m.albedo_texture = tex("wood_albedo.png")
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(1.6, 1.6, 1.6)
			m.roughness = 0.82
		"iron":
			m.albedo_color = Color("2e2925")
			m.roughness = 0.55
			m.metallic = 0.4
		"brass":
			m.albedo_color = Color("d0a24a")
			m.roughness = 0.42
			m.metallic = 0.65
		"brass_dark":
			m.albedo_color = Color("8f6a2a")
			m.roughness = 0.5
			m.metallic = 0.5
		"water":
			m.albedo_color = Color(0.32, 0.62, 0.68, 0.78)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.08
			m.metallic = 0.1
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		"pool_tile":
			m.albedo_color = Color("5fb2c2")
			m.roughness = 0.4
		"palm_trunk":
			m.albedo_color = Color("7a5a3a")
			m.roughness = 0.95
		"palm_leaf":
			m.albedo_color = Color("5f7d38")
			m.roughness = 0.85
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"shrub":
			m.albedo_color = Color("6f8a40")
			m.roughness = 0.9
		"cloth_red":
			m.albedo_color = Color("b8443a")
		"glass":
			m.albedo_color = Color("cfe4e6")
			m.roughness = 0.12
			m.metallic = 0.3
		"beam":
			var u := StandardMaterial3D.new()
			u.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			u.albedo_color = Color(1.0, 0.86, 0.5, 0.85)
			u.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			u.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			_materials[name] = u
			return u
		"glow":
			m.albedo_color = Color("ffd98a")
			m.emission_enabled = true
			m.emission = Color("ffb950")
			m.emission_energy_multiplier = 1.6
		"lamp_off":
			m.albedo_color = Color("5b6a66")
			m.roughness = 0.6
		"shadow_blob":
			var s := StandardMaterial3D.new()
			s.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			s.albedo_color = Color(0.15, 0.1, 0.06, 0.35)
			s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			s.albedo_texture = _radial_texture()
			s.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			_materials[name] = s
			return s
		"invisible":
			var s := StandardMaterial3D.new()
			s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			s.albedo_color = Color(0, 0, 0, 0)
			_materials[name] = s
			return s
		_:
			if name.begins_with("puzzle_"):
				var i := int(name.substr(7))
				m.albedo_color = PUZZLE_COLORS[i % 4]
				m.roughness = 0.6
			elif name.begins_with("lit_"):
				var i := int(name.substr(4))
				m.albedo_color = PUZZLE_COLORS[i % 4]
				m.emission_enabled = true
				m.emission = PUZZLE_COLORS[i % 4]
				m.emission_energy_multiplier = 1.4
	if m.albedo_texture != null and name in ["plaster", "plaster_top", "stone", "wood", "wood_light"]:
		var tint: Color = {"plaster": Color(1, 1, 1), "plaster_top": Color(1.08, 1.06, 1.04), "stone": Color(1, 1, 1),
			"wood": Color(0.95, 0.92, 0.9), "wood_light": Color(1.35, 1.3, 1.25)}[name]
		m.albedo_color = tint
	_materials[name] = m
	return m


static func _radial_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


# --- meshes -----------------------------------------------------------------------

static func _load_kit() -> void:
	if _kit_loaded:
		return
	_kit_loaded = true
	if not ResourceLoader.exists(KIT_PATH):
		return
	var scene: PackedScene = load(KIT_PATH)
	if scene == null:
		return
	var root := scene.instantiate()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		_kit_meshes[String(n.name).to_lower()] = n.mesh
	root.free()


## A named Blender kit mesh, or null when unavailable.
static func piece(name: String) -> Mesh:
	_load_kit()
	return _kit_meshes.get(name.to_lower(), null)


static func box(size: Vector3) -> Mesh:
	var key := "box%s" % size
	if not _meshes.has(key):
		var b := BoxMesh.new()
		b.size = size
		_meshes[key] = b
	return _meshes[key]


static func cylinder(r_top: float, r_bottom: float, h: float, segs := 16) -> Mesh:
	var key := "cyl%s_%s_%s_%d" % [r_top, r_bottom, h, segs]
	if not _meshes.has(key):
		var c := CylinderMesh.new()
		c.top_radius = r_top
		c.bottom_radius = r_bottom
		c.height = h
		c.radial_segments = segs
		c.rings = 1
		_meshes[key] = c
	return _meshes[key]


static func sphere(r: float, segs := 12) -> Mesh:
	var key := "sph%s_%d" % [r, segs]
	if not _meshes.has(key):
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = segs
		s.rings = segs / 2
		_meshes[key] = s
	return _meshes[key]


static func torus(inner: float, outer: float) -> Mesh:
	var key := "tor%s_%s" % [inner, outer]
	if not _meshes.has(key):
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = 20
		t.ring_segments = 8
		_meshes[key] = t
	return _meshes[key]


static func prism(size: Vector3) -> Mesh:
	var key := "pri%s" % size
	if not _meshes.has(key):
		var p := PrismMesh.new()
		p.size = size
		_meshes[key] = p
	return _meshes[key]


static func octahedron(r: float) -> Mesh:
	var key := "oct%s" % r
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v := [Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, r * 1.3, 0), Vector3(0, -r * 1.3, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]
	var faces := [[2, 4, 0], [2, 1, 4], [2, 5, 1], [2, 0, 5], [3, 0, 4], [3, 4, 1], [3, 1, 5], [3, 5, 0]]
	for f in faces:
		var n: Vector3 = (v[f[1]] - v[f[0]]).cross(v[f[2]] - v[f[0]]).normalized()
		for i in f:
			st.set_normal(-n)
			st.add_vertex(v[i])
	var m := st.commit()
	_meshes[key] = m
	return m


static func add(parent: Node3D, mesh: Mesh, material: Material, pos := Vector3.ZERO, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Kit piece if present, else the fallback mesh. Pieces listed in
## OWN_MATERIALS keep their authored materials (painted wood, iron, leaves);
## the rest take the shared material so walls and paving stay one look.
const OWN_MATERIALS := ["door_leaf", "crate", "key", "palm", "shrub", "lantern", "stepping_stone", "pool_edge", "tree"]


static func add_piece(parent: Node3D, name: String, fallback: Mesh, material: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var m := piece(name)
	var keep := m != null and name in OWN_MATERIALS
	var mi := add(parent, m if m != null else fallback, null if keep else material, pos)
	return mi


static func has_piece(name: String) -> bool:
	return piece(name) != null


## Symbols distinguish puzzle elements independently of colour:
## 0 ring, 1 triangle, 2 diamond, 3 cross.
static func emblem(parent: Node3D, index: int, material: Material, pos: Vector3, size := 0.18) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	match index % 4:
		0:
			add(root, torus(size * 0.62, size), material)
		1:
			var p := add(root, prism(Vector3(size * 1.9, size * 1.7, 0.05)), material)
			p.rotation.x = -PI / 2
		2:
			var d := add(root, box(Vector3(size * 1.25, 0.05, size * 1.25)), material)
			d.rotation.y = PI / 4
		3:
			add(root, box(Vector3(size * 1.9, 0.05, size * 0.42)), material)
			add(root, box(Vector3(size * 0.42, 0.05, size * 1.9)), material)
	return root
