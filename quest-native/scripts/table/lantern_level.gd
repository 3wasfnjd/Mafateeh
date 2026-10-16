class_name TableLanternLevel
extends Node3D
## Level 5 on the table, «سُرج الضيف» (the guests' lamps). Wordless. Evening.
## Scene 5: the guest majlis, its fire pit in a round forecourt, eight lanterns on posts round
## the fire. Guests are on their way and the old man must light the place for them. Tap a
## lantern and it changes, lit or dark, and so do the two lanterns beside it. Light all eight
## and the fire takes, the guests walk in and sit, and he pours their coffee.
## (Lights-out on a ring of eight: every start has exactly one set of lanterns to tap.)
##
## Lives under Diorama.stage: positions are in the diorama's own metres (Godot axes).

signal level_won

const FIRE := Vector3(0.0, 0.0, 2.4)          # tools/blender/build_scene5.py: FIRE
const RING_R := 3.3
const N := 8
const POST_H := 1.7
const LANTERN := "res://assets/world/props/lantern.glb"
const START_LIT := [4]                        # the one lamp still burning; tap 0, 3 and 5
const HOST := Vector3(1.0, 0.0, 1.2)
const DAKKA_Y := 0.45
const SEATS := [Vector3(-3.6, 0, -4.5), Vector3(0.0, 0, -4.7), Vector3(3.6, 0, -4.5)]
const GUESTS := [{"head": "ghutra", "thobe": "thobe_grey", "bisht": "bisht"},
	{"head": "ghutra", "agal": "agal_gold", "glasses": "glasses"},
	{"thobe": "thobe_beige", "misbaha": "misbaha"}]
const HINT_AFTER := 20.0
const FLAME := Color("ffc46b")

var diorama: Diorama
var lit: Array = []          # bool per lantern
var _flames: Array = []      # {flame, halo, pool}
var _boxes := {}
var _fire: Node3D
var _was_held := false
var _ray := []
var _busy := false
var _won := false
var _idle_t := 0.0
var _t := 0.0
var _hint := -1
var _hint_ring: MeshInstance3D
var _demo: Array = []


func setup(d: Diorama) -> void:
	diorama = d
	if diorama.shaib:
		diorama.shaib.position = HOST
		TableKit.face(diorama.shaib, FIRE - HOST)
		diorama.play_shaib("idle", "")
	for i in N:
		lit.append(i in START_LIT)
		_lantern(i)
	_fire = _fire_flames()
	_fire.visible = false
	_hint_ring = TableKit.ring(self, 0.5, Color("e6b85a"), 0.9)
	_hint_ring.visible = false
	_show()


func spot(i: int) -> Vector3:
	var a := TAU * i / N - PI / 2   # lantern 0 is on the far side of the fire, then round
	return FIRE + Vector3(cos(a), 0, sin(a)) * RING_R


func _lantern(i: int) -> void:
	var at := spot(i)
	var wood := TableKit.mat(Color("6e4a2c"))
	TableKit.cyl(self, 0.05, 0.07, POST_H, wood, at + Vector3(0, POST_H / 2, 0), 8)
	TableKit.box(self, Vector3(0.36, 0.05, 0.08), wood, at + Vector3(0, POST_H - 0.05, 0))
	var lamp := TableKit.model(self, LANTERN, at + Vector3(0, POST_H - 0.03, 0), 0.0, 0.9)
	if lamp == null:
		TableKit.box(self, Vector3(0.3, 0.45, 0.3), TableKit.mat(Color("4a3a2a")), at + Vector3(0, POST_H + 0.22, 0))
	var flame := TableKit.sphere(self, 0.09, TableKit.lit_mat(FLAME, 2.2), at + Vector3(0, POST_H + 0.25, 0), 8)
	var halo := MeshInstance3D.new()   # a soft glow round the lamp, always facing the eye
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	halo.mesh = q
	var hm := TableKit.glow_mat(FLAME, 0.8)
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.billboard_keep_scale = true   # (else it is drawn at world size, huge on the table)
	hm.albedo_texture = _radial()
	halo.material_override = hm
	halo.position = at + Vector3(0, POST_H + 0.25, 0)
	add_child(halo)
	var pool := MeshInstance3D.new()   # warm light on the ground under it
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.8, 1.8)
	pool.mesh = pm
	var plm := TableKit.glow_mat(FLAME, 0.32)
	plm.albedo_texture = _radial()
	pool.material_override = plm
	pool.position = at + Vector3(0, 0.04, 0)
	add_child(pool)
	_flames.append({"flame": flame, "halo": halo, "pool": pool})
	_boxes[str(i)] = AABB(at - Vector3(0.4, 0, 0.4), Vector3(0.8, POST_H + 0.8, 0.8))


var _radial_tex: Texture2D
func _radial() -> Texture2D:
	if _radial_tex:
		return _radial_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	_radial_tex = t
	return t


func _fire_flames() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.position = FIRE
	for i in 5:
		var a := TAU * i / 5
		var c := TableKit.cyl(n, 0.0, 0.16, 0.7, TableKit.lit_mat(Color("ff9a3c") if i % 2 else Color("ffd27a"), 2.5),
			Vector3(cos(a) * 0.18, 0.35, sin(a) * 0.18), 6)
		c.rotation = Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2))
	var wood := TableKit.mat(Color("3a2a1c"))
	for i in 3:
		TableKit.box(n, Vector3(0.9, 0.1, 0.1), wood, Vector3(0, 0.06, 0), Vector3(0, TAU * i / 6, 0))
	return n


