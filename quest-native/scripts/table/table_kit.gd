class_name TableKit
## Small shared helpers for the table levels (materials, rings, sounds, simple meshes).


static func mat(c: Color, rough := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func glow_mat(c: Color, alpha := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## A light that ignores the scene's lighting (lamp flames, lit windows).
static func lit_mat(c: Color, energy := 1.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


static func mesh(parent: Node3D, m: Mesh, material: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, material: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mesh(parent, b, material, pos, rot)


static func cyl(parent: Node3D, r_top: float, r_bottom: float, h: float, material: Material, pos := Vector3.ZERO, segs := 12) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return mesh(parent, c, material, pos)


static func sphere(parent: Node3D, r: float, material: Material, pos := Vector3.ZERO, segs := 10) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2
	s.radial_segments = segs
	s.rings = segs / 2
	return mesh(parent, s, material, pos)


## A flat ring on the ground (a torus squashed by its parent's scale if wanted).
static func ring(parent: Node3D, r: float, c: Color, alpha := 0.9, thickness := 0.08) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r * (1.0 - thickness)
	t.outer_radius = r
	t.rings = 40
	t.ring_segments = 4
	return mesh(parent, t, glow_mat(c, alpha))


static func face(n: Node3D, d: Vector3) -> void:
	if n and Vector2(d.x, d.z).length() > 0.001:
		n.rotation.y = atan2(d.x, d.z)


static func sfx(parent: Node3D, name: String, at: Vector3, db := 0.0, pitch := 1.0) -> void:
	var path := "res://audio/sfx/" + name + ".wav"
	if not ResourceLoader.exists(path) or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = load(path)
	p.volume_db = db
	p.pitch_scale = pitch
	parent.add_child(p)
	p.position = at
	p.play()
	p.finished.connect(p.queue_free)


## Loads a GLB scene under parent, or null.
static func model(parent: Node3D, path: String, pos := Vector3.ZERO, yaw := 0.0, scale := 1.0) -> Node3D:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var n: Node3D = ps.instantiate()
	parent.add_child(n)
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3.ONE * scale
	for g in n.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


## The pick under a world ray among boxes {id: AABB} given in parent-local space; "" if none.
static func ray_pick(parent: Node3D, ray: Array, boxes: Dictionary) -> String:
	if ray.size() != 2:
		return ""
	var o := parent.to_local(ray[0])
	var d := parent.to_local(ray[0] + ray[1]) - o
	var best := ""
	var best_t := INF
	for id in boxes:
		var hit = (boxes[id] as AABB).intersects_ray(o, d)
		if hit != null and o.distance_to(hit) < best_t:
			best_t = o.distance_to(hit)
			best = id
	return best
