class_name TablePlacer
extends Node3D
## Finding a surface and fixing the diorama on it, before the scene appears (after the
## owner's racing game, Hajwala: a marker that sits on whatever real surface the pointer
## finds, a stick to turn it, the trigger to set it down).
##   The headset's room setup gives the real tables (SceneSurfaces); while placing, each
##   is outlined, and the one under the pointer lights up.
##   A ring the size of the diorama follows the pointer on the surface it hits: a real
##   table (the ring shrinks to fit it and stays on it), the floor, or, when the room has
##   no table captured, a surface at a comfortable table height in front of the player.
##   An arrow on the ring shows where the gate will face. Left stick x turns it, y sizes it.
##   The owner (table_main) feeds it the pointer every frame and presses confirm().

const ISLAND := 0.66        # metres across at size 1
const SIZE_MIN := 0.4
const SIZE_MAX := 3.0
const CREAM := Color("fff1d0")
const GOLD := Color("e3a83a")

var surfaces: Node          # SceneSurfaces (anything with surfaces() -> [{label, center, size, basis}])
var k := 1.0                # the size asked for (the stick); a table may fit less
var fitted := 1.0           # the size it will have where it is now
var has_spot := false
var on_table := false
var _pos := Vector3.ZERO
var _turn := 0.0            # the player's own turn of it, on top of facing them
var _yaw := 0.0
var _marker: Node3D
var _ring: MeshInstance3D
var _fill: MeshInstance3D
var _outlines: Node3D
var _table_lines := {}      # table index -> [MeshInstance3D]
var _hot := -1
var _label: Label3D
var _t := 0.0


func _ready() -> void:
	_outlines = Node3D.new()
	add_child(_outlines)
	_marker = Node3D.new()
	add_child(_marker)
	_ring = TableKit.ring(_marker, 0.5, CREAM, 0.95, 0.05)
	_fill = TableKit.cyl(_marker, 0.5, 0.5, 0.002, TableKit.glow_mat(CREAM, 0.16), Vector3.ZERO, 48)
	# the arrow at the gate's edge, pointing out of the diorama (towards the player)
	var arrow := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.09, 0.07, 0.004)
	arrow.mesh = pm
	arrow.material_override = TableKit.glow_mat(CREAM, 0.95)
	arrow.rotation = Vector3(PI / 2, 0, 0)   # its tip towards +z: out of the gate, at the player
	arrow.position = Vector3(0, 0.003, 0.5 + 0.06)
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(arrow)
	_label = TableMenu.text("", Vector3(0, 0.16, 0), 40, CREAM)
	_label.pixel_size = 0.0005
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.outline_size = 8
	_label.outline_modulate = Color(0.25, 0.17, 0.1, 0.85)
	_label.no_depth_test = true
	add_child(_label)
	_marker.visible = false
	_label.visible = false
	rebuild()


## Draws the outline of every detected table (again, when the room data changes).
func rebuild() -> void:
	for c in _outlines.get_children():
		c.queue_free()
	_table_lines.clear()
	_hot = -1
	var list := _tables()
	for i in list.size():
		var s: Dictionary = list[i]
		var lines: Array = []
		var hx: float = s.size.x / 2.0
		var hz: float = s.size.y / 2.0
		for e in [[Vector3(0, 0, -hz), Vector3(s.size.x, 0.004, 0.012)], [Vector3(0, 0, hz), Vector3(s.size.x, 0.004, 0.012)],
				[Vector3(-hx, 0, 0), Vector3(0.012, 0.004, s.size.y)], [Vector3(hx, 0, 0), Vector3(0.012, 0.004, s.size.y)]]:
			var at: Vector3 = s.center + (s.basis as Basis) * (e[0] as Vector3) + Vector3(0, 0.004, 0)
			var line := TableKit.box(_outlines, e[1], TableKit.glow_mat(CREAM, 0.45))
			line.transform = Transform3D(s.basis, at)   # (this node stays at the origin)
			lines.append(line)
		_table_lines[i] = lines


func _tables() -> Array:
	var out: Array = []
	if surfaces:
		for s in surfaces.surfaces():
			if s.label == "table":
				out.append(s)
	return out


func _floor_y() -> float:
	if surfaces:
		for s in surfaces.surfaces():
			if s.label == "floor":
				return (s.center as Vector3).y
	return 0.0


