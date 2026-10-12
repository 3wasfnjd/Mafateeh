class_name LevelView
extends Node3D
## Visual representation of one level, built from LevelData and animated from
## PuzzleState. Holds no rules: everything it shows is read from the state.

signal mechanism_changed(kind: String, opened: bool, at: Vector3)

const H := LevelData.UPPER_HEIGHT

var state: PuzzleState
var def: Dictionary
var obj_nodes: Dictionary = {}  # object index -> {root: Node3D, ...}
var mech_nodes: Array = []  # parallel to state.mechanisms
var crate_nodes: Array = []
var plate_nodes: Array = []
var lamp_nodes: Array = []
var clue_nodes: Array = []
var beam_nodes: Array = []
var roof_nodes: Array = []
var pan_nodes: Array = []
var scale_beam: Node3D
var exit_gate: Node3D
var exit_open := 0.0
var t := 0.0
var water_nodes: Array = []
var lantern_lights: Array = []
var foliage: Array = []
var wind := 0.3
var _was_solved := false
var _was_light := false
var _was_balanced := false


func surface(x: float, z: float) -> float:
	return LevelData.surface_y(def, x, z)


func build(s: PuzzleState) -> void:
	state = s
	def = s.def
	_build_floor()
	_build_perimeter()
	_build_exit()
	if def.get("storeys", false):
		_build_storeys()
	for w in def.walls:
		_wall(Vector3(w[0], surface(w[0], w[1]), w[1]), w[2], w[3], 0.78)
	if def.get("moat", false):
		_build_moat()
	if def.get("pool_room", false):
		_build_pool_room()
	for i in state.mechanisms.size():
		mech_nodes.append(_build_mechanism(state.mechanisms[i]))
	for i in state.crates.size():
		_build_crate(i)
	for o in state.objects:
		obj_nodes[o.index] = _build_object(o)
	if def.has("circuit"):
		_build_lamp_panel()
	if def.has("sequence"):
		_build_clue_tablet()
	if def.has("optics"):
		_build_optics()
	if def.has("balance"):
		_build_balance_frame()
	for r in def.get("roofs", []):
		_build_roof(r)
	_build_vegetation()
	_was_solved = state.solved
	_was_light = state.light
	_was_balanced = state.balanced()
	sync(0.0)


# --- static architecture ---------------------------------------------------------

