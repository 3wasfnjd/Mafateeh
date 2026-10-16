class_name TableFalconLevel
extends Node3D
## Level 3 on the table, «مفتاح الشاهين» (the falcon's key). Wordless. The falcon is the hero.
## Scene 3: a walled palm garden with an arish. The old man sits at the front of the arish
## with his falcon on his glove. Outside the wall, out on the sand, lies a key. The falcon
## flies only from perch to perch (wooden posts, two tall ones by the wall), and only as far as the
## ring on the ground round it shows. Tap a perch inside the ring and it flies there; tap the
## key when it is in reach and it swoops down and takes it. Carrying the key its ring is
## smaller, so the way back is not always the way out. Bring the key to the old man's glove.
##
## Lives under Diorama.stage: positions are in the diorama's own metres (Godot axes).

signal level_won

const SFX := "res://audio/sfx/"
const SEAT := Vector3(0.0, 0.0, -2.0)         # the old man (scene 3 layout), facing the gate
const GLOVE := Vector3(-0.32, 1.02, -1.75)    # his raised right hand
# perches: id -> [x, z, base height, post height]
const PERCHES := {
	"a": [3.0, -0.5, 0.0, 2.4],    # in the garden, right of the arish
	"b": [4.9, -4.6, 0.0, 2.4],    # in the garden, back right
	"h": [5.1, -0.4, 0.0, 3.6],    # a tall perch inside the right wall, over its top
	"e": [8.8, -1.6, 0.0, 2.6],    # outside, right
	"d": [9.2, -8.2, 0.0, 2.6],    # outside, far back right (a dead end)
	"l1": [-3.0, -0.8, 0.0, 2.4],  # in the garden, left
	"l2": [-5.1, -3.2, 0.0, 3.6],  # a tall perch inside the left wall
	"l3": [-9.0, -4.0, 0.0, 2.6],  # outside, left (nothing out there)
}
const KEY_AT := Vector3(10.2, 0.0, -4.6)      # on a stone out on the sand
const KEY_LEN := 0.8
const RANGE := 5.0          # how far one flight reaches
const RANGE_LOADED := 4.2   # carrying the key
const FLY_SPEED := 5.0
const PICK_R := 1.0
const HINT_AFTER := 20.0
const BEIGE := Color("f1dcae")
const GOLD := Color("e6b85a")

var diorama: Diorama
var falcon: Node3D
var key: Node3D
var at := "man"            # where the falcon is: "man", a perch id, or "key"
var loaded := false
var _flying := false
var _won := false
var _was_held := false
var _ray := []
var _range_ring: MeshInstance3D
var _marks := {}           # perch id / "key" / "man" -> small ring over it
var _posts := {}           # perch id -> Node3D
var _idle_t := 0.0
var _t := 0.0
var _demo: Array = []


func setup(d: Diorama) -> void:
	diorama = d
	TablePathLevel.add_mat(self, SEAT)
	if diorama.shaib:
		diorama.shaib.position = SEAT
		diorama.shaib.rotation.y = 0.0
		diorama.play_shaib("sit_idle", "")
	for id in PERCHES:
		_posts[id] = _post(id)
	key = _key()
	falcon = CreatureSlot.spawn(self, "falcon")
	falcon.scale = Vector3.ONE * Diorama.LIFE_SCALE.falcon
	falcon.position = GLOVE
	CreatureSlot.play(falcon, "perch")
	_range_ring = _ring(1.0, BEIGE, 0.55)
	for id in PERCHES.keys() + ["key", "man"]:
		_marks[id] = _ring(0.35, GOLD, 0.9)
	_refresh()


# --- places ------------------------------------------------------------------------------

## Where the falcon stands at a place (top of the post, the stone, the glove).
func spot(id: String) -> Vector3:
	if id == "man":
		return GLOVE
	if id == "key":
		return KEY_AT + Vector3(0, 0.3, 0)
	var p: Array = PERCHES[id]
	return Vector3(p[0], p[2] + p[3] + 0.06, p[1])


func reach(from: String, to: String, with_key: bool) -> bool:
	var a := spot(from)
	var b := spot(to)
	return Vector2(a.x - b.x, a.z - b.z).length() <= (RANGE_LOADED if with_key else RANGE)


## The places the falcon may fly to from here.
func _targets() -> Array:
	var out: Array = []
	for id in PERCHES.keys() + ["key", "man"]:
		if id == at or (id == "key" and loaded):
			continue
		if reach(at, id, loaded):
			out.append(id)
	return out


## First hop of the shortest way to the goal (the key, or the glove once it carries it).
func _next_hop() -> String:
	var goal := "man" if loaded else "key"
	var prev := {at: ""}
	var queue: Array = [at]
	var ids: Array = PERCHES.keys() + ["key", "man"]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == goal:
			break
		for id in ids:
			if prev.has(id) or (id == "key" and loaded):
				continue
			if reach(cur, id, loaded):
				prev[id] = cur
				queue.append(id)
	if not prev.has(goal):
		return ""
	var step := goal
	while prev[step] != at:
		step = prev[step]
	return step