## The pointer this frame (world ray), the head, and the stick that turns and sizes it.
func update(ray: Array, head: Transform3D, stick: Vector2, dt: float) -> void:
	_t += dt
	if absf(stick.x) > 0.25:
		_turn -= stick.x * 1.6 * dt
	if absf(stick.y) > 0.25:
		k = clampf(k * exp(stick.y * 0.9 * dt), SIZE_MIN, SIZE_MAX)
	var hit := _find(ray, head)
	if hit.is_empty() and not has_spot:
		hit = _nearest_table(head)   # the room scan's table in front, before the pointer finds one
	if hit.is_empty():
		_set_hot(-1)
		_marker.visible = has_spot   # keep the last spot rather than flicker away
	else:
		var to: Vector3 = hit.point
		_pos = to if not has_spot or _pos.distance_to(to) > 0.6 else _pos.lerp(to, clampf(dt * 14.0, 0, 1))
		fitted = hit.fit
		on_table = hit.table >= 0
		_set_hot(hit.table)
		has_spot = true
		_marker.visible = true
	if has_spot:
		var face := Vector3(head.origin.x - _pos.x, 0, head.origin.z - _pos.z)
		_yaw = atan2(face.x, face.z) + _turn
		var r := ISLAND * fitted / 2.0
		_marker.global_transform = Transform3D(Basis(Vector3.UP, _yaw).scaled(Vector3(r * 2.0, 1.0, r * 2.0)), _pos + Vector3(0, 0.003, 0))
		var pulse := 0.6 + 0.35 * sin(_t * 4.0)
		(_ring.material_override as StandardMaterial3D).albedo_color = Color(GOLD if on_table else CREAM, pulse + 0.05)
		_label.global_position = _pos + Vector3(0, 0.12 + r * 0.3, 0)
	_label.visible = has_spot
	var save = get_node_or_null("/root/Save")
	_label.text = save.text("اضغط الزناد لتثبيت المشهد", "Press the trigger to set the scene down") if save else "اضغط الزناد لتثبيت المشهد"


## Where the ray meets a surface: {point, fit, table (index or -1)}, or {}.
func _find(ray: Array, head: Transform3D) -> Dictionary:
	if ray.size() != 2:
		return {}
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	var best := {}
	var best_t := INF
	var list := _tables()
	for i in list.size():
		var s: Dictionary = list[i]
		var c: Vector3 = s.center
		var p = Plane(Vector3.UP, c.y).intersects_ray(o, d)
		if p == null:
			continue
		var b: Basis = s.basis
		var local := b.inverse() * ((p as Vector3) - c)
		var hx: float = s.size.x / 2.0
		var hz: float = s.size.y / 2.0
		if absf(local.x) > hx + 0.05 or absf(local.z) > hz + 0.05:
			continue
		var t := o.distance_to(p)
		if t < best_t:
			# fit the diorama on the table, and keep all of it on the top
			var fit := minf(k, minf(s.size.x, s.size.y) * 0.95 / ISLAND)
			var r := ISLAND * fit / 2.0
			local.x = clampf(local.x, -maxf(0.0, hx - r), maxf(0.0, hx - r))
			local.z = clampf(local.z, -maxf(0.0, hz - r), maxf(0.0, hz - r))
			best_t = t
			best = {"point": c + b * Vector3(local.x, 0, local.z), "fit": fit, "table": i}
	if not best.is_empty():
		return best
	# no table under it: a table-height surface in front (only when the room has no table
	# captured), else the floor
	var planes: Array = []
	if list.is_empty() and head.origin.y > 0.3:
		planes.append(maxf(0.55, head.origin.y - 0.55))
	planes.append(_floor_y())
	for y in planes:
		var p = Plane(Vector3.UP, y).intersects_ray(o, d)
		if p == null:
			continue
		var flat := Vector3((p as Vector3).x - head.origin.x, 0, (p as Vector3).z - head.origin.z).length()
		if flat < 0.25 or flat > 3.5:
			continue
		return {"point": p, "fit": k, "table": -1}
	return {}


## The detected table nearest in front of the player, as a spot ({point, fit, table}), or {}.
func _nearest_table(head: Transform3D) -> Dictionary:
	var list := _tables()
	var fwd := -head.basis.z
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var best := {}
	var best_score := INF
	for i in list.size():
		var s: Dictionary = list[i]
		var to: Vector3 = s.center - head.origin
		var flat := Vector3(to.x, 0, to.z)
		var d := flat.length()
		if d > 3.0 or d < 0.15:
			continue
		var score := d - flat.normalized().dot(fwd)
		if score < best_score:
			best_score = score
			best = {"point": s.center, "fit": minf(k, minf(s.size.x, s.size.y) * 0.95 / ISLAND), "table": i}
	return best


func _set_hot(i: int) -> void:
	if i == _hot:
		return
	for j in _table_lines:
		for line in _table_lines[j]:
			(line.material_override as StandardMaterial3D).albedo_color = Color(GOLD, 0.95) if j == i else Color(CREAM, 0.45)
	_hot = i


func spot() -> Vector3:
	return _pos


## The diorama's place: on the spot, the gate towards the player, at the fitted size.
func placement() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, _yaw).scaled(Vector3.ONE * fitted), _pos + Vector3(0, 0.005, 0))