func _build_floor() -> void:
	# Raised earthen plinth the miniature sits on.
	var base := Kit.add(self, Kit.box(Vector3(10.0, 0.36, 9.3)), Kit.mat("plaster"), Vector3(0, -0.24, -0.3))
	base.name = "Plinth"
	Kit.add(self, Kit.box(Vector3(10.15, 0.06, 9.45)), Kit.mat("plaster_top"), Vector3(0, -0.42, -0.3))
	Kit.add(self, Kit.box(Vector3(9.9, 0.03, 9.2)), Kit.mat("sand"), Vector3(0, -0.05, -0.3), false)
	# Paving: one multimesh, subtle per-tile tone variation.
	var tiles: Array = []
	for x in 8:
		for z in 7:
			var px := x - 3.5
			var pz := z - 3.0
			if def.get("storeys", false) and pz < 0.5:
				continue
			if def.get("moat", false) and absf(pz) < 0.6:
				continue  # water channel
			if def.get("pool_room", false) and px > -3.6 and px < -0.5 and pz > -2.6 and pz < -0.3:
				continue  # pool basin
			tiles.append(Vector3(px, -0.015, pz))
	if def.get("storeys", false):
		for x in 8:
			for z in 3:
				tiles.append(Vector3(x - 3.5, H - 0.015, -1.36 - z * 0.83 - 0.0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var tile_mesh := Kit.piece("floor_tile")
	mm.mesh = tile_mesh if tile_mesh != null else Kit.box(Vector3(0.975, 0.15, 0.975))
	mm.instance_count = tiles.size()
	for i in tiles.size():
		var p: Vector3 = tiles[i]
		var sz := Vector3(1, 1, 0.83 if p.y > 1.0 else 1.0)
		var b := Basis.from_scale(sz)
		if tile_mesh != null:
			b = b.rotated(Vector3.UP, (i * 7 % 4) * PI / 2)
		mm.set_instance_transform(i, Transform3D(b, p))
		var v := 1.0 + float((int(p.x * 17.0 + p.z * 13.0) % 7) - 3) * 0.012
		mm.set_instance_color(i, Color(v, v * 0.995, v * 0.985))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var stone := Kit.mat("stone").duplicate() as StandardMaterial3D
	stone.vertex_color_use_as_albedo = true
	mmi.material_override = stone
	mmi.name = "Paving"
	add_child(mmi)


func _wall(center: Vector3, w: float, d: float, h: float, decorate := true) -> Node3D:
	## Straight mud wall with rounded end posts that close every joint.
	var root := Node3D.new()
	root.position = center
	add_child(root)
	var along_x := w >= d
	var length := w if along_x else d
	var thick := d if along_x else w
	var body := Kit.add_piece(root, "wall_segment", Kit.box(Vector3(1, 1, 1)), Kit.mat("plaster"), Vector3(0, h / 2.0, 0))
	var core := maxf(length - thick, 0.01)
	body.scale = Vector3(core if along_x else thick, h, thick if along_x else core)
	if Kit.piece("wall_segment") != null and not along_x:
		body.rotation.y = PI / 2
		body.scale = Vector3(core, h, thick)
	for side in [-1, 1]:
		var off := Vector3((length - thick) / 2.0 * side, 0, 0) if along_x else Vector3(0, 0, (length - thick) / 2.0 * side)
		var post := Kit.add_piece(root, "wall_post", Kit.cylinder(thick / 2.0, thick / 2.0, 1.0, 14), Kit.mat("plaster"), off + Vector3(0, h / 2.0, 0))
		post.scale = Vector3(thick, h, thick) if Kit.piece("wall_post") != null else Vector3(1, h, 1)
	# Rounded coping cap along the top.
	var cap := Kit.add(root, Kit.box(Vector3(1, 1, 1)), Kit.mat("plaster_top"), Vector3(0, h + 0.02, 0))
	cap.scale = Vector3(core + 0.02 if along_x else thick + 0.04, 0.05, thick + 0.04 if along_x else core + 0.02)
	if decorate and length > 1.6:
		# Small triangular vents, a hallmark of Najdi walls, on both faces.
		var n := int(length / 1.1)
		for i in n:
			var a := (i + 0.5) / n - 0.5
			for face in [-1, 1]:
				var p := Vector3(a * (length - thick), h * 0.66, face * (thick / 2.0 + 0.002))
				if not along_x:
					p = Vector3(face * (thick / 2.0 + 0.002), h * 0.66, a * (length - thick))
				var vent := Kit.add_piece(root, "vent_triangle", Kit.prism(Vector3(0.13, 0.13, 0.02)), Kit.mat("wood"), p)
				vent.rotation.y = 0.0 if along_x else PI / 2
	return root


func _build_perimeter() -> void:
	var back_h := 1.05
	var side_h := 0.95
	var front_h := 0.42
	# Side walls.
	for sx in [-1, 1]:
		_wall(Vector3(sx * 4.09, 0, 0), 0.27, 7.18, side_h)
	# Front (toward the player) kept low for a clear view.
	_wall(Vector3(0, 0, 3.59), 8.18, 0.27, front_h, false)
	# Back wall with a gap for the exit gatehouse.
	var ey := LevelData.exit_y(def)
	var gap_lo := LevelData.EXIT_X - 0.95
	var gap_hi := LevelData.EXIT_X + 0.95
	var left_len := gap_lo + 4.09 + 0.135
	_wall(Vector3((-4.09 - 0.135 + gap_lo) / 2.0, ey, -3.59), left_len, 0.27, back_h)
	var right_len := 4.09 + 0.135 - gap_hi
	_wall(Vector3((gap_hi + 4.09 + 0.135) / 2.0, ey, -3.59), right_len, 0.27, back_h)
	# Corner towers: rounded, slightly taller, with stepped crenellations.
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var hh := front_h + 0.12 if sz > 0 else back_h + 0.25
			var y0 := ey if (sz < 0 and def.get("storeys", false)) else 0.0
			var p := Vector3(sx * 4.09, y0 + hh / 2.0, sz * 3.59)
			var tower := Kit.add_piece(self, "corner_tower", Kit.cylinder(0.24, 0.27, hh, 18), Kit.mat("plaster"), p)
			if Kit.has_piece("corner_tower"):
				tower.scale = Vector3(0.54, hh, 0.54)
			Kit.add(self, Kit.cylinder(0.27, 0.27, 0.05, 18), Kit.mat("plaster_top"), p + Vector3(0, hh / 2.0 + 0.02, 0))
	# Crenellations (shurfat) along the back wall.
	for i in 14:
		var x := -3.85 + i * 0.58
		if x > gap_lo - 0.1 and x < gap_hi + 0.1:
			continue
		var c := Kit.add_piece(self, "crenel", Kit.prism(Vector3(0.22, 0.22, 0.2)), Kit.mat("plaster_top"),
			Vector3(x, ey + back_h + 0.14, -3.59))
		c.name = "Crenel"
	# Wooden beam ends (mirzam) poking out of the back wall.
	for i in 6:
		var x := -3.5 + i * 1.0
		if x > gap_lo - 0.2 and x < gap_hi + 0.2:
			continue
		var b := Kit.add(self, Kit.box(Vector3(0.07, 0.07, 0.36)), Kit.mat("wood"), Vector3(x, ey + back_h - 0.18, -3.44))
		b.name = "BeamEnd"


func _build_exit() -> void:
	var ey := LevelData.exit_y(def)
	var ex := LevelData.EXIT_X
	var gh := Node3D.new()
	gh.name = "Gatehouse"
	gh.position = Vector3(ex, ey, -3.59)
	add_child(gh)
	for sx in [-1, 1]:
		Kit.add_piece(gh, "gate_pillar", Kit.box(Vector3(0.36, 1.55, 0.5)), Kit.mat("plaster"), Vector3(sx * 0.82, 0.775, 0))
	Kit.add(gh, Kit.box(Vector3(2.0, 0.34, 0.56)), Kit.mat("plaster"), Vector3(0, 1.62, 0))
	Kit.add(gh, Kit.box(Vector3(2.08, 0.06, 0.62)), Kit.mat("plaster_top"), Vector3(0, 1.82, 0))
	Kit.add(gh, Kit.box(Vector3(1.5, 0.1, 0.1)), Kit.mat("wood"), Vector3(0, 1.4, 0.27))
	for i in 5:
		Kit.add(gh, Kit.prism(Vector3(0.22, 0.22, 0.24)), Kit.mat("plaster_top"), Vector3(-0.8 + i * 0.4, 1.96, 0))
	# Tunnel behind the gate.
	for sx in [-1, 1]:
		Kit.add(gh, Kit.box(Vector3(0.25, 1.3, 1.2)), Kit.mat("plaster"), Vector3(sx * 0.56, 0.65, -0.75))
	Kit.add(gh, Kit.box(Vector3(1.37, 0.2, 1.2)), Kit.mat("plaster"), Vector3(0, 1.36, -0.75))
	Kit.add(gh, Kit.box(Vector3(0.9, 0.08, 1.4)), Kit.mat("stone"), Vector3(0, -0.02, -0.7))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("2a1d14")
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	Kit.add(gh, Kit.box(Vector3(0.9, 1.3, 0.04)), dark, Vector3(0, 0.65, -1.33))
	# Wooden double gate, opens when the level is solved.
	exit_gate = Node3D.new()
	exit_gate.name = "ExitGate"
	gh.add_child(exit_gate)
	for side in [-1, 1]:
		var hinge := Node3D.new()
		hinge.position = Vector3(side * 0.62, 0, 0.12)
		hinge.name = "Leaf" + str(side)
		exit_gate.add_child(hinge)
		_door_leaf(hinge, -side * 0.31, 0.62, 1.3)
	if not def.has("circuit") and not def.has("sequence"):  # otherwise the puzzle sign sits here
		var plaque := Kit.emblem(gh, 1, Kit.mat("brass"), Vector3(0, 1.62, 0.3), 0.12)
		plaque.rotation.x = PI / 2


func _door_leaf(hinge: Node3D, offset_x: float, width: float, height: float) -> void:
	var leaf := Kit.add_piece(hinge, "door_leaf", Kit.box(Vector3(width, height, 0.07)), Kit.mat("wood"), Vector3(offset_x, height / 2.0, 0))
	if Kit.piece("door_leaf") != null:
		leaf.scale = Vector3(width / 0.6, height / 1.3, 1.0)
	else:
		# Planks and iron studs give the fallback a hand-made read.
		for j in 3:
			Kit.add(hinge, Kit.box(Vector3(width * 0.96, 0.06, 0.09)), Kit.mat("wood_light"),
				Vector3(offset_x, height * (0.2 + j * 0.3), 0.01))
		for j in 3:
			Kit.add(hinge, Kit.sphere(0.022, 6), Kit.mat("iron"), Vector3(offset_x + width * 0.3, height * (0.2 + j * 0.3), 0.06))


func _build_storeys() -> void:
	# Two-storey house: solid lower rooms carry an upper terrace.
	var mass := Kit.add(self, Kit.box(Vector3(8.02, H, 2.54)), Kit.mat("plaster"), Vector3(0, H / 2.0, -2.23))
	mass.name = "LowerRooms"
	Kit.add(self, Kit.box(Vector3(8.1, 0.06, 2.6)), Kit.mat("plaster_top"), Vector3(0, H - 0.09, -2.23))
	# Facade details on the lower rooms: doors, windows, beam ends.
	for x in [-1.6, 1.3]:
		var d := Node3D.new()
		d.position = Vector3(x, 0, -0.95)
		add_child(d)
		_door_leaf(d, 0, 0.62, 1.15)
		Kit.add(d, Kit.box(Vector3(0.8, 0.08, 0.12)), Kit.mat("wood"), Vector3(0, 1.22, 0.02))
	for x in [-0.2, 2.4, 3.4]:
		Kit.add(self, Kit.box(Vector3(0.32, 0.36, 0.04)), Kit.mat("wood"), Vector3(x, 1.25, -0.95))
		Kit.add(self, Kit.prism(Vector3(0.16, 0.14, 0.03)), Kit.mat("wood"), Vector3(x, 1.62, -0.95))
	for i in 9:
		Kit.add(self, Kit.box(Vector3(0.07, 0.07, 0.3)), Kit.mat("wood"), Vector3(-3.6 + i * 0.9, H - 0.28, -0.88))
	# Parapet along the terrace edge, open where stairs arrive.
	var spans: Array = []
	for s in def.stairs:
		spans.append([s[0] - 0.65, s[0] + 0.65])
	spans.sort_custom(func(a, b): return a[0] < b[0])
	var left := -4.0
	for sp in spans + [[4.0, 4.0]]:
		if sp[0] > left + 0.05:
			var w: float = sp[0] - left
			_wall(Vector3((left + sp[0]) / 2.0, H, -1.03), w, 0.16, 0.32, false)
		left = sp[1]
	# Stairs.
	for s in def.stairs:
		var x: float = s[0]
		for i in 12:
			var h: float = (i + 1) / 12.0 * H
			var zc := 0.95 - (i + 0.5) * 1.9 / 12.0
			Kit.add(self, Kit.box(Vector3(1.28, h - 0.03, 0.165)), Kit.mat("plaster"), Vector3(x, (h - 0.03) / 2.0, zc))
			Kit.add(self, Kit.box(Vector3(1.24, 0.035, 0.175)), Kit.mat("wood_light"), Vector3(x, h - 0.0125, zc))
		for side in [-1, 1]:
			var rail := Node3D.new()
			rail.position = Vector3(x + side * 0.69, 0, 0)
			add_child(rail)
			# Sloped mud balustrade following the steps.
			var m := Kit.add(rail, Kit.box(Vector3(0.12, 0.34, 2.15)), Kit.mat("plaster"), Vector3(0, H / 2.0 + 0.17, 0))
			m.rotation.x = atan2(H, 1.9)


func _build_moat() -> void:
	# Recessed water channel (falaj) with stone coping on both banks.
	Kit.add(self, Kit.box(Vector3(7.97, 0.02, 1.2)), Kit.mat("pool_tile"), Vector3(0, -0.022, 0), false)
	var water := Kit.add(self, Kit.box(Vector3(7.97, 0.02, 1.2)), Kit.mat("water"), Vector3(0, 0.012, 0), false)
	water.name = "Moat"
	water_nodes.append(water)
	for z in [-0.56, 0.56]:
		Kit.add(self, Kit.box(Vector3(7.97, 0.16, 0.1)), Kit.mat("stone_dark"), Vector3(0, -0.02, z))
		Kit.add(self, Kit.box(Vector3(7.97, 0.03, 0.14)), Kit.mat("stone"), Vector3(0, 0.07, z))


func _build_pool_room() -> void:
	# Arched passages through the inner walls.
	for a in [[-2.6, 0.8], [2.6, 0.8], [2.8, -1.1]]:
		var root := Node3D.new()
		root.position = Vector3(a[0], 0, a[1])
		add_child(root)
		for side in [-1, 1]:
			Kit.add(root, Kit.box(Vector3(0.15, 0.95, 0.3)), Kit.mat("plaster"), Vector3(side * 0.775, 0.475, 0))
		Kit.add_piece(root, "arch", Kit.box(Vector3(1.7, 0.22, 0.32)), Kit.mat("plaster"), Vector3(0, 1.0, 0))
	# Courtyard pool: tiled basin, coping, water and a stepping-stone lane.
	Kit.add(self, Kit.box(Vector3(2.9, 0.02, 2.1)), Kit.mat("pool_tile"), Vector3(-2.05, -0.022, -1.45), false)
	var water := Kit.add(self, Kit.box(Vector3(2.86, 0.02, 2.06)), Kit.mat("water"), Vector3(-2.05, 0.012, -1.45), false)
	water_nodes.append(water)
	for x in [-3.55, -0.55]:
		Kit.add_piece(self, "pool_edge", Kit.box(Vector3(0.15, 0.19, 2.3)), Kit.mat("stone_dark"), Vector3(x, 0.095, -1.45))
	for z in [-2.55, -0.35]:
		for xw in [[-3.08, 0.92], [-1.02, 0.92]]:
			Kit.add(self, Kit.box(Vector3(xw[1], 0.19, 0.15)), Kit.mat("stone_dark"), Vector3(xw[0], 0.095, z))
	# Brass rail of the pool steps.
	for z in [-1.65, -1.25]:
		Kit.add(self, Kit.box(Vector3(0.04, 0.3, 0.04)), Kit.mat("brass"), Vector3(-0.42, 0.3, z))
	# Inset guide from the socket toward the stones.
	Kit.add(self, Kit.box(Vector3(0.8, 0.018, 0.065)), Kit.mat("brass"), Vector3(-2.76, 0.07, -0.12), false)


func _build_roof(r: Array) -> void:
	var root := Node3D.new()
	root.name = "Roof"
	root.position = Vector3(r[0], 1.32, r[1])
	add_child(root)
	Kit.add(root, Kit.box(Vector3(r[2], 0.12, r[3])), Kit.mat("plaster"), Vector3.ZERO)
	Kit.add(root, Kit.box(Vector3(r[2] + 0.08, 0.05, r[3] + 0.08)), Kit.mat("plaster_top"), Vector3(0, 0.08, 0))
	var n := int(r[2] / 0.4)
	for i in n:
		Kit.add(root, Kit.box(Vector3(0.06, 0.06, 0.18)), Kit.mat("wood"),
			Vector3(-r[2] / 2.0 + (i + 0.5) * r[2] / n, -0.03, r[3] / 2.0 + 0.06))
	# Corner posts carry the roof.
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			Kit.add(root, Kit.cylinder(0.07, 0.08, 1.3, 10), Kit.mat("plaster"),
				Vector3(sx * (r[2] / 2.0 - 0.08), -0.66, sz * (r[3] / 2.0 - 0.08)))
	roof_nodes.append({"node": root, "rect": r, "fade": 1.0})


func _build_vegetation() -> void:
	## Palms, a lote tree and shrubs stand on the planting strip outside the
	## walls: they frame the courtyard without blocking the hero, clues or rays.
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + state.level
	var spots := [["palm", Vector3(-4.62, 0, -3.95)], ["palm_small", Vector3(4.62, 0, -2.3)],
		["tree", Vector3(-4.6, 0, 1.2)], ["shrub", Vector3(4.6, 0, 2.6)], ["shrub", Vector3(-4.6, 0, 3.7)],
		["palm_small", Vector3(-2.6, 0, -4.45)], ["shrub", Vector3(3.6, 0, -4.4)]]
	for sp in spots:
		if rng.randf() < 0.18 and sp[0] == "shrub":
			continue
		var y0 := -0.05
		var mi := Kit.add_piece(self, sp[0], Kit.cylinder(0.08, 0.1, 1.5, 6), Kit.mat("palm_trunk"), sp[1] + Vector3(0, y0, 0))
		mi.rotation.y = rng.randf() * TAU
		mi.scale = Vector3.ONE * rng.randf_range(0.9, 1.1)
		mi.set_meta("sway", rng.randf() * TAU)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		foliage.append(mi)
	# Lanterns on the gatehouse pillars (lit at dusk and night).
	var ey := LevelData.exit_y(def)
	for side in [-1, 1]:
		Kit.add_piece(self, "lantern", Kit.box(Vector3(0.1, 0.25, 0.1)), Kit.mat("glow"),
			Vector3(LevelData.EXIT_X + side * 0.82, ey + 1.56, -3.3))


# --- mechanisms ------------------------------------------------------------------------

func _build_mechanism(m: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.position = Vector3(m.x, surface(m.x, m.z), m.z)
	add_child(root)
	var out := {"root": root, "kind": m.kind, "open": 0.0, "leaves": []}
	match m.kind:
		"door":
			var w: float = m.w
			for side in [-1, 1]:
				var post := Kit.add(root, Kit.box(Vector3(0.14, 1.0, 0.36)), Kit.mat("plaster"), Vector3(side * (w / 2.0 + 0.02), 0.5, 0))
				post.name = "Post"
				var hinge := Node3D.new()
				hinge.position = Vector3(side * (w / 2.0 - 0.05), 0, 0)
				root.add_child(hinge)
				_door_leaf(hinge, -side * (w / 4.0 - 0.02), w / 2.0 - 0.06, 0.82)
				out.leaves.append([hinge, side])
			Kit.add(root, Kit.box(Vector3(w + 0.34, 0.1, 0.36)), Kit.mat("wood"), Vector3(0, 0.98, 0))
			# Plaque shows what opens this door, so it never depends on colour alone.
			# Lock doors show their keyhole instead of a plaque.
			if m.condition != "lock":
				var icon: int = {"circuit": 0, "dials": 2, "balance": 1}.get(m.condition, 0)
				var plaque := Kit.add(root, Kit.box(Vector3(0.3, 0.3, 0.05)), Kit.mat("brass_dark"), Vector3(0, 1.2, 0.0))
				plaque.name = "Plaque"
				var e := Kit.emblem(root, icon, Kit.mat("brass"), Vector3(0, 1.2, 0.04), 0.09)
				e.rotation.x = PI / 2
			if m.condition == "lock":
				Kit.add(root, Kit.box(Vector3(0.18, 0.22, 0.08)), Kit.mat("brass_dark"), Vector3(0, 0.5, 0.08))
				Kit.add(root, Kit.cylinder(0.025, 0.025, 0.02, 10), Kit.mat("iron"), Vector3(0, 0.53, 0.13)).rotation.x = PI / 2
		"bridge":
			var planks := Node3D.new()
			root.add_child(planks)
			for j in 6:
				Kit.add(planks, Kit.box(Vector3(1.25, 0.11, 0.22)), Kit.mat("wood_light"), Vector3(0, 0.08, -0.6 + j * 0.24))
			for side in [-1, 1]:
				Kit.add(planks, Kit.box(Vector3(0.05, 0.05, 1.5)), Kit.mat("wood"), Vector3(side * 0.56, 0.18, 0))
			var icon: int = {"choice": 1, "litChoice": 1, "circuit": 0, "final": 3}.get(m.condition, 1)
			out["planks"] = planks
			out["icon"] = icon
		"stairs":
			var gate := Node3D.new()
			root.add_child(gate)
			for i in range(-2, 3):
				Kit.add(gate, Kit.box(Vector3(0.07, 0.75, 0.09)), Kit.mat("wood"), Vector3(i * 0.23, 0.43, 0))
			Kit.add(gate, Kit.box(Vector3(1.24, 0.08, 0.09)), Kit.mat("wood"), Vector3(0, 0.8, 0))
			Kit.add(gate, Kit.box(Vector3(1.24, 0.08, 0.09)), Kit.mat("wood"), Vector3(0, 0.2, 0))
			var icon: int = {"circuit": 0, "light": 1, "choice": 1, "keyChoice": 3}.get(m.condition, 0)
			if icon != 3:  # no cross ("plus") marks above gates
				var e := Kit.emblem(gate, icon, Kit.mat("brass"), Vector3(0, 0.95, 0.04), 0.09)
				e.rotation.x = PI / 2
			out["gate"] = gate
		"pool_bridge":
			var stones := Node3D.new()
			root.add_child(stones)
			for i in 5:
				var st := Kit.add_piece(stones, "stepping_stone", Kit.cylinder(0.38, 0.42, 0.12, 12), Kit.mat("stone"), Vector3(0, 0.06, -0.85 + i * 0.425))
				st.scale = Vector3(1.2, 1, 0.9)
			out["stones"] = stones
	return out


func _build_crate(i: int) -> void:
	var c: Dictionary = state.crates[i]
	var root := Node3D.new()
	add_child(root)
	var body := Kit.add_piece(root, "crate", Kit.box(Vector3(1.0, 1.0, 1.0)), Kit.mat("wood_light"), Vector3(0, 0.55, 0))
	if Kit.piece("crate") == null:
		for a in [-1, 1]:
			for b in [-1, 1]:
				Kit.add(root, Kit.box(Vector3(1.04, 0.08, 0.08)), Kit.mat("wood"), Vector3(0, 0.55 + a * 0.46, b * 0.48))
				Kit.add(root, Kit.box(Vector3(0.08, 0.08, 1.04)), Kit.mat("wood"), Vector3(a * 0.48, 0.55 + b * 0.46, 0))
				Kit.add(root, Kit.box(Vector3(0.08, 1.0, 0.08)), Kit.mat("wood"), Vector3(a * 0.48, 0.55, b * 0.48))
	var shadow := Kit.add(root, Kit.box(Vector3(1.7, 0.002, 1.7)), Kit.mat("shadow_blob"), Vector3(0, 0.065, 0), false)
	shadow.name = "Shadow"
	crate_nodes.append(root)
	# Pressure plate at the crate's destination, with a guide line from the push side.
	var plate := Node3D.new()
	plate.position = Vector3(c.to.x, 0, c.to.y)
	add_child(plate)
	Kit.add(plate, Kit.box(Vector3(0.95, 0.06, 0.95)), Kit.mat("brass_dark"), Vector3(0, 0.07, 0))
	var top := Kit.add(plate, Kit.box(Vector3(0.84, 0.06, 0.84)), Kit.mat("brass"), Vector3(0, 0.1, 0))
	var arrow := Kit.add(plate, Kit.prism(Vector3(0.36, 0.3, 0.03)), Kit.mat("brass_dark"), Vector3(0, 0.14, 0))
	arrow.rotation = Vector3(-PI / 2, 0, -atan2(c.dir.x, -c.dir.y))
	plate_nodes.append({"root": plate, "top": top})
	var from := Vector2(c.pos)
	var to: Vector2 = c.to
	var mid: Vector2 = (from + to) / 2.0
	var length: float = from.distance_to(c.to)
	var line := Kit.add(self, Kit.box(Vector3(0.08, 0.012, length)), Kit.mat("brass"), Vector3(mid.x, 0.066, mid.y), false)
	line.rotation.y = atan2(c.dir.x, c.dir.y)


func _build_object(o: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.position = Vector3(o.x, surface(o.x, o.z), o.z)
	add_child(root)
	var n := {"root": root, "type": o.type}
	match o.type:
		"key":
			var item := Node3D.new()
			item.position.y = 0.56
			root.add_child(item)
			var c := Kit.mat("brass")
			if Kit.has_piece("key"):
				Kit.add_piece(item, "key", null, c)
			else:
				Kit.add(item, Kit.torus(0.09, 0.15), c, Vector3(0, 0.16, 0)).rotation.x = PI / 2
				Kit.add(item, Kit.box(Vector3(0.07, 0.36, 0.07)), c, Vector3(0, -0.08, 0))
				Kit.add(item, Kit.box(Vector3(0.16, 0.06, 0.07)), c, Vector3(0.07, -0.2, 0))
				Kit.add(item, Kit.box(Vector3(0.12, 0.06, 0.07)), c, Vector3(0.05, -0.1, 0))
			Kit.emblem(root, o.id, Kit.mat("puzzle_%d" % o.id), Vector3(0, 0.08, 0), 0.22)
			Kit.add(root, Kit.box(Vector3(0.7, 0.002, 0.7)), Kit.mat("shadow_blob"), Vector3(0, 0.07, 0), false)
			n["item"] = item
		"gem":
			var item := Node3D.new()
			item.position.y = 0.58
			root.add_child(item)
			Kit.add(item, Kit.octahedron(0.2), Kit.mat("glow"))
			var ring := Kit.add(root, Kit.torus(0.28, 0.33), Kit.mat("brass"), Vector3(0, 0.1, 0))
			ring.name = "Ring"
			Kit.add(root, Kit.box(Vector3(0.7, 0.002, 0.7)), Kit.mat("shadow_blob"), Vector3(0, 0.07, 0), false)
			n["item"] = item
		"lever":
			Kit.add(root, Kit.box(Vector3(0.58, 0.14, 0.55)), Kit.mat("stone_dark"), Vector3(0, 0.15, 0))
			var arm := Node3D.new()
			arm.position.y = 0.2
			root.add_child(arm)
			Kit.add(arm, Kit.box(Vector3(0.08, 0.5, 0.08)), Kit.mat("wood"), Vector3(0, 0.25, 0))
			Kit.add(arm, Kit.sphere(0.11, 10), Kit.mat("brass"), Vector3(0, 0.52, 0))
			for side in [-1, 1]:
				var e := Kit.emblem(root, 1, Kit.mat("brass"), Vector3(side * 0.45, 0.1, 0), 0.11)
				e.rotation.y = side * PI / 2
			n["arm"] = arm
		"circuit":
			Kit.add(root, Kit.box(Vector3(0.62, 0.16, 0.62)), Kit.mat("stone_dark"), Vector3(0, 0.1, 0))
			var cap := Kit.add(root, Kit.box(Vector3(0.46, 0.1, 0.46)), Kit.mat("stone"), Vector3(0, 0.22, 0))
			var cfg: Dictionary = def.circuit
			for j in cfg.count:
				if o.mask & (1 << j):
					Kit.emblem(root, j, Kit.mat("puzzle_%d" % j), Vector3((j - (cfg.count - 1) / 2.0) * 0.12, 0.29, 0), 0.042)
			n["cap"] = cap
		"sequence":
			var cap := Kit.add(root, Kit.box(Vector3(0.7, 0.1, 0.7)), Kit.mat("puzzle_%d" % o.id), Vector3(0, 0.1, 0))
			Kit.add(root, Kit.box(Vector3(0.78, 0.06, 0.78)), Kit.mat("stone_dark"), Vector3(0, 0.05, 0))
			Kit.emblem(root, o.id, Kit.mat("plaster_top"), Vector3(0, 0.17, 0), 0.17)
			n["cap"] = cap
		"portal":
			Kit.add(root, Kit.cylinder(0.44, 0.46, 0.08, 20), Kit.mat("stone_dark"), Vector3(0, 0.08, 0))
			for r in [0.22, 0.36]:
				Kit.add(root, Kit.torus(r - 0.03, r), Kit.mat("puzzle_2"), Vector3(0, 0.13, 0))
			var glow := Kit.add(root, Kit.sphere(0.07, 10), Kit.mat("glow"), Vector3(0, 0.2, 0))
			n["glow"] = glow
		"mirror":
			Kit.add(root, Kit.cylinder(0.3, 0.35, 0.12, 18), Kit.mat("stone_dark"), Vector3(0, 0.08, 0))
			var pivot := Node3D.new()
			root.add_child(pivot)
			Kit.add(pivot, Kit.box(Vector3(0.6, 0.46, 0.06)), Kit.mat("glass"), Vector3(0, 0.45, 0))
			Kit.add(pivot, Kit.box(Vector3(0.66, 0.05, 0.08)), Kit.mat("brass"), Vector3(0, 0.69, 0))
			Kit.add(pivot, Kit.box(Vector3(0.66, 0.05, 0.08)), Kit.mat("brass"), Vector3(0, 0.21, 0))
			Kit.add(root, Kit.box(Vector3(0.08, 0.14, 0.08)), Kit.mat("brass"), Vector3(0, 0.2, 0))
			n["pivot"] = pivot
		"dial":
			var cfg: Dictionary = def.dials
			Kit.add(root, Kit.cylinder(0.39, 0.43, 0.14, 24), Kit.mat("stone_dark"), Vector3(0, 0.1, 0))
			for j in 4:
				var a := j * PI / 2.0
				Kit.add(root, Kit.box(Vector3(0.05, 0.03, 0.1)), Kit.mat("plaster_top"), Vector3(sin(a) * 0.32, 0.18, cos(a) * 0.32)).rotation.y = a
			var rotor := Node3D.new()
			rotor.position.y = 0.2
			root.add_child(rotor)
			var needle := Kit.add(rotor, Kit.prism(Vector3(0.18, 0.3, 0.04)), Kit.mat("puzzle_%d" % o.id), Vector3(0, 0, 0.12))
			needle.rotation.x = PI / 2
			Kit.add(rotor, Kit.cylinder(0.06, 0.06, 0.05, 12), Kit.mat("brass"))
			var target: float = cfg.target[o.id] * PI / 2.0
			Kit.emblem(root, o.id, Kit.mat("brass"), Vector3(sin(target) * 0.5, 0.06, cos(target) * 0.5), 0.06)
			for j in cfg.target.size():
				if cfg.links[o.id][j]:
					Kit.emblem(root, j, Kit.mat("puzzle_%d" % j), Vector3((j - (cfg.target.size() - 1) / 2.0) * 0.15, 0.2, -0.24), 0.035)
			n["rotor"] = rotor
		"pan":
			Kit.add(root, Kit.cylinder(0.38, 0.32, 0.08, 20), Kit.mat("brass_dark"), Vector3(0, 0.34, 0))
			Kit.add(root, Kit.cylinder(0.35, 0.35, 0.03, 20), Kit.mat("stone"), Vector3(0, 0.39, 0))
			var pile := Node3D.new()
			pile.position.y = 0.46
			root.add_child(pile)
			var balls: Array = []
			for j in 12:
				balls.append(Kit.add(pile, Kit.sphere(0.072, 8), Kit.mat("brass"),
					Vector3(((j % 3) - 1) * 0.15, floorf(j / 6.0) * 0.14, ((int(j / 3.0) % 2) - 0.5) * 0.16)))
			n["pile"] = balls
			n["side"] = o.id
			# Running total above the pan, so a wrong choice is easy to see and fix.
			var sum := Label3D.new()
			sum.font_size = 64
			sum.pixel_size = 0.006
			sum.outline_size = 14
			sum.modulate = Color("ffe9b8")
			sum.outline_modulate = Color(0.2, 0.12, 0.05, 0.9)
			sum.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sum.position.y = 1.15
			sum.no_depth_test = false
			root.add_child(sum)
			n["sum"] = sum
			pan_nodes.append(n)
		"weight":
			Kit.add(root, Kit.cylinder(0.27, 0.31, 0.1, 18), Kit.mat("stone_dark"), Vector3(0, 0.1, 0))
			for j in o.value:
				Kit.add(root, Kit.sphere(0.085, 10), Kit.mat("brass"), Vector3(((j % 2) - 0.5) * 0.17, 0.24 + floorf(j / 2.0) * 0.15, 0))
		"brick":
			Kit.add_piece(root, "mud_brick", Kit.box(Vector3(0.92, 0.4, 0.56)), Kit.mat("plaster"), Vector3(0, 0.26, 0))
			for x in [-0.22, 0.22]:
				Kit.add(root, Kit.box(Vector3(0.15, 0.015, 0.25)), Kit.mat("wood"), Vector3(x, 0.47, 0))
		"brickSocket":
			Kit.add(root, Kit.box(Vector3(1.0, 0.07, 0.64)), Kit.mat("brass_dark"), Vector3(0, 0.07, 0))
			Kit.add(root, Kit.box(Vector3(0.83, 0.025, 0.46)), Kit.mat("brass"), Vector3(0, 0.11, 0))
			Kit.emblem(root, 2, Kit.mat("brass_dark"), Vector3(0, 0.14, 0), 0.12)
		"lock":
			pass  # drawn by its door
	return n


## Puzzle signs on the gatehouse front, where the player looks while solving:
## the sequence clues sit on the lintel above the gate; lamps share the lintel, or
## get their own board above it when a level has both (level 10). A lintel board
## stays between the two gate lanterns (at x = ±0.82), so long clues shrink to fit.
const LINTEL_MAX_WIDTH := 1.44
func _facade_board(row: int, width: float) -> Node3D:
	var ey := LevelData.exit_y(def)
	var board := Node3D.new()
	# Gatehouse front face is at z = -3.59 + 0.28; boards stand just proud of it.
	board.position = Vector3(LevelData.EXIT_X, ey + (1.62 if row == 0 else 2.32), -3.59 + 0.3)
	add_child(board)
	if row == 1:  # raised sign over the crenellations, on two short posts
		Kit.add(board, Kit.box(Vector3(width, 0.3, 0.06)), Kit.mat("plaster"), Vector3(0, 0, -0.02))
		for sx in [-1, 1]:
			Kit.add(board, Kit.box(Vector3(0.08, 0.36, 0.06)), Kit.mat("wood"), Vector3(sx * (width / 2.0 - 0.1), -0.3, -0.04))
	Kit.add(board, Kit.box(Vector3(width - 0.06, 0.27, 0.02)), Kit.mat("brass_dark"), Vector3(0, 0, 0.0))
	return board


func _facade_emblem(board: Node3D, index: int, material: Material, x: float, size: float) -> Node3D:
	var e := Kit.emblem(board, index, material, Vector3(x, 0, 0.02), size)
	e.rotation.x = PI / 2  # stand the symbol up, facing the player
	e.set_meta("base", e.position)
	return e


func _build_lamp_panel() -> void:
	var cfg: Dictionary = def.circuit
	var row := 1 if def.has("sequence") else 0
	var spacing := minf(0.34, (LINTEL_MAX_WIDTH - 0.2) / cfg.count) if row == 0 else 0.34
	var board := _facade_board(row, cfg.count * spacing + 0.2)
	for i in cfg.count:
		var x: float = (i - (cfg.count - 1) / 2.0) * spacing
		lamp_nodes.append(_facade_emblem(board, i, Kit.mat("lamp_off"), x, 0.1))


func _build_clue_tablet() -> void:
	var cfg: Dictionary = def.sequence
	var n: int = cfg.order.size()
	var spacing := minf(0.3, (LINTEL_MAX_WIDTH - 0.34) / n)
	var size := minf(0.085, spacing * 0.36)
	var board := _facade_board(0, n * spacing + 0.32)
	for i in n:
		var id: int = cfg.order[i]
		var clue := _facade_emblem(board, id, Kit.mat("puzzle_%d" % id), (i - (n - 1) / 2.0) * spacing + 0.07, size)
		clue_nodes.append({"node": clue, "id": id})
	# Reading direction arrow (left to right, like the clue order).
	var arrow := Kit.add(board, Kit.prism(Vector3(0.1, 0.1, 0.03)), Kit.mat("brass"), Vector3(-(n - 1) / 2.0 * spacing - 0.15, 0, 0.03))
	arrow.rotation = Vector3(0, 0, -PI / 2)


func _build_optics() -> void:
	var cfg: Dictionary = def.optics
	var src := Node3D.new()
	src.position = Vector3(cfg.source[0], surface(cfg.source[0], cfg.source[1]), cfg.source[1])
	add_child(src)
	Kit.add(src, Kit.box(Vector3(0.3, 0.4, 0.34)), Kit.mat("wood"), Vector3(0, 0.25, 0))
	Kit.add(src, Kit.sphere(0.1, 10), Kit.mat("glow"), Vector3(0.16 * cfg.source[2], 0.45, 0.16 * cfg.source[3]))
	var rec := Node3D.new()
	rec.position = Vector3(cfg.receiver[0], surface(cfg.receiver[0], cfg.receiver[1]), cfg.receiver[1])
	add_child(rec)
	Kit.add(rec, Kit.box(Vector3(0.6, 0.2, 0.6)), Kit.mat("stone_dark"), Vector3(0, 0.12, 0))
	var crystal := Kit.add(rec, Kit.octahedron(0.2), Kit.mat("lamp_off"), Vector3(0, 0.48, 0))
	obj_nodes["receiver"] = {"root": rec, "crystal": crystal}
	for i in 12:
		var b := Kit.add(self, Kit.box(Vector3(1, 0.04, 0.04)), Kit.mat("beam"), Vector3.ZERO, false)
		b.visible = false
		beam_nodes.append(b)


func _build_balance_frame() -> void:
	var cfg: Dictionary = def.balance
	var x: float = cfg.at[0]
	var z: float = cfg.at[1]
	var frame := Node3D.new()
	frame.position = Vector3(x, surface(x, z), z)
	add_child(frame)
	Kit.add(frame, Kit.box(Vector3(0.27, 0.9, 0.27)), Kit.mat("wood"), Vector3(0, 0.45, 0))
	scale_beam = Node3D.new()
	scale_beam.position.y = 0.88
	frame.add_child(scale_beam)
	Kit.add(scale_beam, Kit.box(Vector3(2.12, 0.08, 0.1)), Kit.mat("brass"))


# --- per-frame -------------------------------------------------------------------------

func _damp(a: float, b: float, rate: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-rate * dt))


func sync(dt: float, hero_pos := Vector2(INF, INF)) -> void:
	t += dt
	for i in mech_nodes.size():
		var m: Dictionary = state.mechanisms[i]
		var n: Dictionary = mech_nodes[i]
		var is_open := state.is_open(m)
		if dt > 0.0 and n.get("was", is_open) != is_open:
			mechanism_changed.emit(n.kind, is_open, n.root.position + Vector3(0, 0.4, 0))
		n["was"] = is_open
		n.open = _damp(n.open, 1.0 if state.is_open(m) else 0.0, 6.0, dt) if dt > 0 else (1.0 if state.is_open(m) else 0.0)
		match n.kind:
			"door":
				for l in n.leaves:
					l[0].rotation.y = l[1] * n.open * 1.75
			"bridge":
				n.planks.position.y = -0.95 * (1.0 - n.open)
				n.planks.visible = n.open > 0.02
			"stairs":
				n.gate.position.y = -0.98 * n.open
				n.gate.visible = n.open < 0.98
			"pool_bridge":
				n.stones.position.y = -0.2 * (1.0 - n.open)
	for i in crate_nodes.size():
		var c: Dictionary = state.crates[i]
		crate_nodes[i].position = Vector3(c.pos.x, 0, c.pos.y)
		var p: Dictionary = plate_nodes[i]
		p.root.position.y = -0.035 if c.done else 0.0
	if dt > 0.0 and _was_solved != state.solved:
		mechanism_changed.emit("exit", state.solved, exit_gate.get_parent().position + Vector3(0, 0.6, 0.2))
	_was_solved = state.solved
	if dt > 0.0 and _was_light != state.light and obj_nodes.has("receiver"):
		mechanism_changed.emit("light", state.light, obj_nodes.receiver.root.position + Vector3(0, 0.5, 0))
	_was_light = state.light
	var bal := state.balanced()
	if dt > 0.0 and _was_balanced != bal and scale_beam:
		mechanism_changed.emit("balance", bal, scale_beam.get_parent().position + Vector3(0, 0.9, 0))
	_was_balanced = bal
	exit_open = _damp(exit_open, 1.0 if state.solved else 0.0, 4.0, dt) if dt > 0 else (1.0 if state.solved else 0.0)
	for leaf in exit_gate.get_children():
		var side := -1.0 if leaf.name.ends_with("-1") else 1.0
		leaf.rotation.y = -side * exit_open * 1.9
	for o in state.objects:
		var n: Dictionary = obj_nodes.get(o.index, {})
		if n.is_empty():
			continue
		var visible := state.is_visible(o)
		n.root.visible = visible or o.type in ["lock"]
		if o.type == "weight" and visible:  # weights can be put down anywhere
			n.root.position = Vector3(o.x, surface(o.x, o.z), o.z)
		match o.type:
			"key", "gem":
				n.item.rotation.y += dt * 0.8
				n.item.position.y = 0.56 + sin(t * 2.4 + o.x) * 0.04
			"lever":
				n.arm.rotation.z = _damp(n.arm.rotation.z, 0.5 if state.choice else -0.5, 9.0, dt) if dt > 0 else (0.5 if state.choice else -0.5)
			"circuit":
				n.cap.position.y = 0.22 - 0.03 * (1.0 if state.bits & o.mask == o.mask and state.circuit_complete() else 0.0)
			"mirror":
				var target := -PI / 4 if o.dir else PI / 4
				n.pivot.rotation.y = _damp(n.pivot.rotation.y, target, 10.0, dt) if dt > 0 else target
			"dial":
				var target: float = state.dial_values[o.id] * PI / 2.0
				var cur: float = n.rotor.rotation.y
				var diff := wrapf(target - cur, -PI, PI)
				n.rotor.rotation.y = cur + diff * (1.0 - exp(-10.0 * dt)) if dt > 0 else target
			"brick":
				n.root.position = Vector3(state.brick_at.x, 0, state.brick_at.y)
			"portal":
				n.glow.position.y = 0.2 + sin(t * 2.0) * 0.03
	for i in lamp_nodes.size():
		var lit: bool = (state.bits & (1 << i)) != 0
		for mi in lamp_nodes[i].get_children():
			mi.material_override = Kit.mat("lit_%d" % i) if lit else Kit.mat("lamp_off")
		lamp_nodes[i].position = lamp_nodes[i].get_meta("base") + Vector3(0, 0, 0.035 if lit else 0.0)
	for i in clue_nodes.size():
		var done := i < state.sequence
		clue_nodes[i].node.position = clue_nodes[i].node.get_meta("base") + Vector3(0, 0, 0.035 if done else 0.0)
		var mname := ("lit_%d" % clue_nodes[i].id) if done else ("puzzle_%d" % clue_nodes[i].id)
		for mi in clue_nodes[i].node.get_children():
			mi.material_override = Kit.mat(mname)
	if def.has("optics"):
		for b in beam_nodes:
			b.visible = false
		for i in mini(state.light_segments.size(), beam_nodes.size()):
			var seg: Array = state.light_segments[i]
			var a: Vector2 = seg[0]
			var bb: Vector2 = seg[1]
			var y := surface(a.x, a.y) + 0.45
			var b: MeshInstance3D = beam_nodes[i]
			b.visible = true
			b.position = Vector3((a.x + bb.x) / 2.0, y, (a.y + bb.y) / 2.0)
			b.scale = Vector3(maxf(0.01, a.distance_to(bb)), 1, 1)
			b.rotation.y = 0.0 if absf(bb.x - a.x) > absf(bb.y - a.y) else PI / 2
		var rec: Dictionary = obj_nodes["receiver"]
		rec.crystal.material_override = Kit.mat("glow" if state.light else "lamp_off")
		rec.crystal.rotation.y += dt * (1.5 if state.light else 0.2)
	if def.has("balance"):
		var s := state.pan_sums()
		scale_beam.rotation.z = _damp(scale_beam.rotation.z, (s[0] - s[1]) * 0.03, 5.0, dt) if dt > 0 else (s[0] - s[1]) * 0.03
		for n in pan_nodes:
			var side: int = n.side
			var cfg: Dictionary = def.balance
			n.root.position.y = surface(cfg.at[0], cfg.at[1]) + (1.0 if side else -1.0) * sin(scale_beam.rotation.z) * 0.9
			for j in n.pile.size():
				n.pile[j].visible = j < s[side]
			n.sum.text = str(s[side])
			n.sum.modulate = Color("b8f0a0") if s[0] == s[1] and s[0] > 0 else Color("ffe9b8")
	for f in foliage:
		# Gentle sway; stronger, still restrained, in rain.
		var ph: float = f.get_meta("sway")
		f.rotation.z = sin(t * 0.9 + ph) * 0.02 * wind
		f.rotation.x = sin(t * 0.7 + ph * 1.7) * 0.015 * wind
	for r in roof_nodes:
		var rect: Array = r.rect
		var under: bool = absf(hero_pos.x - rect[0]) < rect[2] / 2.0 + 0.3 and absf(hero_pos.y - rect[1]) < rect[3] / 2.0 + 0.3
		r.fade = _damp(r.fade, 0.0 if under else 1.0, 8.0, dt) if dt > 0 else (0.0 if under else 1.0)
		# Cutaway: the roof lifts away instead of turning transparent.
		r.node.visible = r.fade > 0.03
		r.node.position.y = 1.32 + (1.0 - r.fade) * 0.9
		r.node.scale = Vector3.ONE * maxf(r.fade, 0.05)


func is_roofed(p: Vector2) -> bool:
	for r in def.get("roofs", []):
		if absf(p.x - r[0]) < r[2] / 2.0 and absf(p.y - r[1]) < r[3] / 2.0:
			return true
	return false
