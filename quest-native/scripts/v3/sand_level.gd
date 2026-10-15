class_name SandLevel
extends Node3D
## Level 1 «درب في الرمل»: draw a path in the sand with the controller ray; the walker
## follows it to the door, and thorn bushes stop it. Wordless: a ghost line shows the
## idea, the walker and the door glow, sounds and the walker's reactions do the rest.
##   VR: life size inside the Diriyah courtyard; the player is the old man and the cat walks.
##   MR: the old man (with his cat behind him) walks across the room floor to a mud gate;
##       sparrows peck around and a villager strolls past.
## Three rounds per level; each round rearranges the thorns.

signal round_won(round: int)
signal level_won

const SHAIB := "res://assets/character/shaib.glb"
const VILLAGER := "res://assets/character/villager.glb"
const COURTYARD := "res://assets/world/courtyard.glb"
const GATE := "res://assets/world/door_arch.glb"
const PALM := "res://assets/world/palm.glb"
const SFX := "res://audio/sfx/"
const POINT_STEP := 0.12
const ROUNDS := 3
# Thorn layouts in a normalised frame: x in [-1, 1] across, z from +1 (start) to -1 (door).
const LAYOUTS := [
	[Vector2(0.05, 0.05)],
	[Vector2(-0.95, 0.0), Vector2(-0.62, 0.0), Vector2(-0.3, 0.0), Vector2(0.02, 0.0), Vector2(0.34, 0.0), Vector2(0.7, -0.55)],
	[Vector2(-0.25, 0.4), Vector2(0.1, 0.4), Vector2(0.45, 0.4), Vector2(0.8, 0.4), Vector2(1.0, 0.4),
		Vector2(-1.0, -0.3), Vector2(-0.7, -0.3), Vector2(-0.4, -0.3), Vector2(-0.08, -0.3), Vector2(0.25, -0.3)],
]

var mode := "vr"
var round := 0
var origin := Vector3.ZERO     # frame centre on the floor
var span := Vector2(3.0, 3.6)  # frame half-size (x across, z deep) in metres
var thorn_r := 0.38
var walker: Node3D             # the one who follows the path
var walker_anim: AnimationPlayer
var follower: Node3D           # MR: the cat trailing the old man
var door: Node3D
var door_closed_y := 0.0
var goal := Vector3.ZERO
var start := Vector3.ZERO
var thorns: Array = []         # {node, pos}
var vents: Array = []          # MeshInstance3D near the door, lit on success
var birds: Array = []
var villager: Node3D
var _villager_t := 0.0

var _path: PackedVector3Array = PackedVector3Array()
var _drawing := false
var _walking := false
var _walk_i := 0
var _walk_speed := 1.2
var _line: MeshInstance3D
var _line_mat: StandardMaterial3D
var _ghost: MeshInstance3D
var _ghost_t := 0.0
var _ghost_on := true
var _start_ring: MeshInstance3D
var _goal_ring: MeshInstance3D
var _t := 0.0
var _won := false


