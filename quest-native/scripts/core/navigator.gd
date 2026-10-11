class_name Navigator
extends RefCounted
## Collision queries and point-and-select pathfinding on the board plane.
## Mirrors the web reference (segmentHits, clearSegment, findPath,
## approachObject) but precomputes a walkable grid per puzzle state, which
## keeps a full path query to a few milliseconds on Quest.

const STEP := 0.2
const NX := 37
const NZ := 38
const ORIGIN_X := -3.6
const ORIGIN_Z := -4.4

var state: PuzzleState
var _rects: Array = []
var _walk := PackedByteArray()
var _walk_crates := PackedByteArray()
var _key := ""


func _init(s: PuzzleState) -> void:
	state = s


func invalidate() -> void:
	_key = ""


func _ensure() -> void:
	var k := state.state_key() + str(state.solved)
	for c in state.crates:
		k += str(c.pos)
	if k == _key:
		return
	_key = k
	_rects = state.active_rects()
	_walk.resize(NX * NZ)
	_walk_crates.resize(NX * NZ)
	for i in NX * NZ:
		var p := point(i)
		_walk[i] = 0 if state.blocked(p.x, p.y, false, _rects) else 1
		_walk_crates[i] = 0 if state.blocked(p.x, p.y, true, _rects) else 1


static func point(i: int) -> Vector2:
	return Vector2(ORIGIN_X + (i % NX) * STEP, ORIGIN_Z + (i / NX) * STEP)


func rects() -> Array:
	_ensure()
	return _rects


func blocked(x: float, z: float, ignore_crates := false) -> bool:
	_ensure()
	return state.blocked(x, z, ignore_crates, _rects)


static func segment_hits(a: Vector2, b: Vector2, r: Array) -> bool:
	var enter := 0.0
	var leave := 1.0
	for axis in 2:
		var lo: float = r[0] if axis == 0 else r[2]
		var hi: float = r[1] if axis == 0 else r[3]
		var av := a.x if axis == 0 else a.y
		var d := (b.x - a.x) if axis == 0 else (b.y - a.y)
		if absf(d) < 1e-9:
			if av <= lo or av >= hi:
				return false
		else:
			var t1 := (lo - av) / d
			var t2 := (hi - av) / d
			if t1 > t2:
				var t := t1
				t1 = t2
				t2 = t
			enter = maxf(enter, t1)
			leave = minf(leave, t2)
			if enter >= leave:
				return false
	return leave > 0.0 and enter < 1.0


func clear_segment(a: Vector2, b: Vector2, ignore_crates := false) -> bool:
	_ensure()
	var ex := LevelData.EXIT_X
	var obstacles: Array = _rects + [[-100.0, ex - 0.29, -100.0, -3.03], [ex + 0.29, 100.0, -100.0, -3.03]]
	if not ignore_crates:
		for c in state.crates:
			obstacles.append([c.pos.x - 0.87, c.pos.x + 0.87, c.pos.y - 0.87, c.pos.y + 0.87])
	for r in obstacles:
		if segment_hits(a, b, r):
			return false
	var n := maxi(1, ceili(a.distance_to(b) / 0.05))
	for i in range(1, n + 1):
		var p := a.lerp(b, float(i) / n)
		if state.blocked(p.x, p.y, ignore_crates, _rects):
			return false
	return true


func _nearest(p: Vector2, walk: PackedByteArray, ignore_crates: bool) -> int:
	# Search nearby grid nodes in distance order instead of the whole grid.
	var cx := roundi((p.x - ORIGIN_X) / STEP)
	var cz := roundi((p.y - ORIGIN_Z) / STEP)
	var best := -1
	var best_d := INF
	for radius in range(0, 6):
		for gz in range(cz - radius, cz + radius + 1):
			for gx in range(cx - radius, cx + radius + 1):
				if maxi(absi(gx - cx), absi(gz - cz)) != radius:
					continue
				if gx < 0 or gx >= NX or gz < 0 or gz >= NZ:
					continue
				var i := gz * NX + gx
				if walk[i] == 0:
					continue
				var q := point(i)
				var d := p.distance_squared_to(q)
				if d < best_d and clear_segment(p, q, ignore_crates):
					best_d = d
					best = i
		if best >= 0 and radius >= 1:
			return best
	return best


