class_name TableBarterLevel
extends Node3D
## Level 8 on the table, «المقايضة» (barter). Wordless.
## Scene 8: the souq. Six merchants stand at their stalls; each has his goods on the counter
## and, over his head, what he would take for them. The old man comes with a basket of dates
## and wants the brass coffee pot. Tap a stall and he walks over: if he carries what that
## merchant wants, they trade; if not, the merchant shakes his head. Trade your way to the
## coffee pot. (Dates -> cloth -> jar -> coffee -> the coffee pot; the incense seller and the
## perfumer trade in a circle that leads nowhere.) The coffee-pot seller first asks for the
## jar; the moment the old man has one, he raises his price: now he wants the coffee.
##
## Lives under Diorama.stage: positions are in the diorama's own metres (Godot axes).

signal level_won

const OLD_MAN := Vector3(0.0, 0.0, 2.8)
# merchant: where he stands, which way he faces (deg), where the old man stands to trade,
# what he wants, what he gives, his dress
const STALLS := [
	[Vector3(-6.0, 0, -4.4), 0.0, Vector3(-6.0, 0, -2.2), "dates", "cloth", {"head": "ghutra", "thobe": "thobe_grey"}],
	[Vector3(-2.0, 0, -4.4), 0.0, Vector3(-2.0, 0, -2.2), "jar", "coffee", {"agal": "agal_gold"}],
	[Vector3(2.0, 0, -4.4), 0.0, Vector3(2.0, 0, -2.2), "coffee", "dallah", {"bisht": "bisht", "head": "ghutra"}],
	[Vector3(6.0, 0, -4.4), 0.0, Vector3(6.0, 0, -2.2), "cloth", "jar", {"thobe": "thobe_beige", "glasses": "glasses"}],
	[Vector3(-8.0, 0, 0.0), 90.0, Vector3(-5.5, 0, 0.0), "dates", "incense", {"misbaha": "misbaha"}],
	[Vector3(8.0, 0, 0.0), -90.0, Vector3(5.5, 0, 0.0), "incense", "dates", {"head": "ghutra", "agal": "agal_gold"}],
]
const START_ITEM := "dates"
const GOAL := "dallah"
const SPEED := 1.6
const HINT_AFTER := 20.0

var diorama: Diorama
var holding := START_ITEM
var _carried: Node3D
var _merchants: Array = []   # {node, anim}
var _bubbles: Array = []
var _boxes := {}
var _busy := false
var _won := false
var _was_held := false
var _ray := []
var _idle_t := 0.0
var _t := 0.0
var _hint := -1
var _hint_ring: MeshInstance3D
var _demo := false
var wants: Array = []         # what each merchant wants now (the coffee-pot seller changes his mind)
const POT := 2                # the coffee-pot seller
const FIRST_PRICE := "jar"


func setup(d: Diorama) -> void:
	diorama = d
	for s in STALLS:
		wants.append(s[3])
	wants[POT] = FIRST_PRICE
	if diorama.shaib:
		diorama.shaib.position = OLD_MAN
		diorama.shaib.rotation.y = PI
		diorama.play_shaib("idle", "")
	for i in STALLS.size():
		var s: Array = STALLS[i]
		var m := TableKit.model(self, Diorama.SHAIB, s[0], deg_to_rad(s[1]), Diorama.LIFE_SCALE.shaib)
		var ap: AnimationPlayer = null
		if m:
			Wardrobe.apply(m, s[5])
			var aps := m.find_children("*", "AnimationPlayer", true, false)
			ap = aps[0] if not aps.is_empty() else null
			if ap and ap.has_animation("idle"):
				ap.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
				ap.play("idle")
				ap.seek(randf() * 3.0)
		_merchants.append({"node": m, "anim": ap})
		# his goods on the counter, between him and the lane
		var fwd := Vector3(sin(deg_to_rad(s[1])), 0, cos(deg_to_rad(s[1])))
		var goods := item(s[4])
		add_child(goods)
		goods.position = s[0] + fwd * 1.0 + Vector3(0, 0.86, 0)
		# over his head, what he wants: the item on a pale disc
		var b := Node3D.new()
		add_child(b)
		b.position = s[0] + Vector3(0, 2.75, 0)
		var disc := TableKit.cyl(b, 0.5, 0.5, 0.04, TableKit.glow_mat(Color("fbf3e4"), 0.92), Vector3.ZERO, 24)
		disc.rotation.x = PI / 2
		var want := item(wants[i])
		b.add_child(want)
		want.position = Vector3(0, -0.15, 0.12)
		want.scale = Vector3.ONE * 1.25
		_bubbles.append(b)
		_boxes[str(i)] = AABB(s[0] - Vector3(1.4, 0, 1.4) + fwd * 0.6, Vector3(2.8, 3.4, 2.8))
	_carried = item(holding)
	add_child(_carried)
	_hint_ring = TableKit.ring(self, 0.9, Color("e6b85a"), 0.9)
	_hint_ring.visible = false


