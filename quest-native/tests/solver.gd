class_name LevelSolver
extends RefCounted
## Exhaustive search over a level's puzzle states using the real game rules
## (PuzzleState + Navigator). Hero position is abstracted to the connected
## walkable region it stands in. Used by tests to prove that every level is
## solvable, that no reachable state is a dead end, and that gate mechanics
## cannot be bypassed.

var level: int
var level_def: Dictionary = {}
var forbid_types: Array = []
var sample_drops := true
var max_states := 60000

var nodes: Array = []  # [{state: PuzzleState, key: String}]
var edges: Array = []  # node index -> Array[int] successors
var goal_nodes: Array = []
var parent: Dictionary = {}  # node -> [prev node, action label]
var _index: Dictionary = {}
var _flood_cache: Dictionary = {}


func _init(n: int, forbid := [], def := {}) -> void:
	level = n
	forbid_types = forbid
	level_def = def


func _geometry_key(s: PuzzleState) -> String:
	var k := str(s.active_rects()) + str(s.solved)
	for c in s.crates:
		k += str(c.pos)
	return k


func _flood(s: PuzzleState) -> Dictionary:
	var nav := Navigator.new(s)
	var f := nav.flood(s.hero)
	var key := _geometry_key(s) + "#" + str(f.start)
	if _flood_cache.has(key):
		return _flood_cache[key]
	var count := 0
	var lowest := 1 << 30
	for i in f.prev.size():
		if f.prev[i] != -2:
			count += 1
			lowest = mini(lowest, i)
	var entry := {"f": f, "nav": nav, "region": "%d:%d" % [lowest, count], "reach": {}}
	_flood_cache[key] = entry
	return entry


func _reachable_point(entry: Dictionary, p: Vector2) -> bool:
	var nav: Navigator = entry.nav
	if nav.blocked(p.x, p.y):
		return false
	var f: Dictionary = entry.f
	var gx := roundi((p.x - Navigator.ORIGIN_X) / Navigator.STEP)
	var gz := roundi((p.y - Navigator.ORIGIN_Z) / Navigator.STEP)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var x := gx + dx
			var z := gz + dz
			if x < 0 or x >= Navigator.NX or z < 0 or z >= Navigator.NZ:
				continue
			var i := z * Navigator.NX + x
			if f.prev[i] != -2 and nav.clear_segment(p, Navigator.point(i)):
				return true
	return false


func _points_for(entry: Dictionary, s: PuzzleState, o: Dictionary) -> Array:
	var cache_key := "%d" % o.index
	if o.type == "brick" or o.type == "brickSocket" or o.type == "plate":
		cache_key += str(s.brick_at) + s.brick_mode
	if entry.reach.has(cache_key):
		return entry.reach[cache_key]
	var nav: Navigator = entry.nav
	var out: Array = []
	for p in nav.approach_points(o, s.hero):
		if _reachable_point(entry, p):
			out.append(p)
	entry.reach[cache_key] = out
	return out


func _add(s: PuzzleState, from: int, label: String) -> int:
	var entry := _flood(s)
	var key: String = s.state_key() + "@" + entry.region
	if _index.has(key):
		var i: int = _index[key]
		if from >= 0 and not edges[from].has(i):
			edges[from].append(i)
		return i
	var i := nodes.size()
	_index[key] = i
	nodes.append({"state": s, "key": key, "region": entry})
	edges.append([])
	if from >= 0:
		edges[from].append(i)
		parent[i] = [from, label]
	return i