## Breadth-first distances from `from` over the walkable grid.
func flood(from: Vector2, ignore_crates := false) -> Dictionary:
	_ensure()
	var walk := _walk_crates if ignore_crates else _walk
	var start := _nearest(from, walk, ignore_crates)
	var prev := PackedInt32Array()
	prev.resize(NX * NZ)
	prev.fill(-2)
	if start < 0:
		return {"start": -1, "prev": prev}
	prev[start] = -1
	var queue := PackedInt32Array([start])
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % NX
		var z := i / NX
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var xx: int = x + d.x
			var zz: int = z + d.y
			if xx < 0 or xx >= NX or zz < 0 or zz >= NZ:
				continue
			var j: int = zz * NX + xx
			if prev[j] != -2 or walk[j] == 0:
				continue
			prev[j] = i
			queue.append(j)
	return {"start": start, "prev": prev, "walk": walk, "ignore": ignore_crates}


func path_from_flood(f: Dictionary, from: Vector2, to: Vector2) -> Array:
	if f.start < 0:
		return []
	var ignore: bool = f.ignore
	if blocked(to.x, to.y, ignore):
		return []
	var goal := _nearest(to, f.walk, ignore)
	if goal < 0 or f.prev[goal] == -2:
		return []
	var raw: Array = []
	var i := goal
	while i != -1:
		raw.append(point(i))
		i = f.prev[i]
	raw.reverse()
	raw.append(to)
	var smooth: Array = []
	var anchor := from
	var index := 0
	while index < raw.size():
		var far := index
		while far + 1 < raw.size() and clear_segment(anchor, raw[far + 1], ignore):
			far += 1
		smooth.append(raw[far])
		anchor = raw[far]
		index = far + 1
	return smooth


func find_path(from: Vector2, to: Vector2, ignore_crates := false) -> Array:
	return path_from_flood(flood(from, ignore_crates), from, to)


static func path_length(from: Vector2, path: Array) -> float:
	var length := 0.0
	var prev := from
	for q in path:
		length += prev.distance_to(q)
		prev = q
	return length


## Interaction points around an object, nearest first, with line of sight to
## the object (only the lock's own gate and the brick itself may be crossed).
func approach_points(o: Dictionary, from: Vector2) -> Array:
	var target := Vector2(o.x, o.z)
	if o.type == "portal" or o.type == "sequence":
		return [target]
	var radii := [0.62, 0.83]
	if o.type == "brickSocket":
		radii = [1.0, 1.15]
	elif o.type == "brick":
		radii = [0.85, 1.05]
	var pts: Array = []
	for radius in radii:
		for i in 12:
			var a := i / 12.0 * TAU
			pts.append(target + Vector2(cos(a), sin(a)) * radius)
	pts.sort_custom(func(a, b): return a.distance_to(from) < b.distance_to(from))
	var blockers: Array = []
	var brick_rect := PuzzleState.rect_for(state.brick_at.x, state.brick_at.y, 0.92, 0.56)
	for r in rects():
		if o.type == "brick" and r == brick_rect:
			continue
		if o.type == "lock":
			var own := false
			for m in state.mechanisms:
				if m.kind == "door" and m.condition == "lock" and m.id == o.id and m.rect == r:
					own = true
			if own:
				continue
		blockers.append(r)
	var out: Array = []
	for p in pts:
		var los := true
		for r in blockers:
			if segment_hits(p, target, r):
				los = false
				break
		if los:
			out.append(p)
	return out


## Returns the walking route to reach and use `o`, or [] when unreachable.
func route_to_object(o: Dictionary, from: Vector2) -> Array:
	var f := flood(from)
	for p in approach_points(o, from):
		var path := path_from_flood(f, from, p)
		if not path.is_empty():
			return path
	return []