# --- goods ---------------------------------------------------------------------------------------

## A small model of a trade good (about 0.4 m), origin at its foot.
static func item(kind: String) -> Node3D:
	var n := Node3D.new()
	n.name = kind
	match kind:
		"dates":
			TableKit.cyl(n, 0.22, 0.17, 0.16, TableKit.mat(Color("b8894e")), Vector3(0, 0.08, 0), 12)
			for i in 9:
				var a := TAU * i / 9
				TableKit.sphere(n, 0.06, TableKit.mat(Color("5a2e14"), 0.5), Vector3(cos(a) * 0.12, 0.2 + (i % 3) * 0.02, sin(a) * 0.12), 6)
			TableKit.sphere(n, 0.07, TableKit.mat(Color("5a2e14"), 0.5), Vector3(0, 0.24, 0), 6)
		"cloth":
			var roll := TableKit.cyl(n, 0.13, 0.13, 0.5, TableKit.mat(Color("a8322a")), Vector3(0, 0.13, 0), 12)
			roll.rotation.z = PI / 2
			var band := TableKit.cyl(n, 0.135, 0.135, 0.08, TableKit.mat(Color("d9b25a"), 0.5), Vector3(0, 0.13, 0), 12)
			band.rotation.z = PI / 2
		"incense":
			TableKit.box(n, Vector3(0.2, 0.18, 0.2), TableKit.mat(Color("4a2e1c")), Vector3(0, 0.09, 0))
			TableKit.cyl(n, 0.0, 0.16, 0.16, TableKit.mat(Color("c9a24a"), 0.4), Vector3(0, 0.26, 0), 4)
			for i in 3:
				TableKit.sphere(n, 0.06 + i * 0.02, TableKit.glow_mat(Color("e8e4dc"), 0.7), Vector3(0.03 * i, 0.42 + i * 0.1, 0), 6)
		"jar":
			TableKit.sphere(n, 0.17, TableKit.mat(Color("b5643a")), Vector3(0, 0.17, 0), 10)
			TableKit.cyl(n, 0.07, 0.09, 0.14, TableKit.mat(Color("b5643a")), Vector3(0, 0.36, 0), 10)
		"coffee":
			TableKit.cyl(n, 0.16, 0.19, 0.28, TableKit.mat(Color("9a7a52")), Vector3(0, 0.14, 0), 10)
			for i in 7:
				var a := TAU * i / 7
				TableKit.sphere(n, 0.05, TableKit.mat(Color("7c8a52"), 0.6), Vector3(cos(a) * 0.08, 0.3, sin(a) * 0.08), 6)
		"dallah":
			var brass := TableKit.mat(Color("d9a63a"), 0.25)
			brass.metallic = 0.8
			TableKit.cyl(n, 0.16, 0.18, 0.06, brass, Vector3(0, 0.03, 0), 14)
			TableKit.cyl(n, 0.08, 0.16, 0.26, brass, Vector3(0, 0.19, 0), 14)
			TableKit.cyl(n, 0.1, 0.07, 0.08, brass, Vector3(0, 0.36, 0), 14)
			TableKit.cyl(n, 0.0, 0.06, 0.1, brass, Vector3(0, 0.45, 0), 10)
			var spout := TableKit.box(n, Vector3(0.05, 0.05, 0.24), brass, Vector3(0, 0.3, 0.17))
			spout.rotation.x = -0.7
	return n


# --- input and walking ------------------------------------------------------------------------

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
		for i in STALLS.size():
			if Vector2(STALLS[i][2].x - q.x, STALLS[i][2].z - q.z).length() < 1.4:
				id = str(i)
	if id != "":
		_visit(int(id))


func _visit(i: int) -> void:
	_idle_t = 0.0
	_hint = -1
	_hint_ring.visible = false
	_busy = true
	var s: Array = STALLS[i]
	var sh := diorama.shaib
	if sh == null:
		_trade(i)
		return
	var to: Vector3 = s[2]
	var d := to - sh.position
	if d.length() > 0.05:
		TableKit.face(sh, d)
		diorama.play_shaib("walk", "")
		var tw := create_tween()
		tw.tween_property(sh, "position", to, d.length() / SPEED)
		tw.tween_callback(func(): _trade(i))
	else:
		_trade(i)