func run() -> Dictionary:
	var start := PuzzleState.new(level, level_def)
	_add(start, -1, "start")
	var head := 0
	while head < nodes.size():
		if nodes.size() > max_states:
			return {"ok": false, "error": "state limit"}
		var n: Dictionary = nodes[head]
		var s: PuzzleState = n.state
		var entry: Dictionary = n.region
		var cur := head
		head += 1
		# Exit when solved and the tunnel end is reachable.
		if s.solved and _reachable_point(entry, Vector2(LevelData.exit_x(s.def), -4.38)):
			goal_nodes.append(cur)
		# Crate pushes (levels 1–2).
		for i in s.crates.size():
			if not s.crates[i].done and _reachable_point(entry, s.push_position(i)):
				var t := s.clone()
				t.complete_push(i)
				t.hero = t.push_position(i)
				_add(t, cur, "push crate %d" % i)
		# Free crates: push away from, or pull toward, any reachable side.
		for i in s.crates.size():
			if not s.crates[i].free or "crate" in forbid_types:
				continue
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				if not _reachable_point(entry, s.free_push_position(i, d)):
					continue
				for pull in [false, true]:
					var t := s.clone()
					t.hero = t.free_push_position(i, d)
					var r := t.pull_crate(i, d) if pull else t.push_crate(i, d)
					if r.ok:
						_add(t, cur, "%s crate %d %s" % ["pull" if pull else "push", i, str(d)])
		# The falcon, once: to any key or plate, reachable or not.
		if s.def.has("falcon") and not s.falcon_used and not "falcon" in forbid_types:
			for o in s.objects:
				if s.falcon_can(o):
					var t := s.clone()
					var r := t.send_falcon(t.objects[o.index])
					if r.ok:
						_add(t, cur, "falcon %s %d" % [o.type, o.id])
		# Use every visible object from any reachable side.
		for o in s.objects:
			if not s.is_visible(o) or o.type in forbid_types:
				continue
			var pts := _points_for(entry, s, o)
			for p in pts:
				var t := s.clone()
				t.hero = p
				var r := t.activate(t.objects[o.index])
				if r.ok and r.event != "none":
					_add(t, cur, "%s %d" % [o.type, o.id])
					break
				if r.get("reason", "") != "would_trap":
					break
		# Put a carried weight down: onto each plate, and at one spot away from them.
		if s.carried >= 0 and (s.def.get("balance", {}).get("free", false) or not s.def.get("plates", []).is_empty()):
			var spots: Array = []
			for o in s.objects:
				if o.type == "plate":
					spots.append(Vector2(o.x, o.z))
			var f2: Dictionary = entry.f
			for i in range(0, f2.prev.size(), 11):
				if f2.prev[i] != -2:
					var q := Navigator.point(i)
					var far := true
					for sp in spots:
						if sp.distance_to(q) < 1.2:
							far = false
					if far:
						spots.append(q)
						break
			for sp in spots:
				var stand: Vector2 = sp
				var near_ok := false
				for k in 8:
					var a := k * PI / 4.0
					var hp: Vector2 = sp + Vector2(sin(a), cos(a)) * 0.75
					if _reachable_point(entry, hp):
						stand = hp
						near_ok = true
						break
				if not near_ok:
					continue
				var t := s.clone()
				t.hero = stand
				if t.drop_weight(sp, 0.0) != null:
					_add(t, cur, "drop weight at %s" % str(sp.snapped(Vector2(0.1, 0.1))))
		# Put the brick down at a sample of reachable places.
		if sample_drops and s.brick_mode == "carried":
			var f: Dictionary = entry.f
			var count := 0
			for i in range(0, f.prev.size(), 7):
				if f.prev[i] == -2:
					continue
				var t := s.clone()
				t.hero = Navigator.point(i)
				if t.drop_brick(0.0) != null:
					_add(t, cur, "drop brick")
					count += 1
				if count >= 12:
					break
	return {"ok": not goal_nodes.is_empty(), "states": nodes.size()}


func solution() -> Array:
	if goal_nodes.is_empty():
		return []
	# Shortest by BFS order: the first goal found is nearest the start.
	var steps: Array = []
	var i: int = goal_nodes[0]
	while parent.has(i):
		steps.push_front(parent[i][1])
		i = parent[i][0]
	steps.append("exit")
	return steps


## States from which the exit can no longer be reached.
func dead_ends() -> Array:
	var can := {}
	var reverse := {}
	for i in edges.size():
		for j in edges[i]:
			if not reverse.has(j):
				reverse[j] = []
			reverse[j].append(i)
	var queue: Array = goal_nodes.duplicate()
	for g in queue:
		can[g] = true
	var head := 0
	while head < queue.size():
		var j: int = queue[head]
		head += 1
		for i in reverse.get(j, []):
			if not can.has(i):
				can[i] = true
				queue.append(i)
	var out: Array = []
	for i in nodes.size():
		if not can.has(i):
			out.append(i)
	return out


func describe(i: int) -> String:
	var steps: Array = []
	var k := i
	while parent.has(k):
		steps.push_front(parent[k][1])
		k = parent[k][0]
	return " -> ".join(steps) + "  [" + nodes[i].key + "]"
