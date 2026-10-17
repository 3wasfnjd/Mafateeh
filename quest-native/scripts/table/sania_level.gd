class_name TableSaniaLevel
extends Node3D
## Level 9 on the table, «السانية» (the draw-well). Wordless.
## Scene 9: a palm farm. At the well a camel walks back and forth, drawing the bucket up, and
## the water runs into the basin. From the basin it should run through the field's stone
## channels to three palm plots, but the channel pieces lie turned every way. Tap a piece and
## it turns a quarter. Water follows every channel that joins up; when it reaches all three
## plots the palms drink and the old man is glad. While he waits the plots dry out: the
## palms not yet watered droop, little by little; water brings them back.
##
## Lives under Diorama.stage: positions are in the diorama's own metres (Godot axes).

signal level_won

const COLS := 5
const ROWS := 4
const CELL := 1.6
const N := 1
const E := 2
const S := 4
const W := 8
# the solution: opening bits per cell (row, col); unlisted cells are spare pieces
const SOLVED := {
	Vector2i(0, 0): W | E, Vector2i(0, 1): W | E, Vector2i(0, 2): W | E | S, Vector2i(0, 3): W | E, Vector2i(0, 4): W | E,
	Vector2i(1, 2): N | S, Vector2i(2, 2): N | W | E, Vector2i(2, 1): E | S, Vector2i(3, 1): N | S,
	Vector2i(2, 3): W | E, Vector2i(2, 4): W | S, Vector2i(3, 4): N | E,
}
const SPARE := {
	Vector2i(1, 0): N | E, Vector2i(1, 1): N | S, Vector2i(1, 3): S | W, Vector2i(1, 4): N | E | W,
	Vector2i(2, 0): N | S, Vector2i(3, 0): N | E, Vector2i(3, 2): E | S | W, Vector2i(3, 3): W | E,
}
const SOURCE := [Vector2i(0, 0), W]                                  # the water comes in here
const SINKS := [[Vector2i(0, 4), E], [Vector2i(3, 4), E], [Vector2i(3, 1), S]]
const WELL := Vector3(-7.6, 0, -3.6)
const CAMEL_WALK := [Vector3(-7.4, 0, -1.6), Vector3(-7.0, 0, 4.0)]
const OLD_MAN := Vector3(-5.4, 0, 1.4)
const HINT_AFTER := 20.0
const STONE := Color("c9a27a")
const BED := Color("7d5f45")
const WATER := Color("5d9ab4")

var diorama: Diorama
var rot := {}            # cell -> quarter turns from its base piece
var base := {}           # cell -> opening bits of the unturned piece
var _tiles := {}         # cell -> {node, water: Array}
var _plots: Array = []   # {palm, water}
var _wet := {}
var _boxes := {}
var _busy := false
var _won := false
var _was_held := false
var _ray := []
var _idle_t := 0.0
var _t := 0.0
var _hint_ring: MeshInstance3D
var _demo: Array = []
var _camel: Node3D
var _rope: MeshInstance3D
const DRY_FROM := 25.0      # seconds before the palms begin to droop
const DRY_TIME := 90.0      # and how long until they hang their heads


func setup(d: Diorama) -> void:
	diorama = d
	if diorama.shaib:
		diorama.shaib.position = OLD_MAN
		TableKit.face(diorama.shaib, Vector3(1, 0, 0.4))
		diorama.play_shaib("idle", "")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for r in ROWS:
		for c in COLS:
			var cell := Vector2i(r, c)
			base[cell] = SOLVED.get(cell, SPARE.get(cell, N | S))
			rot[cell] = rng.randi_range(1, 3)   # never in place to begin with
			_tile(cell)
	for s in SINKS:
		_plot(s[0], s[1])
	_hint_ring = TableKit.ring(self, 0.95, Color("e6b85a"), 0.9)
	_hint_ring.visible = false
	_camel = TableKit.model(self, "res://assets/world/props/camel_standing.glb", CAMEL_WALK[0], 0.0, 0.85)
	_rope = TableKit.box(self, Vector3(0.04, 0.04, 1.0), TableKit.mat(Color("8a6a44")))
	_flow()


static func cell_pos(cell: Vector2i) -> Vector3:
	return Vector3((cell.y - 2) * CELL, 0, 1.1 + (cell.x - 1.5) * CELL)


static func turned_bits(bits: int, quarter: int) -> int:
	var b := bits
	for i in posmod(quarter, 4):
		b = ((b << 1) | (b >> 3)) & 15   # N -> E -> S -> W -> N
	return b


