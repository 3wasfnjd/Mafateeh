class_name TableCampLevel
extends Node3D
## Level 4 on the table, «الوايت» (the water truck). Wordless. No buildings: a desert camp.
## Scene 4: dunes, the goat-hair tent, the sheep in their wire pen, camels waiting by an empty
## trough. On the packed sand in front of the tent the camp's cars are parked every which way
## (shases and datsuns, Motri's), and the water truck is boxed in among them. Its way out is to the
## right, towards the trough. Tap a car to pick it (the cells it can drive to light up), then
## tap one of them and it drives there, forwards or in reverse, never sideways. Get the truck
## out and it drives to the trough; the camels drink and the old man dances.
## (Rush-hour rules; this layout takes 11 moves at best.)
##
## Lives under Diorama.stage: positions are in the diorama's own metres (Godot axes).

signal level_won

const SFX := "res://audio/sfx/"
const CELL := 2.2
const N := 6
const EXIT_ROW := 2
const CENTRE := Vector3(0.0, 0.0, 1.0)   # middle of the grid (tools/blender/build_scene4.py: GRID)
const TROUGH_STOP := Vector3(9.3, 0.0, -0.1)
const OLD_MAN := Vector3(1.8, 0.0, -7.0)
const MODELS := {"shas": "res://assets/world/props/shas.glb", "datsun": "res://assets/world/props/datsun.glb",
	"wayit": "res://assets/world/props/wayit.glb"}
# [kind, colour, row, col, horizontal, facing forward (+x or +z)]; the first is the truck
const START := [
	["wayit", "", 2, 0, true, true],
	["shas", "", 0, 2, true, false],          # Motri's own beige
	["datsun", "", 5, 2, true, true],         # Motri's own white, hay in the bed
	["shas", "eeeeea", 5, 0, true, false],
	["datsun", "8fb3c9", 3, 4, false, true],
	["shas", "a9ada6", 3, 2, false, false],
	["datsun", "c96f5a", 0, 4, false, true],
	["shas", "", 4, 5, false, false],
	["shas", "eeeeea", 1, 2, false, true],
	["datsun", "d9b25a", 0, 0, false, false],
]
const BARRELS := [Vector2i(3, 3)]   # (row, col): water drums, they don't move
const DRIVE_SPEED := 4.5
const CAR_LEN := 2 * CELL * 0.93
const HINT_AFTER := 20.0
const BEIGE := Color("f1dcae")
const GOLD := Color("e6b85a")

var diorama: Diorama
var cars: Array = []        # {node, kind, r, c, h, len}
var selected := {}
var _moving := false
var _won := false
var _was_held := false
var _ray := []
var _stick_ready := true
var _sel_ring: MeshInstance3D
var _cells: Array = []      # glow squares on the cells the picked car can reach
var _hint_ring: MeshInstance3D
var _hint_car := {}
var _hint_dirty := true
var _hint_task := -1
var _hint_result: Array = []
var _idle_t := 0.0
var _t := 0.0
var _demo: Array = []


func setup(d: Diorama) -> void:
	diorama = d
	if diorama.shaib:
		diorama.shaib.position = OLD_MAN
		diorama.shaib.rotation.y = 0.0
		diorama.play_shaib("idle", "")
	for s in START:
		cars.append(_car(s))
	for b in BARRELS:
		_barrels(b)
	_sel_ring = _ring(1.0, BEIGE, 0.85)
	_sel_ring.visible = false
	_hint_ring = _ring(1.0, GOLD, 0.9)
	_hint_ring.visible = false


static func cell_pos(r: int, c: int) -> Vector3:
	return CENTRE + Vector3((c - 2.5) * CELL, 0, (r - 2.5) * CELL)


func _car_centre(car: Dictionary) -> Vector3:
	var a := cell_pos(car.r, car.c)
	var b := cell_pos(car.r + (0 if car.h else car.len - 1), car.c + (car.len - 1 if car.h else 0))
	return (a + b) / 2


