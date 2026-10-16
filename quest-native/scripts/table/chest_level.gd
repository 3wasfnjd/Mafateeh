class_name TableChestLevel
extends Node3D
## Level 10 on the table, «صندوق الجد» (the grandfather's chest). Wordless. Evening.
## Scene 10: the family house's inner courtyard. In the middle stands the grandfather's Najdi
## chest, nine brass studs across its front. Round it, each on a little mud stand, lies a
## keepsake of the journey: the cat, a mud block, the key, the water truck, a lantern, a drum,
## a star, the coffee pot, a young palm. Tap them in the order the journey went (the order of
## the chapters) and each goes into the chest and lights a stud; a keepsake out of turn just
## shakes. With all nine in, the lid opens, the drums beat, the men dance, the falcon wheels
## overhead and the cat sits at the old man's feet.
##
## Lives under Diorama.stage: positions are in the diorama's own metres (Godot axes).

signal level_won

const CHEST := Vector3(0.0, 0.0, -0.4)     # back from the front wall, which hides the ground just behind it
const OLD_MAN := Vector3(0.0, 0.0, -1.8)
const ARC_R := 3.2
const KEEPSAKES := ["cat", "block", "key", "truck", "lantern", "drum", "star", "dallah", "palm"]
const PLACES := [4, 7, 1, 8, 2, 5, 0, 6, 3]   # which arc place each keepsake stands on (shuffled)
const DANCERS := [Vector3(-3.6, 0, -4.6), Vector3(-1.2, 0, -4.8), Vector3(1.2, 0, -4.8), Vector3(3.6, 0, -4.6)]  # in the riwaq
const DANCER_DRESS := [{"bisht": "bisht", "head": "ghutra"}, {"thobe": "thobe_grey"}, {"agal": "agal_gold"}, {"thobe": "thobe_beige", "glasses": "glasses"}]
const HINT_AFTER := 20.0
const GOLD := Color("e6b85a")

var diorama: Diorama
var next := 0                 # how many keepsakes are in the chest
var _items: Array = []        # {node, stand, at}
var _studs: Array = []
var _lid: Node3D
var _glow: MeshInstance3D
var _boxes := {}
var _busy := false
var _won := false
var _was_held := false
var _ray := []
var _idle_t := 0.0
var _t := 0.0
var _hint_ring: MeshInstance3D
var _demo := false
var _falcon: Node3D
var _falcon_a := 0.0


func setup(d: Diorama) -> void:
	diorama = d
	if diorama.shaib:
		diorama.shaib.position = OLD_MAN
		diorama.shaib.rotation.y = 0.0
		diorama.play_shaib("idle", "")
	_chest()
	for i in KEEPSAKES.size():
		var a := deg_to_rad(-25.0 + PLACES[i] * 28.75)  # round the chest, all but the side towards the house
		var at := CHEST + Vector3(cos(a), 0, sin(a)) * ARC_R
		var stand := TableKit.cyl(self, 0.38, 0.44, 0.5, TableKit.mat(Color("b98a5c")), at + Vector3(0, 0.25, 0), 12)
		var n := _keepsake(KEEPSAKES[i])
		add_child(n)
		n.position = at + Vector3(0, 0.5, 0)
		TableKit.face(n, CHEST - at)
		_items.append({"node": n, "stand": stand, "at": at})
		_boxes[str(i)] = AABB(at - Vector3(0.6, 0, 0.6), Vector3(1.2, 1.6, 1.2))
	for x in [-6.2, 6.2]:   # two lit lanterns in the riwaq
		var lamp := TableKit.model(self, "res://assets/world/props/lantern.glb", Vector3(x, 0, -3.2), 0.0, 1.0)
		if lamp:
			TableKit.sphere(self, 0.12, TableKit.lit_mat(Color("ffc46b"), 2.4), Vector3(x, 0.3, -3.2), 8)
	_hint_ring = TableKit.ring(self, 0.6, GOLD, 0.9)
	_hint_ring.visible = false