func _trade(i: int) -> void:
	var s: Array = STALLS[i]
	var m: Dictionary = _merchants[i]
	var sh := diorama.shaib
	if sh:
		TableKit.face(sh, s[0] - sh.position)
	if holding != wants[i]:
		TableKit.sfx(self, "soft_reject", s[0], -4.0)
		_play(m, "reject")
		diorama.play_shaib("think", "idle")
		_busy = false
		return
	# they swap: his goods go over the counter, the merchant's come back
	TableKit.sfx(self, "gem_pickup", s[0], -4.0)
	_play(m, "interact")
	diorama.play_shaib("interact", "idle")
	var old := _carried
	var counter: Vector3 = s[0] + Vector3(sin(deg_to_rad(s[1])), 0, cos(deg_to_rad(s[1]))) * 1.0 + Vector3(0, 0.9, 0)
	var t1 := create_tween()
	t1.tween_property(old, "position", counter, 0.45).set_trans(Tween.TRANS_SINE)
	t1.tween_callback(old.queue_free)
	holding = s[4]
	_carried = item(holding)
	add_child(_carried)
	_carried.position = counter
	_carried.scale = Vector3.ONE * 0.6
	var t2 := create_tween().set_parallel()
	t2.tween_interval(0.25)
	t2.chain().tween_property(_carried, "scale", Vector3.ONE, 0.4)
	t2.tween_callback(func():
		_busy = false
		if holding == GOAL:
			_win()
		elif holding == FIRST_PRICE and wants[POT] == FIRST_PRICE:
			_raise_price())


## The coffee-pot seller saw the old man get the jar: he wants the coffee now.
func _raise_price() -> void:
	wants[POT] = STALLS[POT][3]
	var b: Node3D = _bubbles[POT]
	var old: Node3D = b.get_child(1)
	_play(_merchants[POT], "think")
	TableKit.sfx(self, "soft_reject", b.position, -8.0, 1.3)
	var tw := create_tween()
	tw.tween_property(b, "scale", Vector3.ONE * 1.25, 0.15)
	tw.tween_property(b, "rotation:z", 0.25, 0.08)
	tw.tween_property(b, "rotation:z", -0.25, 0.12)
	tw.tween_property(b, "rotation:z", 0.0, 0.08)
	tw.tween_callback(func():
		old.queue_free()
		var want := item(wants[POT])
		b.add_child(want)
		want.position = Vector3(0, -0.15, 0.12)
		want.scale = Vector3.ONE * 1.25
		TableKit.sfx(self, "dial_click", b.position, -6.0))
	tw.tween_property(b, "scale", Vector3.ONE, 0.25)


static func _play(m: Dictionary, clip: String) -> void:
	var ap: AnimationPlayer = m.anim
	if ap and ap.has_animation(clip):
		ap.play(clip, 0.2)
		ap.queue("idle")


func _win() -> void:
	_won = true
	TableKit.sfx(self, "success", _carried.position, -2.0)
	diorama.play_shaib("celebrate", "idle")
	diorama.scare_birds(diorama.shaib.position if diorama.shaib else OLD_MAN, 5.0)
	for m in _merchants:
		_play(m, "celebrate")
	var tw := create_tween()
	tw.tween_interval(4.5)
	tw.tween_callback(func():
		TableKit.sfx(self, "level_complete", OLD_MAN)
		level_won.emit())


## The stalls to visit, in order, from what he holds now to the coffee pot.
func route() -> Array:
	var prev := {holding: null}
	var queue: Array = [holding]
	while not queue.is_empty():
		var it: String = queue.pop_front()
		if it == GOAL:
			var stalls: Array = []
			var k := it
			while prev[k] != null:
				stalls.push_front(prev[k][1])
				k = prev[k][0]
			return stalls
		for i in STALLS.size():
			if wants[i] == it and not prev.has(STALLS[i][4]):
				prev[STALLS[i][4]] = [it, i]
				queue.append(STALLS[i][4])
	return []


func demo() -> void:
	_demo = true


func _process(dt: float) -> void:
	_t += dt
	# what he carries rides along at his shoulder
	if _carried and diorama.shaib and not _busy:
		_carried.position = _carried.position.lerp(diorama.shaib.position + Vector3(0, 1.75, 0), clampf(dt * 10.0, 0, 1))
	elif _carried and diorama.shaib and _carried.scale.x > 0.99:
		_carried.position = _carried.position.lerp(diorama.shaib.position + Vector3(0, 1.75, 0), clampf(dt * 6.0, 0, 1))
	for b in _bubbles:
		if b.get_child_count() > 1:
			var want: Node3D = b.get_child(b.get_child_count() - 1)
			want.rotation.y += dt * 0.8
	if _won or _busy:
		return
	if _demo:
		var r := route()
		if not r.is_empty():
			_visit(r[0])
		return
	_idle_t += dt
	if _idle_t > HINT_AFTER:
		if _hint < 0:
			var r := route()
			_hint = r[0] if not r.is_empty() else -1
		_hint_ring.visible = _hint >= 0
		if _hint_ring.visible:
			var pulse := 1.0 + 0.12 * sin(_t * 5.0)
			_hint_ring.position = STALLS[_hint][2] + Vector3(0, 0.05, 0)
			_hint_ring.scale = Vector3(pulse, 0.3, pulse)
