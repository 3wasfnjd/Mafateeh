class_name TablePathLevel
extends Node3D
## Level 1 on the table, «درب في الرمل» (a path in the sand). Wordless.
## The old man sits on his mat on the porch, inside the courtyard. His cat is out on the sand
## beyond the gate, with thorn bushes in between. Hold the trigger on the cat and draw its way
## home: round the thorns, in through the gate (the line can't go through walls; near the gate
## it slips through the opening by itself), across the courtyard to him. Let go and the cat
## follows the line. A thorn sends it hopping back. When it reaches him it sits at his knee
## and he strokes it; that ends the level.
##
## Lives under Diorama.model, so every position here is in the diorama's own metres
## (Godot axes, +Z = outside the gate).

signal level_won

const SFX := "res://audio/sfx/"
const MAT := "res://assets/world/props/majlis.glb"   # the owner's mat, when it arrives
const SEAT := Vector3(0.0, 0.0, 0.75)        # the old man on the porch, facing the gate
const HOME := Vector3(-0.22, 0.0, 1.45)      # where the cat sits to be stroked (his right hand)
const GATE_OUT := Vector3(0.03, 0.0, 7.0)
const GATE_IN := Vector3(0.03, 0.0, 5.5)
const START := Vector3(0.0, 0.0, 11.2)
# the only ground the cat may be led over: the courtyard, and the paved ellipse outside the
# gate (must match APRON in tools/blender/build_scene1.py): centre x, centre z, radii x, z
const APRON := [0.0, 8.6, 4.6, 3.9]
const COURT := Rect2(-8.0, -6.0, 16.0, 12.0)
const THORN_R := 0.75
const CAT_R := 0.3                           # how close the cat may come to a wall
const POINT_STEP := 0.3
const WALK_SPEED := 2.4
const START_RADIUS := 1.4
const HOME_RADIUS := 0.9
# two rows outside the gate: round the far row at either end, then through the gap in the near one
const THORNS := [Vector2(-1.4, 10.0), Vector2(0.0, 10.0), Vector2(1.4, 10.0), Vector2(2.8, 10.0),
	Vector2(-3.2, 8.0), Vector2(-1.9, 8.0), Vector2(1.9, 8.0), Vector2(3.2, 8.0)]
# solid ground plan (model metres): walls, the house, the tower — x0, z0, x1, z1
const BLOCKS := [
	Rect2(-8.5, 6.0, 8.03, 0.5),   # front wall, left of the gate
	Rect2(0.53, 6.0, 7.97, 0.5),   # front wall, right of the gate
	Rect2(-8.5, -6.5, 17.0, 0.5),  # back wall
	Rect2(-8.5, -6.5, 0.5, 13.0),  # left wall
	Rect2(8.0, -6.5, 0.5, 13.0),   # right wall
	Rect2(-3.3, -6.5, 6.6, 6.55),  # the house
	Rect2(5.7, 4.0, 5.1, 4.5),     # the tower
	Rect2(-2.6, 1.4, 0.6, 0.6),    # porch columns
	Rect2(2.0, 1.4, 0.6, 0.6),
]
# a path that works (hint dot, screenshots and tests)
const SOLUTION := [Vector3(-2.6, 0, 11.0), Vector3(-2.6, 0, 9.0), Vector3(0.03, 0, 9.0), GATE_OUT, GATE_IN]

var diorama: Diorama
var cat: Node3D
var thorns: Array = []  # {node, pos: Vector2}
var _path := PackedVector3Array()
var _drawing := false
var _walking := false
var _walk_i := 0
var _won := false
var _line: MeshInstance3D
var _start_ring: MeshInstance3D
var _goal_ring: MeshInstance3D
var _ghost: MeshInstance3D
var _ghost_t := 0.0
var _ghost_on := true
var _idle_t := 0.0
var _t := 0.0
var _bump_t := 0.0