func _chest() -> void:
	var n := Node3D.new()
	add_child(n)
	n.position = CHEST
	var wood := TableKit.mat(Color("6e2f1e"), 0.7)
	var brass := TableKit.mat(Color("d9a63a"), 0.3)
	brass.metallic = 0.7
	TableKit.box(n, Vector3(1.6, 0.8, 0.9), wood, Vector3(0, 0.45, 0))
	TableKit.box(n, Vector3(1.66, 0.1, 0.96), wood, Vector3(0, 0.05, 0))        # its feet
	for x in [-0.6, 0.0, 0.6]:                                                   # brass bands
		TableKit.box(n, Vector3(0.06, 0.82, 0.92), brass, Vector3(x, 0.45, 0))
	for i in 9:   # the studs: one lights for each keepsake put in
		var s := TableKit.sphere(n, 0.045, brass, Vector3(-0.64 + i * 0.16, 0.62, 0.46), 6)
		_studs.append(s)
	_lid = Node3D.new()   # hinged at the back edge
	n.add_child(_lid)
	_lid.position = Vector3(0, 0.85, -0.45)
	TableKit.box(_lid, Vector3(1.64, 0.14, 0.94), wood, Vector3(0, 0.07, 0.45))
	for x in [-0.6, 0.0, 0.6]:
		TableKit.box(_lid, Vector3(0.06, 0.16, 0.96), brass, Vector3(x, 0.07, 0.45))
	_glow = TableKit.box(n, Vector3(1.4, 0.04, 0.7), TableKit.lit_mat(Color("ffd27a"), 2.5), Vector3(0, 0.83, 0))
	_glow.visible = false
	_boxes["chest"] = AABB(CHEST - Vector3(0.9, 0, 0.6), Vector3(1.8, 1.2, 1.2))


## The keepsakes, each a little model (about half a metre), origin at the foot.
func _keepsake(kind: String) -> Node3D:
	var n := Node3D.new()
	match kind:
		"cat":
			var c := CreatureSlot.spawn(n, "cat")
			if c:
				c.scale = Vector3.ONE * Diorama.LIFE_SCALE.cat
				CreatureSlot.play(c, "sit")
		"block":
			TableKit.box(n, Vector3(0.36, 0.5, 0.36), TableKit.mat(Color("d9a777")), Vector3(0, 0.25, 0))
		"key":
			var gold := TableKit.mat(GOLD, 0.3)
			gold.metallic = 0.7
			var ring := TableKit.mesh(n, TorusMesh.new(), gold, Vector3(-0.16, 0.25, 0), Vector3(PI / 2, 0, 0))
			ring.scale = Vector3.ONE * 0.2
			TableKit.box(n, Vector3(0.36, 0.05, 0.05), gold, Vector3(0.08, 0.25, 0))
			TableKit.box(n, Vector3(0.05, 0.12, 0.05), gold, Vector3(0.22, 0.2, 0))
		"truck":
			TableKit.model(n, "res://assets/world/props/wayit.glb", Vector3.ZERO, PI / 2, 0.09)
		"lantern":
			TableKit.model(n, "res://assets/world/props/lantern.glb", Vector3.ZERO, 0.0, 0.8)
			TableKit.sphere(n, 0.07, TableKit.lit_mat(Color("ffc46b"), 2.2), Vector3(0, 0.26, 0), 6)
		"drum":
			TableKit.cyl(n, 0.22, 0.2, 0.3, TableKit.mat(Color("b5452f")), Vector3(0, 0.15, 0), 14)
			TableKit.cyl(n, 0.225, 0.225, 0.03, TableKit.mat(Color("efe2c4")), Vector3(0, 0.31, 0), 14)
		"star":
			var lit := TableKit.lit_mat(Color("ffd27a"), 2.6)
			TableKit.sphere(n, 0.12, lit, Vector3(0, 0.35, 0), 8)
			for i in 4:
				var ray := TableKit.box(n, Vector3(0.05, 0.36, 0.05), lit, Vector3(0, 0.35, 0), Vector3(0, 0, PI / 4 * i))
				ray.scale = Vector3.ONE
		"dallah":
			n.add_child(TableBarterLevel.item("dallah"))
		"palm":
			TableKit.cyl(n, 0.2, 0.22, 0.12, TableKit.mat(Color("6b4a30")), Vector3(0, 0.06, 0), 10)
			TableKit.model(n, "res://assets/world/palm.glb", Vector3(0, 0.1, 0), 0.0, 0.13)
	return n


# --- input -------------------------------------------------------------------------------------

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
		for i in _items.size():
			var at: Vector3 = _items[i].at
			if Vector2(at.x - q.x, at.z - q.z).length() < 0.8:
				id = str(i)
	if id == "" or id == "chest":
		return
	_pick(int(id))


