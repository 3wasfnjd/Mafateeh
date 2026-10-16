class_name TablePathLevel
extends Node3D
## Level 1 on the table, «درب في الرمل» (a path in the sand). Wordless.
## The old man's cat is out on the sand beyond the gate; thorn bushes lie between it and home.
## Hold the trigger on the cat and draw a path in the sand to the gate; let go and the cat
## follows it. A thorn on the way sends it hopping back. At the gate it trots in to the old
## man, who cheers; the sparrows lift. Three rounds, more thorns each time; the last ends in
## the ardah.
##
## Lives under Diorama.model, so every position here is in the diorama's own metres
## (Godot axes, +Z = outside the gate).

signal round_won(round: int)
signal level_won

const SFX := "res://audio/sfx/"
const ROUNDS := 3
const GOAL := Vector3(0.03, 0.0, 7.0)      # just outside the gate opening
const SHAIB_AT := Vector3(-1.8, 0.0, 7.3)  # the old man waits just outside the gate
const HOME := Vector3(-0.95, 0.0, 7.35)    # where the cat settles beside him
const THORN_R := 0.75
const POINT_STEP := 0.3
const WALK_SPEED := 2.6
const START_RADIUS := 1.4                  # a path must begin this close to the cat
const GOAL_RADIUS := 0.9
# per round: cat start, thorn bushes (x, z)
# per round: cat start and thorn bushes (x, z). Everything stays on the flat sand in front of
# the gate (the dunes begin about 11.5 m from the centre).
const ROUND_DATA := [
	{"start": Vector3(3.0, 0, 10.6), "thorns": [Vector2(1.6, 9.0), Vector2(-0.8, 9.4)]},
	{"start": Vector3(-3.6, 0, 10.4), "thorns": [Vector2(-2.4, 9.6), Vector2(-1.5, 8.5), Vector2(0.3, 9.9),
		Vector2(1.6, 8.4)]},
	# two rows: get round the far row at either end, then through the gap in the near row
	{"start": Vector3(0.0, 0, 11.2), "thorns": [Vector2(-1.4, 10.0), Vector2(0.0, 10.0), Vector2(1.4, 10.0),
		Vector2(2.8, 10.0), Vector2(-3.2, 8.0), Vector2(-1.9, 8.0), Vector2(1.9, 8.0), Vector2(3.2, 8.0)]},
]
# a path that solves each round (screenshots and tests)
const SOLUTIONS := [
	[Vector3(2.8, 0, 8.4), Vector3(1.0, 0, 7.6)],
	[Vector3(-1.1, 0, 10.6), Vector3(-0.5, 0, 9.4), Vector3(0.0, 0, 8.0)],
	[Vector3(-2.6, 0, 11.0), Vector3(-2.6, 0, 9.0), Vector3(0.0, 0, 9.0)],
]

var diorama: Diorama
var round := 0
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


func setup(d: Diorama) -> void:
	diorama = d
	cat = CreatureSlot.spawn(self, "cat")
	cat.scale = Vector3.ONE * Diorama.LIFE_SCALE.cat
	_start_ring = _ring(1.0, Color("f1dcae"))
	_goal_ring = _ring(1.3, Color("e6b85a"))
	_goal_ring.position = GOAL + Vector3(0, 0.06, 0)
	_line = MeshInstance3D.new()
	_line.mesh = ImmediateMesh.new()
	_line.material_override = _glow_mat(Color("fff4dc"), 0.95)
	add_child(_line)
	_ghost = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.64
	_ghost.mesh = sm
	_ghost.material_override = _glow_mat(Color("fff4dc"), 0.85)
	add_child(_ghost)
	if diorama.shaib:  # the old man waits at the gate, looking out for his cat
		diorama.shaib.position = SHAIB_AT
		diorama.shaib.rotation.y = 0.0
		diorama.play_shaib("idle_look", "")
	_start_round(0)


# --- rounds ----------------------------------------------------------------------------

func _start_round(r: int) -> void:
	round = r
	_won = false
	_walking = false
	_clear_path()
	for t in thorns:
		t.node.queue_free()
	thorns.clear()
	var data: Dictionary = ROUND_DATA[r]
	var i := 0
	for p in data.thorns:
		var n := _thorn_bush(Vector3(p.x, 0, p.y))
		n.scale = Vector3.ONE * 0.01
		create_tween().tween_property(n, "scale", Vector3.ONE, 0.35).set_delay(0.1 * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		thorns.append({"node": n, "pos": p})
		i += 1
	cat.position = data.start
	_face(cat, GOAL - data.start)
	CreatureSlot.play(cat, "sit")
	_ghost_t = 0.0
	_idle_t = 0.0
	_ghost_on = r == 0
	if r > 0:
		_sfx("tap", data.start, -6.0)


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
		if _path[_path.size() - 1].distance_to(q) >= POINT_STEP:
			_path.append(q)
			_redraw()
	elif _drawing and not held:
		_drawing = false
		if _path.size() >= 3:
			_walking = true
			_walk_i = 1
			CreatureSlot.play(cat, "walk")
		else:
			_clear_path()


## Screenshot/test helper: draws a path that dodges this round's thorns and lets go.
func demo_round() -> void:
	var pts: Array = [cat.position]
	pts.append_array(SOLUTIONS[round])
	pts.append(GOAL)
	var dense: Array = []
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var n := maxi(1, int(a.distance_to(b) / POINT_STEP))
		for k in n:
			dense.append(a.lerp(b, float(k) / n))
	dense.append(GOAL)
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
		if _idle_t > 12.0:  # stuck for a while: show the hint
			_ghost_on = true
	if _ghost_on and not _won:
		# the hint: a light dot running along a path that works, from the cat to the gate
		_ghost_t += dt
		var k := fmod(_ghost_t, 3.6) / 3.0
		_ghost.visible = k <= 1.0
		if k <= 1.0:
			_ghost.position = _along(_hint_path(), k) + Vector3(0, 0.3, 0)
	else:
		_ghost.visible = false
	if _walking:
		_step(dt)


func _hint_path() -> Array:
	var pts: Array = [cat.position]
	pts.append_array(SOLUTIONS[round])
	pts.append(GOAL)
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
		for t in thorns:
			if Vector2(cat.position.x, cat.position.z).distance_to(t.pos) < THORN_R:
				_hit_thorn(t)
				return
		if cat.position.distance_to(GOAL) < GOAL_RADIUS:
			_reach_goal()
			return
	if _walk_i >= _path.size():  # the path ran out short of the gate
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
	diorama.play_shaib("think")
	_clear_path()


func _reach_goal() -> void:
	_walking = false
	_won = true
	_clear_path()
	_sfx("success", GOAL, -2.0)
	# home to the old man's feet
	CreatureSlot.play(cat, "walk")
	_face(cat, HOME - cat.position)
	var tw := create_tween()
	tw.tween_property(cat, "position", HOME, 0.8)
	tw.tween_callback(func():
		_face(cat, SHAIB_AT - HOME)
		CreatureSlot.play(cat, "sit"))
	diorama.scare_birds(GOAL, 8.0)
	diorama.play_shaib("excited" if round < ROUNDS - 1 else "ardah", "idle" if round < ROUNDS - 1 else "")
	round_won.emit(round)
	if round < ROUNDS - 1:
		var won_round := round
		get_tree().create_timer(3.6).timeout.connect(func():
			if round == won_round and _won:  # nothing else restarted the level meanwhile
				_start_round(won_round + 1))
	else:
		_sfx("level_complete", GOAL)
		get_tree().create_timer(1.0).timeout.connect(func(): level_won.emit())


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