func setup(d: Diorama) -> void:
	diorama = d
	_add_mat()
	if diorama.shaib:
		diorama.shaib.position = SEAT
		diorama.shaib.rotation.y = 0.0
		diorama.play_shaib("sit_idle", "")
	cat = CreatureSlot.spawn(self, "cat")
	cat.scale = Vector3.ONE * Diorama.LIFE_SCALE.cat
	_start_ring = _ring(0.9, Color("f1dcae"))
	_goal_ring = _ring(1.0, Color("e6b85a"))
	_goal_ring.position = HOME + Vector3(0, 0.06, 0)
	_line = MeshInstance3D.new()
	_line.mesh = ImmediateMesh.new()
	_line.material_override = _glow_mat(Color("fff4dc"), 0.95)
	add_child(_line)
	_ghost = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	_ghost.mesh = sm
	_ghost.material_override = _glow_mat(Color("fff4dc"), 0.85)
	add_child(_ghost)
	var i := 0
	for p in THORNS:
		var n := _thorn_bush(Vector3(p.x, 0, p.y))
		n.scale = Vector3.ONE * 0.01
		create_tween().tween_property(n, "scale", Vector3.ONE, 0.35).set_delay(0.1 * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		thorns.append({"node": n, "pos": p})
		i += 1
	cat.position = START
	_face(cat, GATE_OUT - START)
	CreatureSlot.play(cat, "sit")


## The mat and cushion he sits on: the owner's model when it exists, else a simple stand-in.
func _add_mat() -> void:
	if ResourceLoader.exists(MAT):
		var m: Node3D = (load(MAT) as PackedScene).instantiate()
		add_child(m)
		m.position = SEAT
		return
	var rug := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.9, 0.05, 1.4)
	rug.mesh = bm
	rug.material_override = _mat(Color("8e3b2e"))
	rug.position = SEAT + Vector3(0, 0.025, 0.05)
	add_child(rug)
	var band := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(1.94, 0.052, 0.16)
	band.mesh = bb
	band.material_override = _mat(Color("d9b36a"))
	band.position = SEAT + Vector3(0, 0.027, 0.55)
	add_child(band)
	var cushion := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(1.7, 0.42, 0.3)
	cushion.mesh = cb
	cushion.material_override = _mat(Color("5d3a2a"))
	cushion.position = SEAT + Vector3(0, 0.26, -0.55)
	add_child(cushion)


# --- drawing ---------------------------------------------------------------------------

## Feed the pointer every frame: held = trigger down, p = point on the diorama ground (model
## metres) or null when the ray misses it.
func pointer(held: bool, p) -> void:
	if _walking or _won:
		return
	if held and p != null:
		var q: Vector3 = p
		if not _drawing:
			if q.distance_to(cat.position) > START_RADIUS:
				return
			_drawing = true
			_ghost_on = false
			_ghost.visible = false
			_path = PackedVector3Array([cat.position])
			_sfx("tap", cat.position, -8.0)
		var last := _path[_path.size() - 1]
		if last.distance_to(q) >= POINT_STEP:
			_extend(last, q)
	elif _drawing and not held:
		_drawing = false
		if _path.size() >= 3:
			_walking = true
			_walk_i = 1
			CreatureSlot.play(cat, "walk")
		else:
			_clear_path()


## Adds q to the path unless the way there crosses a wall; near the gate, the line is led
## through the opening.
func _extend(a: Vector3, q: Vector3) -> void:
	if _blocked(q):
		if _gate_zone(q) or _gate_zone(a):
			_through_gate(a, q)
		else:
			_bump(q)
		return
	if _crosses(a, q):
		if _gate_zone(q) or _gate_zone(a) or _crosses_front_wall(a, q):
			_through_gate(a, q)
		else:
			_bump(q)
		return
	_path.append(q)
	_redraw()


func _through_gate(a: Vector3, q: Vector3) -> void:
	var inward := a.z > 6.25
	var pts := [GATE_OUT, GATE_IN] if inward else [GATE_IN, GATE_OUT]
	if (pts[0] as Vector3).distance_to(a) > 0.05 and not _crosses(a, pts[0]):
		_path.append(pts[0])
	elif _crosses(a, pts[0]):
		_bump(q)
		return
	_path.append(pts[1])
	if not _blocked(q) and not _crosses(pts[1], q):
		_path.append(q)
	_redraw()


func _gate_zone(p: Vector3) -> bool:
	return absf(p.x) < 2.2 and p.z > 4.6 and p.z < 7.8