func _car(s: Array) -> Dictionary:
	var n := Node3D.new()
	add_child(n)
	var ps := load(MODELS[s[0]]) as PackedScene
	if ps:
		var m: Node3D = ps.instantiate()
		n.add_child(m)
		# Motri's vehicles are 5-6 m long; each fills its two cells
		var length := _length(m)
		if length > 0.01:
			m.scale = Vector3.ONE * (CAR_LEN / length)
		if s[1] != "":
			_paint(m, Color(s[1]))
	var car := {"node": n, "kind": s[0], "r": s[2], "c": s[3], "h": s[4], "len": 2}
	n.position = _car_centre(car)
	var fwd: bool = s[5]
	n.rotation.y = (PI / 2 if fwd else -PI / 2) if s[4] else (0.0 if fwd else PI)
	return car


static func _length(root: Node3D) -> float:
	var zmax := 0.0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = (mi as MeshInstance3D).get_aabb()
		zmax = maxf(zmax, maxf(absf(a.position.z), absf(a.end.z)))
	return zmax * 2.0


## Recolours the body (faces on the paint_* material), keeping glass, lamps, tyres and the load.
static func _paint(root: Node, c: Color) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat and mat.resource_name.begins_with("paint") and mat is StandardMaterial3D:
				var m2: StandardMaterial3D = mat.duplicate()
				m2.vertex_color_use_as_albedo = false   # one flat body colour instead of Motri's
				m2.albedo_color = c
				(mi as MeshInstance3D).set_surface_override_material(i, m2)
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- the grid ---------------------------------------------------------------------------------

func _occupied(skip: Dictionary) -> Dictionary:
	var o := {}
	for car in cars:
		if car == skip:
			continue
		for k in car.len:
			o[Vector2i(car.r + (0 if car.h else k), car.c + (k if car.h else 0))] = true
	for b in BARRELS:
		o[b] = true
	return o


## Positions (row, col of its first cell) the car can drive to in a straight line.
func _reach(car: Dictionary) -> Array:
	var o := _occupied(car)
	var out: Array = []
	for d in [-1, 1]:
		var k := 1
		while true:
			var r: int = car.r + (0 if car.h else d * k)
			var c: int = car.c + (d * k if car.h else 0)
			var ok := true
			for i in car.len:
				var cell := Vector2i(r + (0 if car.h else i), c + (i if car.h else 0))
				if cell.x < 0 or cell.x >= N or cell.y < 0 or cell.y >= N or o.has(cell):
					ok = false
			if not ok:
				break
			out.append(Vector2i(r, c))
			k += 1
	return out


# --- input -----------------------------------------------------------------------------------

func aim(origin: Vector3, dir: Vector3) -> void:
	_ray = [origin, dir]


## The stick nudges the picked car one cell along its own line.
func move(v: Vector2) -> void:
	if v.length() < 0.5:
		_stick_ready = true
		return
	if not _stick_ready or selected.is_empty() or _moving or _won:
		return
	_stick_ready = false
	var axis := Vector2(1, 0) if selected.h else Vector2(0, 1)
	var along := v.dot(axis)
	if absf(along) < 0.35:
		return
	var step := 1 if along > 0 else -1
	var to := Vector2i(selected.r + (0 if selected.h else step), selected.c + (step if selected.h else 0))
	if to in _reach(selected):
		_drive(selected, to)
	else:
		_sfx("soft_reject", selected.node.position, -8.0)


func pointer(held: bool, p) -> void:
	var pressed := held and not _was_held
	_was_held = held
	if not pressed or _moving or _won:
		return
	_idle_t = 0.0
	var car := _pick_car()
	if not car.is_empty():
		if car == selected:
			_select({})
		else:
			_select(car)
			_sfx("tap", car.node.position, -6.0)
		return
	if selected.is_empty() or p == null:
		return
	# a cell in the picked car's line: drive as far towards it as the way is clear
	var q: Vector3 = p
	var best = null
	var best_d := INF
	for to in _reach(selected):
		var tmp := {"r": to.x, "c": to.y, "h": selected.h, "len": selected.len}
		var dd := Vector2(q.x, q.z).distance_to(Vector2(_car_centre(tmp).x, _car_centre(tmp).z))
		if dd < best_d:
			best_d = dd
			best = to
	if best != null and best_d < CELL * 1.2:
		_drive(selected, best)
	else:
		_sfx("soft_reject", q, -10.0)