func setup(m: String, anchor: Transform3D) -> void:
	mode = m
	if mode == "vr":
		var yard: Node3D = (load(COURTYARD) as PackedScene).instantiate()
		add_child(yard)
		door = yard.find_child("DoorMain", true, false)
		origin = Vector3(-0.6, 0, -0.4)
		span = Vector2(3.2, 3.6)
		thorn_r = 0.4
		goal = Vector3(-1.0, 0, -3.75)
		start = Vector3(0.6, 0, 3.4)
		for mi in yard.find_children("vent*", "MeshInstance3D", true, false):
			if (mi as Node3D).global_position.z > -5.2 and absf((mi as Node3D).global_position.x + 1.0) < 2.2:
				vents.append(mi)
		walker = CreatureSlot.spawn(self, "cat")
		walker.scale = Vector3.ONE * 1.25
		_walk_speed = 1.3
	else:
		global_transform = anchor
		origin = Vector3(0, 0, -1.55)
		span = Vector2(1.25, 1.35)
		thorn_r = 0.2
		goal = Vector3(0, 0, -3.0)
		start = Vector3(0.2, 0, -0.25)
		var gate: Node3D = (load(GATE) as PackedScene).instantiate()
		add_child(gate)
		gate.position = Vector3(0, 0, -3.35)
		door = gate.find_child("DoorMain", true, false)
		for mi in gate.find_children("vent*", "MeshInstance3D", true, false):
			vents.append(mi)
		for p in [Vector3(-1.7, 0, -3.4), Vector3(1.8, 0, -3.1)]:
			var palm: Node3D = (load(PALM) as PackedScene).instantiate()
			add_child(palm)
			palm.position = p
			palm.scale = Vector3.ONE * 0.75
		walker = (load(SHAIB) as PackedScene).instantiate()
		add_child(walker)
		walker.scale = Vector3.ONE * 1.38
		for mi in walker.find_children("*", "MeshInstance3D", true, false):
			if String(mi.name).begins_with(("Bisht")) or String(mi.name).begins_with("Glasses") or String(mi.name).begins_with("Misbaha") or String(mi.name).begins_with("CaneArm"):
				mi.visible = false
		walker_anim = _anim(walker)
		_loop(walker_anim, ["idle", "walk", "ardah", "think"])
		_walk_speed = 0.75
		follower = CreatureSlot.spawn(self, "cat")
		villager = (load(VILLAGER) as PackedScene).instantiate()
		add_child(villager)
		villager.scale = Vector3.ONE * 1.3
		var va := _anim(villager)
		_loop(va, ["walk", "ardah", "idle"])
		if va and va.has_animation("walk"):
			va.play("walk")
	if door:
		door_closed_y = door.rotation.y
	_spawn_birds()
	_build_markers()
	_start_round(0)


static func _anim(n: Node) -> AnimationPlayer:
	var a: Array = n.find_children("*", "AnimationPlayer", true, false)
	return a[0] if not a.is_empty() else null


static func _loop(ap: AnimationPlayer, clips: Array) -> void:
	if ap == null:
		return
	for c in clips:
		if ap.has_animation(c):
			ap.get_animation(c).loop_mode = Animation.LOOP_LINEAR


func _frame(p: Vector2) -> Vector3:
	return origin + Vector3(p.x * span.x, 0, -p.y * span.y)


# --- visuals -------------------------------------------------------------------------

static func _glow_mat(c: Color, alpha := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _ring(r: float, c: Color) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r * 0.86
	t.outer_radius = r
	t.rings = 32
	t.ring_segments = 4
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.material_override = _glow_mat(c, 0.85)
	mi.scale = Vector3(1, 0.15, 1)
	add_child(mi)
	return mi


func _build_markers() -> void:
	var s := 1.0 if mode == "vr" else 0.6
	_start_ring = _ring(0.5 * s, Color("f3d68a"))
	_goal_ring = _ring(0.75 * s, Color("8fd18b"))
	_goal_ring.position = goal + Vector3(0, 0.02, 0.4 * s)
	_line = MeshInstance3D.new()
	_line.mesh = ImmediateMesh.new()
	_line_mat = _glow_mat(Color("fff3d6"), 0.95)
	_line.material_override = _line_mat
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)
	_ghost = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06 * (1.0 if mode == "vr" else 0.7)
	sm.height = sm.radius * 2
	_ghost.mesh = sm
	_ghost.material_override = _glow_mat(Color("fff3d6"), 0.8)
	add_child(_ghost)


func _thorn_bush(at: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.position = at
	var stem := StandardMaterial3D.new()
	stem.albedo_color = Color("6b5a38")
	stem.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color("7d8a3c")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(at.x * 1000 + at.z * 37)
	var s := thorn_r / 0.4
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
	n.add_child(d)
	return n


func _spawn_birds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in (5 if mode == "vr" else 3):
		var b := CreatureSlot.spawn(self, "sparrow")
		if b == null:
			return
		var p := _frame(Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-0.2, 1.1)))
		b.position = p
		b.rotation.y = rng.randf() * TAU
		CreatureSlot.play(b, "peck", 0.0, rng.randf() * 2.0)
		birds.append({"node": b, "home": p, "t": 0.0, "fly": false})


# --- rounds ----------------------------------------------------------------------------