func _crosses_front_wall(a: Vector3, b: Vector3) -> bool:
	return (a.z - 6.25) * (b.z - 6.25) < 0.0 and absf(lerpf(a.x, b.x, (6.25 - a.z) / (b.z - a.z))) < 2.2


## Off the paving (out on the sand) counts as blocked too.
func _on_paving(p: Vector3) -> bool:
	if COURT.has_point(Vector2(p.x, p.z)):
		return true
	var ex := (p.x - APRON[0]) / (APRON[2] - CAT_R)
	var ez := (p.z - APRON[1]) / (APRON[3] - CAT_R)
	return ex * ex + ez * ez <= 1.0


func _blocked(p: Vector3) -> bool:
	if not _on_paving(p):
		return true
	for r in BLOCKS:
		var g: Rect2 = (r as Rect2).grow(CAT_R)
		if g.has_point(Vector2(p.x, p.z)):
			return true
	return false


func _crosses(a: Vector3, b: Vector3) -> bool:
	var n := maxi(1, int(a.distance_to(b) / 0.1))
	for k in range(1, n + 1):
		if _blocked(a.lerp(b, float(k) / n)):
			return true
	return false


func _bump(at: Vector3) -> void:
	if _t - _bump_t > 0.4:
		_bump_t = _t
		_sfx("soft_reject", at, -12.0)


## Screenshot/test helper: draws the working path (as a hand would) and lets go.
func demo() -> void:
	var pts: Array = [cat.position]
	pts.append_array(SOLUTION)
	pts.append(HOME)
	var dense: Array = []
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var n := maxi(1, int(a.distance_to(b) / POINT_STEP))
		for k in n:
			dense.append(a.lerp(b, float(k) / n))
	dense.append(HOME)
	for q in dense:
		pointer(true, q)
	pointer(false, null)


# --- per frame -------------------------------------------------------------------------

func _process(dt: float) -> void:
	_t += dt
	var pulse := 1.0 + 0.1 * sin(_t * 4.0)
	_start_ring.position = cat.position + Vector3(0, 0.06, 0)
	_start_ring.scale = Vector3(pulse, 0.2, pulse)
	_start_ring.visible = not _walking and not _won
	_goal_ring.scale = Vector3(pulse, 0.2, pulse)
	_goal_ring.visible = not _won
	if not _walking and not _drawing and not _won:
		_idle_t += dt
		if _idle_t > 12.0:  # stuck for a while: show the hint again
			_ghost_on = true
	if _ghost_on and not _won:
		_ghost_t += dt
		var k := fmod(_ghost_t, 4.4) / 3.8
		_ghost.visible = k <= 1.0
		if k <= 1.0:
			_ghost.position = _along(_hint_path(), k) + Vector3(0, 0.3, 0)
	else:
		_ghost.visible = false
	if _walking:
		_step(dt)


func _hint_path() -> Array:
	var pts: Array = [cat.position]
	pts.append_array(SOLUTION)
	pts.append(HOME)
	return pts


static func _along(pts: Array, k: float) -> Vector3:
	var total := 0.0
	for i in pts.size() - 1:
		total += (pts[i] as Vector3).distance_to(pts[i + 1])
	var d := clampf(k, 0.0, 1.0) * total
	for i in pts.size() - 1:
		var seg: float = (pts[i] as Vector3).distance_to(pts[i + 1])
		if d <= seg:
			return (pts[i] as Vector3).lerp(pts[i + 1], d / maxf(seg, 0.0001))
		d -= seg
	return pts[pts.size() - 1]


func _step(dt: float) -> void:
	var remaining := WALK_SPEED * dt
	while remaining > 0.0 and _walk_i < _path.size():
		var target := _path[_walk_i]
		var to := target - cat.position
		var dist := to.length()
		if dist < 0.0001:
			_walk_i += 1
			continue
		var mv := minf(remaining, dist)
		cat.position += to / dist * mv
		_face(cat, to)
		remaining -= mv
		if mv >= dist:
			_walk_i += 1
		diorama.scare_birds(cat.position, 1.6)
		diorama.scare_hens(cat.position, 1.8)
		for t in thorns:
			if Vector2(cat.position.x, cat.position.z).distance_to(t.pos) < THORN_R:
				_hit_thorn(t)
				return
		if cat.position.distance_to(HOME) < HOME_RADIUS:
			_reach_home()
			return
	if _walk_i >= _path.size():  # the line ran out before reaching him
		_walking = false
		_clear_path()
		CreatureSlot.play(cat, "sit")
		_idle_t = 0.0