func _pick_car() -> Dictionary:
	var id := TableKit.ray_pick(self, _ray, hover_boxes(), false)
	return cars[int(id)] if id != "" else {}


## The cars' boxes (for the pointer's ring, and picking): taps on the ground between them
## matter here, so no snapping onto a car the ray misses.
var assist := false
func hover_boxes() -> Dictionary:
	var out := {}
	for i in cars.size():
		var car: Dictionary = cars[i]
		var c := _car_centre(car)
		var half := Vector3(CELL * (0.95 if car.h else 0.45), 1.2, CELL * (0.45 if car.h else 0.95))
		out[str(i)] = AABB(c - Vector3(half.x, 0, half.z), Vector3(half.x * 2, 2.4, half.z * 2))
	return out


func _select(car: Dictionary) -> void:
	selected = car
	for q in _cells:
		q.queue_free()
	_cells.clear()
	_sel_ring.visible = not car.is_empty()
	if car.is_empty():
		return
	var c := _car_centre(car)
	_sel_ring.position = c + Vector3(0, 0.06, 0)
	_sel_ring.scale = Vector3(CELL * 1.05, 1.0, CELL * 1.05)
	for to in _reach(car):
		var tmp := {"r": to.x, "c": to.y, "h": car.h, "len": car.len}
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(CELL * (2.0 if car.h else 1.0), CELL * (1.0 if car.h else 2.0)) * 0.9
		q.mesh = pm
		q.material_override = _glow_mat(BEIGE, 0.22)
		add_child(q)
		q.position = _car_centre(tmp) + Vector3(0, 0.04, 0)
		_cells.append(q)


func _drive(car: Dictionary, to: Vector2i) -> void:
	_moving = true
	_hint_dirty = true
	_hint_ring.visible = false
	var from: Vector3 = car.node.position
	car.r = to.x
	car.c = to.y
	var dest := _car_centre(car)
	_sfx("bridge_move", from, -8.0)
	var tw := create_tween()
	tw.tween_property(car.node, "position", dest, maxf(0.35, from.distance_to(dest) / DRIVE_SPEED)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		_moving = false
		if car == cars[0] and car.c + car.len == N:
			_win()
		elif car == selected:
			_select(car))


func _win() -> void:
	_won = true
	_select({})
	var truck: Dictionary = cars[0]
	_sfx("success", truck.node.position, -2.0)
	var tw := create_tween()
	tw.tween_property(truck.node, "position", TROUGH_STOP, 1.6).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		_sfx("seq_3", TROUGH_STOP, -4.0)
		diorama.play_shaib("ardah", "")
		diorama.scare_birds(TROUGH_STOP, 5.0))
	tw.tween_interval(4.0)
	tw.tween_callback(func():
		_sfx("level_complete", TROUGH_STOP)
		level_won.emit())


# --- solving (hints and the demo) --------------------------------------------------------------

## The best next move from here: [car index, Vector2i to], or [] when stuck.
func best_move() -> Array:
	var path := _solve(_snapshot())
	return path[0] if not path.is_empty() else []


func _snapshot() -> Array:
	var s: Array = []
	for car in cars:
		s.append(Vector2i(car.r, car.c))
	return s