func _pick(i: int) -> void:
	_idle_t = 0.0
	_hint_ring.visible = false
	var item: Dictionary = _items[i]
	var n: Node3D = item.node
	if not n.visible:
		return
	if i != next:
		TableKit.sfx(self, "soft_reject", n.position, -4.0)
		var x0 := n.position.x
		var tw := create_tween()
		for k in 4:
			tw.tween_property(n, "position:x", x0 + (0.07 if k % 2 == 0 else -0.07), 0.06)
		tw.tween_property(n, "position:x", x0, 0.06)
		return
	_busy = true
	if diorama.shaib:
		TableKit.face(diorama.shaib, n.position - OLD_MAN)
		diorama.play_shaib("interact", "idle")
	var from := n.position
	var to := CHEST + Vector3(0, 1.0, 0)
	var stud: Node3D = _studs[next]
	TableKit.sfx(self, "seq_%d" % (next % 6 + 1), from, -4.0)
	var tw := create_tween()
	tw.tween_method(func(k: float):
		n.position = from.lerp(to, k) + Vector3(0, sin(k * PI) * 1.4, 0)
		n.scale = Vector3.ONE * lerpf(1.0, 0.3, k), 0.0, 1.0, 0.8)
	tw.tween_callback(func():
		n.visible = false
		(stud as MeshInstance3D).material_override = TableKit.lit_mat(GOLD, 2.4)
		TableKit.sfx(self, "brick_place", CHEST, -6.0)
		next += 1
		_busy = false
		if diorama.shaib:
			diorama.shaib.rotation.y = 0.0
		if next >= KEEPSAKES.size():
			_win())


func _win() -> void:
	_won = true
	TableKit.sfx(self, "unlock", CHEST, 0.0)
	var tw := create_tween()
	tw.tween_property(_lid, "rotation:x", deg_to_rad(-105), 1.4).set_trans(Tween.TRANS_BACK)
	tw.tween_callback(func():
		_glow.visible = true
		TableKit.sfx(self, "success", CHEST, -2.0)
		_celebrate())
	tw.tween_interval(9.0)
	tw.tween_callback(func():
		TableKit.sfx(self, "level_complete", CHEST)
		level_won.emit())


## Everyone from the journey: the men dance, the drums beat, the falcon wheels, the cat comes.
func _celebrate() -> void:
	diorama.play_shaib("ardah", "")
	diorama.scare_birds(CHEST, 6.0)
	for k in DANCERS.size():
		var m := TableKit.model(self, Diorama.SHAIB, DANCERS[k], 0.0, Diorama.LIFE_SCALE.shaib)
		if m == null:
			continue
		Wardrobe.apply(m, DANCER_DRESS[k])
		var aps := m.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty() and (aps[0] as AnimationPlayer).has_animation("ardah"):
			var ap: AnimationPlayer = aps[0]
			ap.get_animation("ardah").loop_mode = Animation.LOOP_LINEAR
			ap.play("ardah")
			ap.seek(k * 0.2)
	var beat := create_tween().set_loops(10)
	for v in [1, 3, 2, 4]:
		var voice: int = v
		beat.tween_callback(func(): TableKit.sfx(self, "seq_%d" % voice, CHEST + Vector3(2.5, 0.5, -1.5), -8.0))
		beat.tween_interval(0.45)
	_falcon = CreatureSlot.spawn(self, "falcon")
	if _falcon:
		_falcon.scale = Vector3.ONE * Diorama.LIFE_SCALE.falcon
		CreatureSlot.play(_falcon, "fly")
	var cat := CreatureSlot.spawn(self, "cat")
	if cat:
		cat.scale = Vector3.ONE * Diorama.LIFE_SCALE.cat
		cat.position = Vector3(4.0, 0, 5.6)
		CreatureSlot.play(cat, "walk")
		var to := OLD_MAN + Vector3(0.6, 0, 0.5)
		TableKit.face(cat, to - cat.position)
		var t2 := create_tween()
		t2.tween_property(cat, "position", to, cat.position.distance_to(to) / 1.6)
		t2.tween_callback(func():
			TableKit.face(cat, OLD_MAN - to)
			CreatureSlot.play(cat, "sit"))


func demo() -> void:
	_demo = true


func _process(dt: float) -> void:
	_t += dt
	for it in _items:
		var n: Node3D = it.node
		if n.visible and not _busy:
			n.position.y = 0.5 + 0.05 * sin(_t * 2.0 + it.at.x)
	if _falcon:
		_falcon_a += dt * 0.5
		_falcon.position = CHEST + Vector3(cos(_falcon_a) * 4.5, 6.0 + sin(_falcon_a * 2.0) * 0.5, sin(_falcon_a) * 4.5)
		_falcon.rotation = Vector3(0, -_falcon_a, deg_to_rad(16))
	if _won or _busy:
		return
	if _demo:
		_pick(next)
		return
	_idle_t += dt
	if _idle_t > HINT_AFTER:
		_hint_ring.visible = true
		var pulse := 1.0 + 0.12 * sin(_t * 5.0)
		_hint_ring.position = _items[next].at + Vector3(0, 0.55, 0)
		_hint_ring.scale = Vector3(pulse, 0.3, pulse)