func _start_round(r: int) -> void:
	round = r
	_won = false
	for t in thorns:
		t.node.queue_free()
	thorns.clear()
	for p in LAYOUTS[r]:
		var at := _frame(p)
		var n := _thorn_bush(at)
		n.scale = Vector3.ONE * 0.01
		create_tween().tween_property(n, "scale", Vector3.ONE, 0.35).set_delay(0.08 * thorns.size()).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		thorns.append({"node": n, "pos": at})
	walker.position = start
	walker.rotation.y = PI
	if follower:
		follower.position = start + Vector3(0.45, 0, 0.35)
		follower.rotation.y = PI
	_idle()
	_close_door()
	_clear_path()
	_ghost_on = r == 0
	_ghost_t = 0.0
	for v in vents:
		(v as MeshInstance3D).material_override = null


func _idle() -> void:
	if walker_anim:
		walker_anim.play("idle", 0.2)
	else:
		CreatureSlot.play(walker, "sit")
	if follower:
		CreatureSlot.play(follower, "sit")


func _close_door() -> void:
	if door:
		door.rotation.y = door_closed_y


# --- input (called by the scene with a world-space ray, every frame while held) --------

## Feeds the pointer: `held` while the trigger is down, `hit` = floor point or null.
func pointer(held: bool, hit) -> void:
	if _walking or _won:
		return
	if held and hit != null:
		var p: Vector3 = to_local(hit)
		p.y = 0.0
		if not _drawing:
			# a path always starts at the walker
			if p.distance_to(walker.position) > (1.0 if mode == "vr" else 0.6):
				return
			_drawing = true
			_ghost_on = false
			_ghost.visible = false
			_path = PackedVector3Array([walker.position])
			_sfx("tap", walker.position, -8.0)
		if _path[_path.size() - 1].distance_to(p) >= POINT_STEP:
			_path.append(p)
			_redraw()
	elif _drawing and not held:
		_drawing = false
		if _path.size() >= 3:
			_walking = true
			_walk_i = 1
			if walker_anim:
				walker_anim.play("walk", 0.2)
			else:
				CreatureSlot.play(walker, "walk")
			if follower:
				CreatureSlot.play(follower, "walk")
		else:
			_clear_path()


func _clear_path() -> void:
	_path = PackedVector3Array()
	(_line.mesh as ImmediateMesh).clear_surfaces()


func _redraw() -> void:
	var im := _line.mesh as ImmediateMesh
	im.clear_surfaces()
	if _path.size() < 2:
		return
	var w := 0.07 if mode == "vr" else 0.05
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _path.size():
		var a := _path[maxi(i - 1, 0)]
		var b := _path[mini(i + 1, _path.size() - 1)]
		var d := (b - a)
		d.y = 0
		d = d.normalized() if d.length() > 0.0001 else Vector3.FORWARD
		var side := Vector3(-d.z, 0, d.x) * w
		im.surface_add_vertex(_path[i] + side + Vector3(0, 0.015, 0))
		im.surface_add_vertex(_path[i] - side + Vector3(0, 0.015, 0))
	im.surface_end()


# --- per frame ---------------------------------------------------------------------------

func _process(dt: float) -> void:
	_t += dt
	var pulse := 1.0 + 0.08 * sin(_t * 4.0)
	_start_ring.position = walker.position + Vector3(0, 0.02, 0)
	_start_ring.scale = Vector3(pulse, 0.15, pulse)
	_start_ring.visible = not _walking and not _won
	_goal_ring.scale = Vector3(pulse, 0.15, pulse)
	if _ghost_on:
		_ghost_t += dt
		var k := fmod(_ghost_t, 3.2) / 2.6
		_ghost.visible = k <= 1.0
		if k <= 1.0:
			var a := walker.position
			var mid := _frame(Vector2(0.75, 0.0)) if round == 0 else _frame(Vector2(0.8, 0.0))
			var p := a.lerp(mid, k).lerp(mid.lerp(goal + Vector3(0, 0, 0.6), k), k)
			_ghost.position = p + Vector3(0, 0.05, 0)
	if _walking:
		_step(dt)
	if follower and _walking:
		var target := walker.position + walker.global_basis.z * 0.5
		follower.position = follower.position.lerp(target, clampf(dt * 2.5, 0, 1))
		var d := walker.position - follower.position
		if Vector2(d.x, d.z).length() > 0.05:
			follower.rotation.y = atan2(d.x, d.z)
	_update_birds(dt)
	_update_villager(dt)