# --- input -----------------------------------------------------------------------------------

func aim(origin: Vector3, dir: Vector3) -> void:
	_ray = [origin, dir]


func pointer(held: bool, p) -> void:
	var pressed := held and not _was_held
	_was_held = held
	if not pressed or _flying or _won:
		return
	var id := _pick(p)
	if id == "" or id == at:
		return
	_idle_t = 0.0
	if id == "key" and loaded:
		return
	if not reach(at, id, loaded):
		_refuse(id)
		return
	_fly(id)


func _pick(p) -> String:
	var ids: Array = PERCHES.keys() + ["key", "man"]
	if _ray.size() == 2:
		var o := to_local(_ray[0])
		var d := to_local(_ray[0] + _ray[1]) - o
		var best := ""
		var best_t := INF
		for id in ids:
			var s := spot(id)
			var box := AABB(Vector3(s.x - 0.45, 0.0, s.z - 0.45), Vector3(0.9, s.y + 0.5, 0.9))
			if id == "man":
				box = AABB(SEAT - Vector3(0.6, 0, 0.6), Vector3(1.2, 1.6, 1.2))
			var hit = box.intersects_ray(o, d)
			if hit != null and o.distance_to(hit) < best_t:
				best_t = o.distance_to(hit)
				best = id
		if best != "":
			return best
	if p == null:
		return ""
	var q: Vector3 = p
	var best2 := ""
	var best_d := PICK_R
	for id in ids:
		var s := SEAT if id == "man" else spot(id)
		var dd := Vector2(s.x - q.x, s.z - q.z).length()
		if dd < best_d:
			best_d = dd
			best2 = id
	return best2


# --- flight ----------------------------------------------------------------------------------

func _fly(id: String) -> void:
	_flying = true
	_set_marks(false)
	var a := falcon.position
	var b := spot(id)
	var top := maxf(a.y, b.y) + 1.4
	if id == "key":
		top = a.y + 0.6   # a swoop down onto it
	var dist := Vector2(a.x - b.x, a.z - b.z).length()
	var dur := maxf(0.7, dist / FLY_SPEED + 0.3)
	_face(falcon, b - a)
	CreatureSlot.play(falcon, "fly")
	_sfx("cloth_%d" % (randi() % 4 + 1), a, -6.0)
	if at == "man":
		diorama.play_shaib("sit_idle", "")
	var tw := create_tween()
	tw.tween_method(func(k: float):
		var e := smoothstep(0.0, 1.0, k)
		var pos := a.lerp(b, e)
		pos.y = lerpf(a.y, b.y, e) + (top - maxf(a.y, b.y)) * sin(e * PI) * (1.0 if id != "key" else 0.6)
		falcon.position = pos
		if loaded:
			key.position = pos + Vector3(0, -0.2, 0), 0.0, 1.0, dur)
	tw.tween_callback(func(): _land(id))


func _land(id: String) -> void:
	at = id
	_flying = false
	CreatureSlot.play(falcon, "perch")
	_face(falcon, Vector3(0, 0, 1) if id == "man" else SEAT - falcon.position)
	_sfx("tap", falcon.position, -10.0)
	if id == "key" and not loaded:
		loaded = true
		_sfx("key_pickup", KEY_AT, -2.0)
		key.position = falcon.position + Vector3(0, -0.2, 0)
	if id == "man" and loaded:
		_win()
		return
	_refresh()


## Out of reach: it rises off the perch, beats its wings and settles back.
func _refuse(id: String) -> void:
	_flying = true
	_sfx("soft_reject", spot(id), -6.0)
	var home := falcon.position
	_face(falcon, spot(id) - home)
	CreatureSlot.play(falcon, "fly")
	var tw := create_tween()
	tw.tween_property(falcon, "position", home + Vector3(0, 0.35, 0), 0.25)
	tw.tween_property(falcon, "position", home, 0.3)
	tw.tween_callback(func():
		CreatureSlot.play(falcon, "perch")
		_flying = false)
	var ring := _range_ring
	var t2 := create_tween()
	t2.tween_property(ring, "scale", ring.scale * 1.08, 0.12)
	t2.tween_property(ring, "scale", ring.scale, 0.2)


func _win() -> void:
	_won = true
	_set_marks(false)
	_range_ring.visible = false
	_sfx("success", GLOVE, -2.0)
	# the key goes to his hand; he strokes the falcon
	var tw := create_tween()
	tw.tween_property(key, "position", SEAT + Vector3(0.25, 0.75, 0.35), 0.5)
	tw.tween_callback(func():
		diorama.play_shaib("sit_pet", "")
		diorama.scare_birds(SEAT, 4.0))
	tw.tween_interval(4.0)
	tw.tween_callback(func():
		_sfx("level_complete", SEAT)
		level_won.emit())