## Breadth-first search over the parked cars; returns the moves of a shortest way out.
## Reads only the cars' orientations besides `start`, so it can run on a worker thread.
func _solve(start: Array) -> Array:
	var key0 := str(start)
	var prev := {key0: null}
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var s: Array = queue[head]
		head += 1
		if s[0].y + 2 == N:
			var moves: Array = []
			var k := str(s)
			while prev[k] != null:
				var link: Array = prev[k]
				moves.push_front([link[1], link[2]])
				k = link[0]
			return moves
		var o := {}
		for i in s.size():
			for j in 2:
				o[Vector2i(s[i].x + (0 if cars[i].h else j), s[i].y + (j if cars[i].h else 0))] = i
		for b in BARRELS:
			o[b] = -1
		for i in s.size():
			var h: bool = cars[i].h
			for d in [-1, 1]:
				var k2 := 1
				while true:
					var nr: int = s[i].x + (0 if h else d * k2)
					var nc: int = s[i].y + (d * k2 if h else 0)
					var ok := true
					for j in 2:
						var cell := Vector2i(nr + (0 if h else j), nc + (j if h else 0))
						if cell.x < 0 or cell.x >= N or cell.y < 0 or cell.y >= N or (o.has(cell) and o[cell] != i):
							ok = false
					if not ok:
						break
					var ns := s.duplicate()
					ns[i] = Vector2i(nr, nc)
					var kk := str(ns)
					if not prev.has(kk):
						prev[kk] = [str(s), i, Vector2i(nr, nc)]
						queue.append(ns)
					k2 += 1
	return []


func demo() -> void:
	_demo = _solve(_snapshot())


func _process(dt: float) -> void:
	_t += dt
	if _won:
		return
	if not _moving and not _demo.is_empty():
		var mv: Array = _demo.pop_front()
		_drive(cars[mv[0]], mv[1])
		return
	_idle_t += dt
	if _idle_t > HINT_AFTER and not _moving:
		# the search takes a moment on the headset: run it off the main thread
		if _hint_dirty and _hint_task < 0:
			_hint_dirty = false
			var snap := _snapshot()
			_hint_result = []
			_hint_task = WorkerThreadPool.add_task(func():
				var path := _solve(snap)
				_hint_result = path[0] if not path.is_empty() else [])
		if _hint_task >= 0 and WorkerThreadPool.is_task_completed(_hint_task):
			WorkerThreadPool.wait_for_task_completion(_hint_task)
			_hint_task = -1
			_hint_car = cars[_hint_result[0]] if not _hint_result.is_empty() and not _hint_dirty else {}
		_hint_ring.visible = not _hint_car.is_empty()
		if _hint_ring.visible:
			var pulse := 1.0 + 0.1 * sin(_t * 5.0)
			_hint_ring.position = _car_centre(_hint_car) + Vector3(0, 0.08, 0)
			_hint_ring.scale = Vector3(CELL * pulse, 1.0, CELL * pulse)
	if _sel_ring.visible:
		var k := 1.0 + 0.05 * sin(_t * 3.0)
		_sel_ring.scale = Vector3(CELL * 1.05 * k, 1.0, CELL * 1.05 * k)


# --- props and helpers ---------------------------------------------------------------------------

## Blue water drums standing in a cell: they don't move.
func _barrels(cell: Vector2i) -> void:
	var c := cell_pos(cell.x, cell.y)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("2f5f8f")
	m.roughness = 0.6
	var lid := StandardMaterial3D.new()
	lid.albedo_color = Color("d8d6d0")
	for o in [Vector2(-0.45, -0.4), Vector2(0.45, -0.35), Vector2(0.0, 0.45)]:
		var cy := CylinderMesh.new()
		cy.top_radius = 0.38
		cy.bottom_radius = 0.38
		cy.height = 1.05
		cy.radial_segments = 12
		var mi := MeshInstance3D.new()
		mi.mesh = cy
		mi.material_override = m
		mi.position = c + Vector3(o.x, 0.525, o.y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var top := CylinderMesh.new()
		top.top_radius = 0.3
		top.bottom_radius = 0.3
		top.height = 0.03
		var t2 := MeshInstance3D.new()
		t2.mesh = top
		t2.material_override = lid
		t2.position = c + Vector3(o.x, 1.06, o.y)
		add_child(t2)


static func _glow_mat(c: Color, alpha := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _ring(r: float, c: Color, alpha: float) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r * 0.94
	t.outer_radius = r
	t.rings = 40
	t.ring_segments = 4
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.material_override = _glow_mat(c, alpha)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _sfx(name: String, pos: Vector3, db := 0.0) -> void:
	TableKit.sfx(self, name, pos, db)