func _step(dt: float) -> void:
	var remaining := _walk_speed * dt
	while remaining > 0.0 and _walk_i < _path.size():
		var target := _path[_walk_i]
		var to := target - walker.position
		var dist := to.length()
		if dist < 0.0001:
			_walk_i += 1
			continue
		var mv := minf(remaining, dist)
		walker.position += to / dist * mv
		walker.rotation.y = atan2(to.x, to.z)
		remaining -= mv
		if mv >= dist:
			_walk_i += 1
		for t in thorns:
			if Vector2(walker.position.x - t.pos.x, walker.position.z - t.pos.z).length() < thorn_r:
				_hit_thorn(t)
				return
		if walker.position.distance_to(goal) < (0.9 if mode == "vr" else 0.55):
			_reach_goal()
			return
	if _walk_i >= _path.size():
		_walking = false
		_clear_path()
		_idle()


func _hit_thorn(t: Dictionary) -> void:
	_walking = false
	_sfx("soft_reject", walker.position)
	var back: Vector3 = walker.position + (walker.position - t.pos).normalized() * 0.35
	back.y = 0
	create_tween().tween_property(walker, "position", back, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var n: Node3D = t.node
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3(1.15, 0.9, 1.15), 0.08)
	tw.tween_property(n, "scale", Vector3.ONE, 0.2)
	if walker_anim and walker_anim.has_animation("reject"):
		walker_anim.play("reject", 0.1)
		walker_anim.queue("idle")
	else:
		CreatureSlot.play(walker, "sit")
	_clear_path()


func _reach_goal() -> void:
	_walking = false
	_won = true
	_clear_path()
	_sfx("door_creak", goal)
	_sfx("success", goal, -2.0)
	if door:
		create_tween().tween_property(door, "rotation:y", door_closed_y - deg_to_rad(100.0), 1.1).set_trans(Tween.TRANS_SINE)
	var gold := _glow_mat(Color("f3c95a"), 1.0)
	var i := 0
	for v in vents:
		var mi: MeshInstance3D = v
		get_tree().create_timer(0.08 * i).timeout.connect(func(): mi.material_override = gold)
		i += 1
	if walker_anim:
		walker_anim.play("excited" if round < ROUNDS - 1 else "ardah", 0.2)
	else:
		CreatureSlot.play(walker, "sit")
	for b in birds:
		_fly(b)
	if villager and round == ROUNDS - 1:
		var va := _anim(villager)
		if va and va.has_animation("ardah"):
			va.play("ardah", 0.3)
	round_won.emit(round)
	if round < ROUNDS - 1:
		get_tree().create_timer(3.2).timeout.connect(func(): _start_round(round + 1))
	else:
		_sfx("level_complete", goal)
		level_won.emit()


# --- life --------------------------------------------------------------------------------

func _fly(b: Dictionary) -> void:
	if b.fly:
		return
	b.fly = true
	b.t = 0.0
	CreatureSlot.play(b.node, "fly", 0.1)
	if randf() < 0.5:
		_sfx("bird_%d" % (randi() % 4 + 1), b.node.position, -10.0)


func _update_birds(dt: float) -> void:
	for b in birds:
		var n: Node3D = b.node
		b.t += dt
		if b.fly:
			var k: float = clampf(b.t / 2.5, 0.0, 1.0)
			n.position = b.home + Vector3(sin(b.t * 1.3) * 1.2, sin(k * PI) * (4.0 if mode == "vr" else 1.6), cos(b.t * 1.3) * 1.2 - 1.2) * k * (1.0 - k) * 4.0
			if b.t > 2.5:
				b.fly = false
				b.t = 0.0
				n.position = b.home
				CreatureSlot.play(n, "peck", 0.2)
		elif Vector2(n.position.x - walker.position.x, n.position.z - walker.position.z).length() < (0.9 if mode == "vr" else 0.5):
			_fly(b)


func _update_villager(dt: float) -> void:
	if villager == null:
		return
	if _won and round == ROUNDS - 1:
		return
	_villager_t += dt * 0.16
	var r := 3.6
	var a := _villager_t
	villager.position = Vector3(cos(a) * r, 0, -1.6 + sin(a) * r)
	villager.rotation.y = atan2(-sin(a), cos(a)) + PI


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
