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
	p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"   # quiet, see table_main
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


## Aim assist: a ray that misses every box by less than this angle still picks the one it
## passes closest to (the pointer snaps to it), so small things on the table are easy to hit.
const ASSIST := 0.035  # radians, 2 degrees: a couple of centimetres at arm's length


## What the ray meets first in the scene itself this frame (set by the game before the level
## reads its ray): a piece behind that wall or roof cannot be picked through it, and the piece
## already under the pointer is the one a press picks at the edge of the assist.
static var wall_o := Vector3.INF   # the ray's origin (the wall counts only for that ray)
static var wall_t := INF           # world distance to the first scene surface
static var wall_tol := 0.0         # world slack: a piece standing on that surface still counts
static var held_id := ""           # the piece under the pointer


static func set_wall(origin: Vector3, t: float, tol: float, held: String) -> void:
	wall_o = origin
	wall_t = t
	wall_tol = tol
	held_id = held


## The pick under a world ray among boxes {id: AABB} given in parent-local space; "" if none.
static func ray_pick(parent: Node3D, ray: Array, boxes: Dictionary, assist := true) -> String:
	return ray_hit(parent, ray, boxes, assist).get("id", "")


## The box under a world ray (or, failing that, the one it passes within ASSIST of):
## {id, box, point, normal, snapped (true when found by the assist)} in parent-local space, or
## {} if none. Nothing hidden behind the scene's first surface along the ray is found.
static func ray_hit(parent: Node3D, ray: Array, boxes: Dictionary, assist := true, held := "") -> Dictionary:
	if ray.size() != 2 or boxes.is_empty():
		return {}
	if held == "":
		held = held_id
	var walled := (ray[0] as Vector3).is_equal_approx(wall_o) and wall_t < INF
	var o := parent.to_local(ray[0])
	var d := (parent.to_local(ray[0] + ray[1]) - o).normalized()
	var best := ""
	var best_t := INF
	var best_p := Vector3.ZERO
	for id in boxes:
		var hit = (boxes[id] as AABB).intersects_ray(o, d)
		if hit != null and walled and (ray[0] as Vector3).distance_to(parent.to_global(hit)) > wall_t + wall_tol:
			continue   # behind a wall or a roof
		if hit != null and o.distance_to(hit) < best_t:
			best_t = o.distance_to(hit)
			best = id
			best_p = hit
	if best != "":
		var b: AABB = boxes[best]
		return {"id": best, "box": b, "point": best_p, "normal": _face_normal(b, best_p)}
	if not assist:
		return {}
	var near := ""
	var near_a := ASSIST
	for id in boxes:
		var b: AABB = boxes[id]
		var v := b.get_center() - o
		var t := v.dot(d)
		if t <= 0.0:
			continue
		# the angle to the box, less its own half size seen from here
		var a := atan2((v - d * t).length(), t) - atan2(b.size.length() * 0.25, t)
		if id == held:
			a -= ASSIST * 0.8   # the one already under the pointer holds on a little longer: no flicker at the edge
		if a < near_a and walled:
			var top_w := parent.to_global(Vector3(b.get_center().x, b.end.y, b.get_center().z))
			var reach := (parent.global_basis * (b.size * 0.5)).length()
			if (ray[0] as Vector3).distance_to(top_w) > wall_t + wall_tol + reach:
				continue   # the ray stops on something well in front of it
		if a < near_a:
			near_a = a
			near = id
	if near == "":
		return {}
	var nb: AABB = boxes[near]
	var top := Vector3(nb.get_center().x, nb.end.y, nb.get_center().z)
	return {"id": near, "box": nb, "point": top, "normal": Vector3.UP, "snapped": true}


static func _face_normal(b: AABB, p: Vector3) -> Vector3:
	var best := Vector3.UP
	var best_d := absf(p.y - b.end.y)
	for f in [[absf(p.x - b.position.x), Vector3.LEFT], [absf(p.x - b.end.x), Vector3.RIGHT],
			[absf(p.z - b.position.z), Vector3.FORWARD], [absf(p.z - b.end.z), Vector3.BACK],
			[absf(p.y - b.position.y), Vector3.DOWN]]:
		if f[0] < best_d:
			best_d = f[0]
			best = f[1]
	return best