func openings(cell: Vector2i) -> int:
	return turned_bits(base[cell], rot[cell])


static func step(cell: Vector2i, dir: int) -> Vector2i:
	match dir:
		N: return cell + Vector2i(-1, 0)
		E: return cell + Vector2i(0, 1)
		S: return cell + Vector2i(1, 0)
	return cell + Vector2i(0, -1)


static func opposite(dir: int) -> int:
	return turned_bits(dir, 2)


# --- pieces ------------------------------------------------------------------------------------

## A channel piece: a bed, kerbs along its open arms, water that shows when it runs.
func _tile(cell: Vector2i) -> void:
	var n := Node3D.new()
	add_child(n)
	n.position = cell_pos(cell)
	var bits: int = base[cell]
	TableKit.box(n, Vector3(1.5, 0.06, 1.5), TableKit.mat(BED), Vector3(0, 0.03, 0))
	var stone := TableKit.mat(STONE)
	var water: Array = []
	var wmat := TableKit.lit_mat(WATER, 0.35)
	water.append(TableKit.box(n, Vector3(0.34, 0.03, 0.34), wmat, Vector3(0, 0.1, 0)))
	for dir in [N, E, S, W]:
		var a := _dir_vec(dir)
		var side := Vector3(-a.z, 0, a.x)
		if bits & dir:
			for sgn in [-1, 1]:
				var k := TableKit.box(n, Vector3(0.12, 0.22, 0.6), stone, a * 0.5 + side * sgn * 0.23 + Vector3(0, 0.11, 0))
				k.rotation.y = atan2(a.x, a.z)
			var w := TableKit.box(n, Vector3(0.34, 0.03, 0.6), wmat, a * 0.48 + Vector3(0, 0.1, 0))
			w.rotation.y = atan2(a.x, a.z)
			water.append(w)
		else:
			var k := TableKit.box(n, Vector3(0.58, 0.22, 0.12), stone, a * 0.23 + Vector3(0, 0.11, 0))
			k.rotation.y = atan2(a.x, a.z)
	n.rotation.y = -rot[cell] * PI / 2
	_tiles[cell] = {"node": n, "water": water}
	_boxes["%d,%d" % [cell.x, cell.y]] = AABB(n.position - Vector3(0.8, 0, 0.8), Vector3(1.6, 0.6, 1.6))


static func _dir_vec(dir: int) -> Vector3:
	match dir:
		N: return Vector3(0, 0, -1)
		E: return Vector3(1, 0, 0)
		S: return Vector3(0, 0, 1)
	return Vector3(-1, 0, 0)


func _plot(cell: Vector2i, dir: int) -> void:
	var at := cell_pos(cell) + _dir_vec(dir) * CELL
	TableKit.cyl(self, 0.75, 0.8, 0.12, TableKit.mat(Color("6b4a30")), at + Vector3(0, 0.06, 0), 16)
	var water := TableKit.cyl(self, 0.62, 0.62, 0.02, TableKit.lit_mat(WATER, 0.35), at + Vector3(0, 0.13, 0), 16)
	water.visible = false
	var palm := TableKit.model(self, "res://assets/world/palm.glb", at, randf() * TAU, 0.38)
	_plots.append({"palm": palm, "water": water, "cell": cell, "dir": dir})


# --- water -------------------------------------------------------------------------------------

## Floods the channels from the basin; true when all three plots are reached.
func _flow() -> bool:
	_wet.clear()
	var start: Vector2i = SOURCE[0]
	if openings(start) & SOURCE[1]:
		var queue: Array = [start]
		_wet[start] = true
		while not queue.is_empty():
			var c: Vector2i = queue.pop_front()
			for dir in [N, E, S, W]:
				if not (openings(c) & dir):
					continue
				var nb := step(c, dir)
				if _wet.has(nb) or not base.has(nb):
					continue
				if openings(nb) & opposite(dir):
					_wet[nb] = true
					queue.append(nb)
	for cell in _tiles:
		for w in _tiles[cell].water:
			(w as Node3D).visible = _wet.has(cell)
	var all := true
	for p in _plots:
		var reached: bool = _wet.has(p.cell) and (openings(p.cell) & p.dir) != 0
		(p.water as Node3D).visible = reached
		all = all and reached
	return all


# --- input -------------------------------------------------------------------------------------

func aim(origin: Vector3, dir: Vector3) -> void:
	_ray = [origin, dir]


