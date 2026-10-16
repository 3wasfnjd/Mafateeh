class_name TableStepsLevel
extends Node3D
## Level 2 on the table, «درج من طين» (steps of mud). Wordless.
## Scene 2: a lane between a tall house and its low annex. The cat has climbed onto the annex
## roof and can't get down; the old man stands in the lane looking up at it. Three mud blocks,
## tall, middle and short, lie about the lane. Tap a block and it hops to the next free place
## along the annex wall (the first one under the cat); tap a placed block and it goes back.
## With all three placed, if they make a stair (tallest under the cat, going down away from
## it) the cat steps down them and runs to the old man,
## who dances; otherwise they shake and tumble back to where they were.
##
## Lives under Diorama.model: positions are in the diorama's own metres (Godot axes).

signal level_won

const SFX := "res://audio/sfx/"
const MUD := "res://assets/world/kit/wall_kit_mud_tile.jpg"
const ROOF_Y := 2.8                     # annex roof top (tools/blender/build_scene2.py: ANNEX_H)
const PERCH := Vector3(2.9, ROOF_Y, -1.75)   # the cat, at the roof's front edge, near its right end
# along the annex's front wall, from under the cat leftwards: a stair seen side-on from the lane
const SLOTS := [Vector3(2.9, 0, -0.88), Vector3(2.2, 0, -0.88), Vector3(1.5, 0, -0.88)]
const BLOCK_W := 0.66
# the blocks: height and where each lies at the start (not in stair order)
const BLOCKS := [[1.4, Vector3(-4.4, 0, 3.6)], [0.7, Vector3(0.4, 0, 5.4)], [2.1, Vector3(4.6, 0, 2.2)]]
const OLD_MAN := Vector3(-1.8, 0, 2.6)
const CAT_GOAL := Vector3(-1.15, 0, 2.2)     # at the old man's feet
const PICK_R := 0.8                          # ground-point fallback when the ray misses a block
const HINT_AFTER := 14.0

var diorama: Diorama
var cat: Node3D
var blocks: Array = []   # {node, h, home, slot}
var _slots: Array = [null, null, null]   # block dict in each slot, or null
var _was_held := false
var _ray := []           # last world ray from aim(): [origin, dir]
var _busy := false       # a check or the ending is playing
var _won := false
var _idle_t := 0.0
var _t := 0.0
var _hint: MeshInstance3D
var _marks: Array = []   # faint squares on the ground where the blocks go


func setup(d: Diorama) -> void:
	diorama = d
	cat = CreatureSlot.spawn(self, "cat")
	cat.scale = Vector3.ONE * Diorama.LIFE_SCALE.cat
	cat.position = PERCH
	cat.rotation.y = 0.0  # looking down into the lane
	CreatureSlot.play(cat, "sit")
	if diorama.shaib:
		diorama.shaib.position = OLD_MAN
		_face(diorama.shaib, PERCH - OLD_MAN)
		diorama.play_shaib("idle", "")
	var mud := StandardMaterial3D.new()
	mud.albedo_texture = load(MUD) if ResourceLoader.exists(MUD) else null
	mud.albedo_color = Color("d9a777") if mud.albedo_texture else Color("b98a5c")  # a shade darker than the walls, so they read as loose
	mud.uv1_triplanar = true
	mud.uv1_scale = Vector3.ONE * 0.6
	mud.roughness = 1.0
	for b in BLOCKS:
		var h: float = b[0]
		var bm := BoxMesh.new()
		bm.size = Vector3(BLOCK_W, h, BLOCK_W)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = mud
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var n := Node3D.new()   # origin on the ground, at the block's foot
		add_child(n)
		n.add_child(mi)
		mi.position.y = h / 2
		n.position = b[1]
		n.rotation.y = randf_range(-0.3, 0.3)
		blocks.append({"node": n, "h": h, "home": b[1], "slot": -1, "yaw": n.rotation.y})
	for s in SLOTS:
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(BLOCK_W, BLOCK_W) * 1.05
		q.mesh = pm
		q.material_override = _glow_mat(Color("fff0d0"), 0.22)
		add_child(q)
		q.position = s + Vector3(0, 0.03, 0)
		_marks.append(q)
	_hint = _ring(0.75, Color("e6b85a"))
	_hint.visible = false