func _hit_thorn(t: Dictionary) -> void:
	_walking = false
	_idle_t = 0.0
	_sfx("soft_reject", cat.position)
	var away := Vector3(cat.position.x - t.pos.x, 0, cat.position.z - t.pos.y).normalized()
	create_tween().tween_property(cat, "position", cat.position + away * 0.9, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var n: Node3D = t.node
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3(1.2, 0.85, 1.2), 0.08)
	tw.tween_property(n, "scale", Vector3.ONE, 0.2)
	CreatureSlot.play(cat, "sit")
	_clear_path()


func _reach_home() -> void:
	_walking = false
	_won = true
	_clear_path()
	_sfx("success", HOME, -2.0)
	var tw := create_tween()
	tw.tween_property(cat, "position", HOME, 0.4)
	tw.tween_callback(func():
		_face(cat, SEAT - HOME)
		CreatureSlot.play(cat, "sit")
		diorama.play_shaib("sit_pet", ""))
	diorama.scare_birds(HOME, 6.0)
	get_tree().create_timer(4.5).timeout.connect(func():
		_sfx("level_complete", HOME)
		level_won.emit())


# --- visuals -----------------------------------------------------------------------------

func _clear_path() -> void:
	_path = PackedVector3Array()
	(_line.mesh as ImmediateMesh).clear_surfaces()


func _redraw() -> void:
	var im := _line.mesh as ImmediateMesh
	im.clear_surfaces()
	if _path.size() < 2:
		return
	var w := 0.22
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _path.size():
		var a := _path[maxi(i - 1, 0)]
		var b := _path[mini(i + 1, _path.size() - 1)]
		var d := b - a
		d.y = 0
		d = d.normalized() if d.length() > 0.0001 else Vector3.FORWARD
		var side := Vector3(-d.z, 0, d.x) * w
		im.surface_add_vertex(_path[i] + side + Vector3(0, 0.08, 0))
		im.surface_add_vertex(_path[i] - side + Vector3(0, 0.08, 0))
	im.surface_end()


static func _face(n: Node3D, d: Vector3) -> void:
	if Vector2(d.x, d.z).length() > 0.001:
		n.rotation.y = atan2(d.x, d.z)  # models face +Z


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m


static func _glow_mat(c: Color, alpha := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _ring(r: float, c: Color) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r * 0.84
	t.outer_radius = r
	t.rings = 32
	t.ring_segments = 4
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.material_override = _glow_mat(c, 0.9)
	add_child(mi)
	return mi


func _thorn_bush(at: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.position = at
	var stem := StandardMaterial3D.new()
	stem.albedo_color = Color("6b5a38")
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color("7d8a3c")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(at.x * 1000 + at.z * 37)
	var s := THORN_R / 0.4
	for i in 9:
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.05 * s
		c.height = rng.randf_range(0.35, 0.6) * s
		c.radial_segments = 4
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.material_override = stem if i % 3 else leaf
		var a := rng.randf() * TAU
		mi.position = Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.22) * s + Vector3(0, c.height * 0.45, 0)
		mi.rotation = Vector3(rng.randf_range(-0.7, 0.7), rng.randf() * TAU, rng.randf_range(-0.7, 0.7))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
	var dome := SphereMesh.new()
	dome.radius = 0.24 * s
	dome.height = 0.26 * s
	dome.radial_segments = 7
	dome.rings = 3
	var d := MeshInstance3D.new()
	d.mesh = dome
	d.material_override = leaf
	d.position.y = 0.1 * s
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(d)
	return n


func _sfx(name: String, at: Vector3, db := 0.0) -> void:
	var path := SFX + name + ".wav"
	if not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = load(path)
	p.volume_db = db
	add_child(p)
	p.position = at
	p.play()
	p.finished.connect(p.queue_free)