func pointer(held: bool, p) -> void:
	var pressed := held and not _was_held
	_was_held = held
	if not pressed or _busy or _won:
		return
	var id := TableKit.ray_pick(self, _ray, _boxes)
	var cell = null
	if id != "":
		var parts := id.split(",")
		cell = Vector2i(int(parts[0]), int(parts[1]))
	elif p != null:
		var q: Vector3 = p
		var c := int(round(q.x / CELL)) + 2
		var r := int(round((q.z - 1.1) / CELL + 1.5))
		if base.has(Vector2i(r, c)):
			cell = Vector2i(r, c)
	if cell != null:
		_turn(cell)


func _turn(cell: Vector2i) -> void:
	_idle_t = 0.0
	_hint_ring.visible = false
	_busy = true
	rot[cell] = (rot[cell] + 1) % 4
	var n: Node3D = _tiles[cell].node
	TableKit.sfx(self, "brick_place", n.position, -8.0, 1.2)
	var tw := create_tween()
	tw.tween_property(n, "rotation:y", n.rotation.y - PI / 2, 0.22).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		_busy = false
		var before := _wet.size()
		var done := _flow()
		if _wet.size() > before:
			TableKit.sfx(self, "seq_2", n.position, -10.0)
		if done:
			_win())


## A piece that is part of the way and not turned right yet (straights look right two ways).
func _wrong_piece() -> Variant:
	for cell in SOLVED:
		if openings(cell) != SOLVED[cell]:
			return cell
	return null


func _win() -> void:
	_won = true
	TableKit.sfx(self, "success", cell_pos(Vector2i(2, 2)), -2.0)
	diorama.play_shaib("celebrate", "idle")
	diorama.scare_birds(OLD_MAN, 5.0)
	for p in _plots:
		var palm: Node3D = p.palm
		if palm:
			var tw := create_tween().set_parallel()
			tw.tween_property(palm, "scale", Vector3.ONE * 0.52, 1.5).set_trans(Tween.TRANS_BACK)
			tw.tween_property(palm, "rotation:z", 0.0, 1.0)   # standing up again
	var end := create_tween()
	end.tween_interval(5.0)
	end.tween_callback(func():
		TableKit.sfx(self, "level_complete", OLD_MAN)
		level_won.emit())


func demo() -> void:
	_demo.clear()
	for cell in SOLVED:
		var r: int = rot[cell]
		for k in 4:
			if turned_bits(base[cell], r + k) == SOLVED[cell]:
				for j in k:
					_demo.append(cell)
				break


func _process(dt: float) -> void:
	_t += dt
	# the camel walks out drawing the bucket up, and back; the rope runs from the pulley to him
	if _camel:
		var u := pingpong(_t * 0.09, 1.0)
		var a: Vector3 = CAMEL_WALK[0]
		var b: Vector3 = CAMEL_WALK[1]
		_camel.position = a.lerp(b, smoothstep(0.0, 1.0, u))
		_camel.rotation.y = 0.0 if fmod(_t * 0.09, 2.0) < 1.0 else PI
		var top := WELL + Vector3(0, 1.6, 0)
		var end := _camel.position + Vector3(0, 1.5, 0)
		_rope.position = (top + end) / 2
		_rope.look_at(to_global(end), global_basis.y)
		_rope.scale = Vector3(1, 1, top.distance_to(end))
	# thirst: the palms with no water droop as time goes on
	if not _won:
		var thirst := clampf((_t - DRY_FROM) / DRY_TIME, 0.0, 1.0)
		for pl in _plots:
			var palm: Node3D = pl.palm
			if palm == null:
				continue
			var wet: bool = (pl.water as Node3D).visible
			var k := 0.0 if wet else thirst
			palm.scale = palm.scale.lerp(Vector3(0.38, 0.38 * (1.0 - 0.22 * k), 0.38), clampf(dt * 2.0, 0, 1))
			palm.rotation.z = lerpf(palm.rotation.z, 0.18 * k, clampf(dt * 2.0, 0, 1))
	if _won or _busy:
		return
	if not _demo.is_empty():
		_turn(_demo.pop_front())
		return
	_idle_t += dt
	if _idle_t > HINT_AFTER:
		var cell = _wrong_piece()
		_hint_ring.visible = cell != null
		if cell != null:
			var pulse := 1.0 + 0.1 * sin(_t * 5.0)
			_hint_ring.position = cell_pos(cell) + Vector3(0, 0.3, 0)
			_hint_ring.scale = Vector3(pulse, 0.3, pulse)