## World-space ray of the pointing hand (or mouse), every frame before pointer().
func aim(origin: Vector3, dir: Vector3) -> void:
	_ray = [origin, dir]


## held = trigger down; p = point on the diorama ground (model metres) or null.
func pointer(held: bool, p) -> void:
	var pressed := held and not _was_held
	_was_held = held
	if not pressed or _busy or _won:
		return
	var b := _pick(p)
	if b.is_empty():
		return
	_idle_t = 0.0
	_hint.visible = false
	if b.slot >= 0:
		_slots[b.slot] = null
		b.slot = -1
		_hop(b, b.home, b.yaw)
		_sfx("brick_lift", b.node.position)
		return
	var free := _slots.find(null)
	if free < 0:
		return
	_slots[free] = b
	b.slot = free
	_sfx("brick_lift", b.node.position)
	_hop(b, SLOTS[free], 0.0).finished.connect(func():
		_sfx("brick_place", b.node.position)
		if not _slots.has(null):
			_check())


## The block under the ray (its box, a little enlarged), else the one nearest the ground point.
func _pick(p) -> Dictionary:
	if _ray.size() == 2:
		var o := to_local(_ray[0])
		var d := to_local(_ray[0] + _ray[1]) - o
		var best := {}
		var best_t := INF
		for b in blocks:
			var n: Node3D = b.node
			var box := AABB(n.position - Vector3(BLOCK_W / 2, 0, BLOCK_W / 2), Vector3(BLOCK_W, b.h, BLOCK_W)).grow(0.18)
			var hit = box.intersects_ray(o, d)
			if hit != null and o.distance_to(hit) < best_t:
				best_t = o.distance_to(hit)
				best = b
		if not best.is_empty():
			return best
	if p == null:
		return {}
	var q: Vector3 = p
	var best2 := {}
	var best_d := PICK_R
	for b in blocks:
		var dd := Vector2(b.node.position.x - q.x, b.node.position.z - q.z).length()
		if dd < best_d:
			best_d = dd
			best2 = b
	return best2


func _hop(b: Dictionary, to: Vector3, yaw: float) -> Tween:
	var n: Node3D = b.node
	var from := n.position
	var y0 := n.rotation.y
	var up: float = 0.6 + b.h * 0.3
	var tw := create_tween()
	tw.tween_method(func(k: float):
		n.position = from.lerp(to, k) + Vector3(0, sin(k * PI) * up, 0)
		n.rotation.y = lerp_angle(y0, yaw, k), 0.0, 1.0, 0.45).set_trans(Tween.TRANS_SINE)
	return tw


## All three placed: a stair (tallest against the wall) lets the cat down; else they tumble back.
func _check() -> void:
	var ok := true
	for i in 3:
		if i > 0 and _slots[i].h >= _slots[i - 1].h:
			ok = false
	if ok and _slots[0].h < ROOF_Y - 0.9:
		ok = false
	_busy = true
	if ok:
		_win()
		return
	_sfx("soft_reject", SLOTS[1])
	for s in _slots:
		var n: Node3D = s.node
		var x0: float = SLOTS[s.slot].x
		var tw := create_tween()
		for k in 4:
			tw.tween_property(n, "position:x", x0 + (0.08 if k % 2 == 0 else -0.08), 0.06)
		tw.tween_property(n, "position:x", x0, 0.06)
	get_tree().create_timer(0.8).timeout.connect(func():
		for b in blocks:
			if b.slot >= 0:
				_slots[b.slot] = null
				b.slot = -1
				_hop(b, b.home, b.yaw)
		_sfx("brick_drop", SLOTS[1])
		_busy = false)