# --- rings and hints -------------------------------------------------------------------------

func _refresh() -> void:
	var r := RANGE_LOADED if loaded else RANGE
	var s := spot(at)
	_range_ring.position = Vector3(s.x, 0.05, s.z)
	create_tween().tween_property(_range_ring, "scale", Vector3(r, 1.0, r), 0.35)
	_range_ring.visible = true
	_set_marks(true)


func _set_marks(on: bool) -> void:
	var t := _targets() if on else []
	for id in _marks:
		var m: MeshInstance3D = _marks[id]
		m.visible = id in t
		var s := (SEAT + Vector3(0, 1.75, 0)) if id == "man" else spot(id) + Vector3(0, 0.12, 0)
		m.position = s


## Screenshot/test helper: flies the way out and back.
func demo() -> void:
	_demo = ["a", "h", "e", "key", "e", "h", "a", "man"]


func _process(dt: float) -> void:
	_t += dt
	if _won:
		return
	if not _flying and not _demo.is_empty():
		var id: String = _demo.pop_front()
		if reach(at, id, loaded):
			_fly(id)
	_idle_t += dt
	var hint := _next_hop() if _idle_t > HINT_AFTER and not _flying else ""
	for id in _marks:
		var m: MeshInstance3D = _marks[id]
		if not m.visible:
			continue
		var pulse := 1.0 + (0.35 if id == hint else 0.1) * sin(_t * (6.0 if id == hint else 3.0))
		m.scale = Vector3(pulse, 0.3, pulse)


# --- props -----------------------------------------------------------------------------------

## A falconer's perch: a wooden post with a padded cross-bar on top.
func _post(id: String) -> Node3D:
	var p: Array = PERCHES[id]
	var n := Node3D.new()
	add_child(n)
	n.position = Vector3(p[0], p[2], p[1])
	var wood := _mat(Color("7a5634"))
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.08
	pole.height = p[3]
	pole.radial_segments = 8
	_mesh(n, pole, wood, Vector3(0, p[3] / 2, 0))
	var bar := BoxMesh.new()
	bar.size = Vector3(0.6, 0.08, 0.1)
	_mesh(n, bar, _mat(Color("8e3b2e")), Vector3(0, p[3], 0))  # the padded bar, in red cloth
	if p[2] == 0.0:
		var foot := CylinderMesh.new()
		foot.top_radius = 0.16
		foot.bottom_radius = 0.22
		foot.height = 0.14
		foot.radial_segments = 8
		_mesh(n, foot, _mat(Color("b99167")), Vector3(0, 0.07, 0))
	return n


## The key on its stone (the old game's key model when the kit has it).
func _key() -> Node3D:
	var stone := SphereMesh.new()
	stone.radius = 0.45
	stone.height = 0.5
	stone.radial_segments = 8
	stone.rings = 4
	var s := Node3D.new()
	add_child(s)
	s.position = KEY_AT
	_mesh(s, stone, _mat(Color("a98a6a")), Vector3(0, 0.08, 0))
	var k := Node3D.new()
	add_child(k)
	k.position = KEY_AT + Vector3(0, 0.34, 0)
	var mesh := Kit.piece("key")
	if mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		k.add_child(mi)
		var size := mesh.get_aabb().size
		mi.scale = Vector3.ONE * (KEY_LEN / maxf(0.001, maxf(size.x, maxf(size.y, size.z))))
		mi.position = -mesh.get_aabb().get_center() * mi.scale
	else:
		var gold := _mat(GOLD)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.1
		ring.outer_radius = 0.17
		_mesh(k, ring, gold, Vector3(-0.3, 0, 0), Vector3(PI / 2, 0, 0))
		var shaft := BoxMesh.new()
		shaft.size = Vector3(0.5, 0.06, 0.06)
		_mesh(k, shaft, gold, Vector3(0.08, 0, 0))
		var bit := BoxMesh.new()
		bit.size = Vector3(0.06, 0.06, 0.16)
		_mesh(k, bit, gold, Vector3(0.28, 0, 0.08))
	return k


func _mesh(parent: Node3D, m: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _face(n: Node3D, d: Vector3) -> void:
	if n and Vector2(d.x, d.z).length() > 0.001:
		n.rotation.y = atan2(d.x, d.z)


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m


func _ring(r: float, c: Color, alpha: float) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r * 0.93
	t.outer_radius = r
	t.rings = 48
	t.ring_segments = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _sfx(name: String, pos: Vector3, db := 0.0) -> void:
	TableKit.sfx(self, name, pos, db)