func _show() -> void:
	for i in N:
		var f: Dictionary = _flames[i]
		for key in ["flame", "halo", "pool"]:
			(f[key] as Node3D).visible = lit[i]


# --- input -----------------------------------------------------------------------------------

func aim(origin: Vector3, dir: Vector3) -> void:
	_ray = [origin, dir]


func pointer(held: bool, p) -> void:
	var pressed := held and not _was_held
	_was_held = held
	if not pressed or _busy or _won:
		return
	var id := TableKit.ray_pick(self, _ray, _boxes)
	if id == "" and p != null:
		var q: Vector3 = p
		for i in N:
			if Vector2(spot(i).x - q.x, spot(i).z - q.z).length() < 0.9:
				id = str(i)
	if id == "":
		return
	_tap(int(id))


func _tap(i: int) -> void:
	_idle_t = 0.0
	_hint = -1
	_hint_ring.visible = false
	_busy = true
	if diorama.shaib:
		TableKit.face(diorama.shaib, spot(i) - HOST)
		diorama.play_shaib("interact", "idle")
	get_tree().create_timer(0.35).timeout.connect(func():
		for j in [i - 1, i, i + 1]:
			var k := posmod(j, N)
			lit[k] = not lit[k]
			TableKit.sfx(self, "switch_%d" % (k % 5), spot(k) + Vector3(0, POST_H, 0), -8.0, 1.0 if lit[k] else 0.8)
		_show()
		_busy = false
		if not lit.has(false):
			_win())


## The lanterns to tap from here (each once, any order): lights-out on a ring of N.
func solution() -> Array:
	for mask in 1 << N:
		var state := lit.duplicate()
		for i in N:
			if mask & (1 << i):
				for j in [i - 1, i, i + 1]:
					state[posmod(j, N)] = not state[posmod(j, N)]
		if not state.has(false):
			var out: Array = []
			for i in N:
				if mask & (1 << i):
					out.append(i)
			return out
	return []


func _win() -> void:
	_won = true
	_busy = true
	TableKit.sfx(self, "success", FIRE, -2.0)
	_fire.visible = true
	_fire.scale = Vector3(1, 0.1, 1)
	create_tween().tween_property(_fire, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_BACK)
	if diorama.shaib:
		TableKit.face(diorama.shaib, Vector3(1, 0, 0))
	# the guests come in from the right and sit on the dakka
	for k in GUESTS.size():
		var g := TableKit.model(self, Diorama.SHAIB, Vector3(11.0 + k * 1.3, 0, -1.0), -PI / 2, Diorama.LIFE_SCALE.shaib)
		if g == null:
			continue
		Wardrobe.apply(g, GUESTS[k])
		var ap: AnimationPlayer = g.find_children("*", "AnimationPlayer", true, false)[0] if not g.find_children("*", "AnimationPlayer", true, false).is_empty() else null
		if ap and ap.has_animation("walk"):
			ap.get_animation("walk").loop_mode = Animation.LOOP_LINEAR
			ap.play("walk")
		var seat: Vector3 = SEATS[k]
		var front := Vector3(seat.x, 0, -2.0)
		var tw := create_tween()
		tw.tween_interval(0.6 + k * 0.9)
		tw.tween_callback(func(): TableKit.face(g, front - g.position))
		tw.tween_property(g, "position", front, g.position.distance_to(front) / 1.3)
		tw.tween_callback(func(): TableKit.face(g, Vector3(0, 0, -1)))
		tw.tween_property(g, "position", seat + Vector3(0, DAKKA_Y, 0), 0.9)
		tw.tween_callback(func():
			TableKit.face(g, Vector3(0, 0, 1))
			if ap and ap.has_animation("sit_idle"):
				ap.get_animation("sit_idle").loop_mode = Animation.LOOP_LINEAR
				ap.play("sit_idle", 0.3))
	var end := create_tween()
	end.tween_interval(9.0)
	end.tween_callback(func():
		if diorama.shaib:
			TableKit.face(diorama.shaib, Vector3(0, 0, -1))
		diorama.play_shaib("celebrate", "idle")
		TableKit.sfx(self, "level_complete", FIRE))
	end.tween_interval(3.0)
	end.tween_callback(func(): level_won.emit())


func demo() -> void:
	_demo = solution()


func _process(dt: float) -> void:
	_t += dt
	if _fire.visible:
		for c in _fire.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is CylinderMesh:
				c.scale.y = 1.0 + 0.18 * sin(_t * 9.0 + c.position.x * 20.0)
	for i in N:
		if lit[i]:
			var f: Dictionary = _flames[i]
			var k := 1.0 + 0.08 * sin(_t * 11.0 + i * 1.7)
			(f.flame as Node3D).scale = Vector3(k, k * 1.15, k)
	if _won or _busy:
		return
	if not _demo.is_empty():
		_tap(_demo.pop_front())
		return
	_idle_t += dt
	if _idle_t > HINT_AFTER:
		if _hint < 0:
			var s := solution()
			_hint = s[0] if not s.is_empty() else -1
		_hint_ring.visible = _hint >= 0
		if _hint_ring.visible:
			var pulse := 1.0 + 0.15 * sin(_t * 5.0)
			_hint_ring.position = spot(_hint) + Vector3(0, 0.05, 0)
			_hint_ring.scale = Vector3(pulse, 0.3, pulse)