func _win() -> void:
	_won = true
	_sfx("success", PERCH, -2.0)
	for m in _marks:
		m.visible = false
	# down the steps: roof edge, each block top, the ground, then along the lane to him
	var steps: Array = [PERCH + Vector3(0, 0, 0.35)]
	for i in 3:
		steps.append(SLOTS[i] + Vector3(0, _slots[i].h, 0))
	steps.append(SLOTS[2] + Vector3(-0.7, 0, 0.3))
	var tw := create_tween()
	tw.tween_interval(0.5)
	var at: Vector3 = cat.position
	for s in steps:
		var a := at
		var b: Vector3 = s
		tw.tween_callback(func(): CreatureSlot.play(cat, "walk"))
		tw.tween_method(func(k: float):
			cat.position = a.lerp(b, k) + Vector3(0, sin(k * PI) * 0.35, 0), 0.0, 1.0, 0.38)
		tw.tween_callback(func(): _sfx("tap", b, -10.0))
		tw.tween_interval(0.12)
		at = b
	var walk: float = at.distance_to(CAT_GOAL) / 1.8
	tw.tween_callback(func():
		_face(cat, CAT_GOAL - cat.position)
		if diorama.shaib:
			_face(diorama.shaib, CAT_GOAL - OLD_MAN))
	tw.tween_property(cat, "position", CAT_GOAL, walk)
	tw.tween_callback(func():
		_face(cat, OLD_MAN - CAT_GOAL)
		CreatureSlot.play(cat, "sit")
		diorama.play_shaib("ardah", "")
		diorama.scare_birds(CAT_GOAL, 5.0))
	tw.tween_interval(4.0)
	tw.tween_callback(func():
		_sfx("level_complete", CAT_GOAL)
		level_won.emit())


## Screenshot/test helper: taps the blocks into a stair.
func demo() -> void:
	var order := blocks.duplicate()
	order.sort_custom(func(a, b): return a.h > b.h)
	var tw := create_tween()
	for b in order:
		tw.tween_callback(func():
			_ray = []
			pointer(false, null)
			pointer(true, b.node.position))
		tw.tween_interval(0.7)
	tw.tween_callback(func(): pointer(false, null))


func _process(dt: float) -> void:
	_t += dt
	if _won or _busy:
		return
	_idle_t += dt
	# a wordless nudge: after a while, the block that belongs next glows at its foot
	if _idle_t > HINT_AFTER:
		var want := _next_block()
		_hint.visible = not want.is_empty()
		if _hint.visible:
			var pulse := 1.0 + 0.12 * sin(_t * 4.0)
			_hint.position = (want.node as Node3D).position + Vector3(0, 0.05, 0)
			_hint.scale = Vector3(pulse, 0.2, pulse)
	for i in _marks.size():
		_marks[i].visible = _slots[i] == null


## The loose block that should go in the next free slot (or the misplaced one to take back).
func _next_block() -> Dictionary:
	var sorted := blocks.duplicate()
	sorted.sort_custom(func(a, b): return a.h > b.h)
	for i in 3:
		if _slots[i] == null:
			return sorted[i] if sorted[i].slot < 0 else {}
		if _slots[i] != sorted[i]:
			return _slots[i]
	return {}


static func _face(n: Node3D, d: Vector3) -> void:
	if Vector2(d.x, d.z).length() > 0.001:
		n.rotation.y = atan2(d.x, d.z)


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


func _sfx(name: String, at: Vector3, db := 0.0) -> void:
	var path := SFX + name + ".wav"
	if not ResourceLoader.exists(path) or not is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = load(path)
	p.volume_db = db
	add_child(p)
	p.position = at
	p.play()
	p.finished.connect(p.queue_free)
