class_name PuzzleState
extends RefCounted
## Pure puzzle rules for one level: no nodes, no rendering, no audio.
## Ported from the web reference (src/game.js: roomCondition, activateObject,
## activateAdvanced, activateAtrium, traceLight, refreshRoom, blocked).
## Every action that could close a mechanism on top of the hero is reverted
## and rejected, exactly as in the reference, so no action strands the hero.

signal changed

const PAD := 0.29
const COURT_MIN_X := -3.65
const COURT_MAX_X := 3.65
const COURT_MAX_Z := 3.05
const COURT_MIN_Z := -3.03
const CRATE_HALF := 0.86

var level := 1
var def: Dictionary
var keys := 0
var gems := 0
var unlocked := 0
var choice := 0
var bits := 0
var sequence := 0
var light := false
var light_segments: Array = []  # [[Vector2 from, Vector2 to], ...] for rendering
var dial_values: Array = []
var weight_places: Array = []  # -1 floor, 0/1 pan side, 2 carried
var carried := -1
var brick_mode := ""  # "floor" | "carried" | "socket" (level 21 only)
var brick_at := Vector2.ZERO
var crates: Array = []  # [{pos: Vector2, to: Vector2, dir: Vector2, done: bool}]
var solved := false

var objects: Array = []  # interactable dictionaries
var mechanisms: Array = []  # {kind, condition, id, rect, x, z}
var static_rects: Array = []
var hero := Vector2.ZERO  # hero position on the board plane (x, z)


func _init(level_number: int) -> void:
	level = level_number
	def = LevelData.get_level(level_number)
	_build()
	_refresh()


# --- construction -----------------------------------------------------------

static func rect_for(x: float, z: float, w: float, d: float, pad := PAD) -> Array:
	return [x - w / 2.0 - pad, x + w / 2.0 + pad, z - d / 2.0 - pad, z + d / 2.0 + pad]


func _add(type: String, x: float, z: float, extra := {}) -> Dictionary:
	var o := {"type": type, "x": x, "z": z, "id": 0, "index": objects.size()}
	o.merge(extra, true)
	objects.append(o)
	return o


func _build() -> void:
	var start: Array = def.start
	hero = Vector2(start[0], start[1])
	for c in def.get("crates", []):
		crates.append({"pos": Vector2(c.at[0], c.at[1]), "to": Vector2(c.to[0], c.to[1]),
			"dir": Vector2(c.dir[0], c.dir[1]), "done": false})
	if def.get("storeys", false):
		var spans: Array = []
		for s in def.stairs:
			spans.append([s[0] - 0.65, s[0] + 0.65])
		spans.sort_custom(func(a, b): return a[0] < b[0])
		var left := -4.0
		for sp in spans:
			if sp[0] > left:
				static_rects.append([left - 0.28, sp[0] + 0.28, -1.24, 1.24])
			left = sp[1]
		if left < 4.0:
			static_rects.append([left - 0.28, 4.28, -1.24, 1.24])
		for s in def.stairs:
			if s[1] != "always":
				mechanisms.append({"kind": "stairs", "condition": s[1], "id": s[2], "x": s[0], "z": 1.02,
					"rect": [s[0] - 0.94, s[0] + 0.94, -1.24, 1.24]})
	for w in def.walls:
		static_rects.append(rect_for(w[0], w[1], w[2], w[3]))
	if def.get("moat", false):
		var spans: Array = []
		for b in def.bridges:
			spans.append([b[0] - 0.65, b[0] + 0.65])
		spans.sort_custom(func(a, b): return a[0] < b[0])
		var left := -4.0
		for sp in spans:
			if sp[0] > left:
				static_rects.append([left - 0.28, sp[0] + 0.28, -0.89, 0.89])
			left = sp[1]
		if left < 4.0:
			static_rects.append([left - 0.28, 4.3, -0.89, 0.89])
		for b in def.bridges:
			mechanisms.append({"kind": "bridge", "condition": b[1], "id": b[2], "x": b[0], "z": 0.0,
				"rect": [b[0] - 0.93, b[0] + 0.93, -0.89, 0.89]})
	for d in def.get("doors", []):
		mechanisms.append({"kind": "door", "condition": d[4], "id": d[5], "x": d[0], "z": d[1],
			"w": d[2], "d": d[3], "rect": rect_for(d[0], d[1], d[2], d[3])})
		if d[4] == "lock":
			_add("lock", d[0], d[1], {"id": d[5]})
	for k in def.get("keys", []):
		_add("key", k[0], k[1], {"id": k[2]})
	for g in def.get("gems", []):
		_add("gem", g[0], g[1], {"id": g[2]})
	for l in def.get("levers", []):
		_add("lever", l[0], l[1], {"id": l[2]})
	if def.has("circuit"):
		var cfg: Dictionary = def.circuit
		for i in cfg.positions.size():
			_add("circuit", cfg.positions[i][0], cfg.positions[i][1], {"id": i, "mask": cfg.masks[i]})
	if def.has("sequence"):
		var cfg: Dictionary = def.sequence
		for i in cfg.pads.size():
			_add("sequence", cfg.pads[i][0], cfg.pads[i][1], {"id": i})
	for p in def.get("portals", []):
		_add("portal", p[0], p[1], {"tx": p[2], "tz": p[3]})
		_add("portal", p[2], p[3], {"tx": p[0], "tz": p[1]})
	if def.has("optics"):
		var cfg: Dictionary = def.optics
		for i in cfg.mirrors.size():
			var m: Array = cfg.mirrors[i]
			_add("mirror", m[0], m[1], {"id": i, "dir": m[2]})
	if def.has("dials"):
		var cfg: Dictionary = def.dials
		for i in cfg.positions.size():
			_add("dial", cfg.positions[i][0], cfg.positions[i][1], {"id": i})
			dial_values.append(0)
	if def.has("balance"):
		var cfg: Dictionary = def.balance
		for side in 2:
			_add("pan", cfg.at[0] + (0.9 if side else -0.9), cfg.at[1], {"id": side})
		for i in cfg.weights.size():
			var w: Array = cfg.weights[i]
			_add("weight", w[0], w[1], {"id": i, "value": w[2]})
			weight_places.append(-1)
	if def.get("pool_room", false):
		brick_mode = "floor"
		brick_at = Vector2(-2.6, 0.8)
		for a in [[-2.6, 0.8], [2.6, 0.8], [2.8, -1.1]]:
			for side in [-1, 1]:
				static_rects.append(rect_for(a[0] + side * 0.775, a[1], 0.15, 0.25))
		static_rects.append([-3.85, -2.72, -2.86, -0.04])
		static_rects.append([-1.38, -0.25, -2.86, -0.04])
		mechanisms.append({"kind": "pool_bridge", "condition": "brickSocket", "id": 0, "x": -2.05, "z": -1.45,
			"rect": [-2.72, -1.38, -2.86, -0.04]})
		_add("brick", -2.6, 0.8)
		_add("brickSocket", -3.35, 0.08)
	_trace_light()


# --- conditions ---------------------------------------------------------------

func dials_match() -> bool:
	if not def.has("dials"):
		return false
	for i in dial_values.size():
		if dial_values[i] != def.dials.target[i]:
			return false
	return true


func pan_sums() -> Array:
	var sum := [0, 0]
	if def.has("balance"):
		for i in weight_places.size():
			var p: int = weight_places[i]
			if p == 0 or p == 1:
				sum[p] += def.balance.weights[i][2]
	return sum


func balanced() -> bool:
	if not def.has("balance"):
		return false
	for p in weight_places:
		if p != 0 and p != 1:
			return false
	var s := pan_sums()
	return s[0] == s[1] and s[0] > 0


func sequence_complete() -> bool:
	return def.has("sequence") and sequence == def.sequence.order.size()


func circuit_complete() -> bool:
	return def.has("circuit") and bits == (1 << int(def.circuit.count)) - 1


func condition(type: String, id := 0) -> bool:
	match type:
		"brickSocket": return brick_mode == "socket"
		"dials": return dials_match()
		"balance": return balanced()
		"light": return light
		"keyChoice": return choice == id and (keys & 1) != 0
		"lock": return (unlocked & (1 << id)) != 0
		"choice": return choice == id
		"litChoice": return choice == id and light
		"circuit": return circuit_complete()
		"final": return (keys & 1) != 0 and sequence_complete()
	return true


func is_open(m: Dictionary) -> bool:
	return condition(m.condition, m.id)


func compute_solved() -> bool:
	for c in crates:
		if not c.done:
			return false
	var goal: int = def.get("goal_gems", 0)
	var need: int = def.get("need_keys", 0)
	if (gems & goal) != goal or (keys & need) != need:
		return false
	if def.get("need_circuit", false) and not circuit_complete():
		return false
	if def.get("need_sequence", false) and not sequence_complete():
		return false
	if def.get("need_light", false) and not light:
		return false
	if def.get("need_dials", false) and not dials_match():
		return false
	if def.get("need_balance", false) and not balanced():
		return false
	return true


# --- collision ---------------------------------------------------------------

func active_rects() -> Array:
	var r := static_rects.duplicate()
	if brick_mode == "floor" or brick_mode == "socket":
		r.append(rect_for(brick_at.x, brick_at.y, 0.92, 0.56))
	for m in mechanisms:
		if not is_open(m):
			r.append(m.rect)
	return r


func blocked(x: float, z: float, ignore_crates := false, rects = null) -> bool:
	if z < COURT_MIN_Z:
		if not solved or absf(x - LevelData.EXIT_X) > 0.29 or z < -4.43:
			return true
	elif x < COURT_MIN_X or x > COURT_MAX_X or z > COURT_MAX_Z:
		return true
	for r in (rects if rects != null else active_rects()):
		if x > r[0] and x < r[1] and z > r[2] and z < r[3]:
			return true
	if not ignore_crates:
		for c in crates:
			if absf(x - c.pos.x) < CRATE_HALF and absf(z - c.pos.y) < CRATE_HALF:
				return true
	return false


func hero_blocked() -> bool:
	return blocked(hero.x, hero.y)


# --- actions -----------------------------------------------------------------
# Each returns {"ok": bool, "event": String} so presentation can react
# (animation, sound) without the rules knowing about either.

func _snapshot() -> Dictionary:
	return {"keys": keys, "gems": gems, "unlocked": unlocked, "choice": choice, "bits": bits,
		"sequence": sequence, "dials": dial_values.duplicate(), "weights": weight_places.duplicate(),
		"carried": carried, "brick_mode": brick_mode, "brick_at": brick_at,
		"weight_at": objects.filter(func(o): return o.type == "weight").map(func(o): return Vector2(o.x, o.z)),
		"mirrors": objects.filter(func(o): return o.type == "mirror").map(func(o): return o.dir)}


func _restore(s: Dictionary) -> void:
	keys = s.keys; gems = s.gems; unlocked = s.unlocked; choice = s.choice; bits = s.bits
	sequence = s.sequence; dial_values = s.dials; weight_places = s.weights; carried = s.carried
	brick_mode = s.brick_mode; brick_at = s.brick_at
	var w := 0
	for o in objects:
		if o.type == "weight" and s.has("weight_at"):
			o.x = s.weight_at[w].x
			o.z = s.weight_at[w].y
			w += 1
	var i := 0
	for o in objects:
		if o.type == "mirror":
			o.dir = s.mirrors[i]
			i += 1
	_trace_light()


func is_visible(o: Dictionary) -> bool:
	match o.type:
		"key": return (keys & (1 << o.id)) == 0
		"gem": return (gems & (1 << o.id)) == 0
		"weight": return weight_places[o.id] == -1
		"brick": return brick_mode != "carried"
	return true


func activate(o: Dictionary) -> Dictionary:
	if not is_visible(o):
		return {"ok": false, "event": "none"}
	var before := _snapshot()
	var event := ""
	match o.type:
		"key":
			keys |= 1 << o.id
			event = "key"
		"gem":
			gems |= 1 << o.id
			event = "gem"
		"lock":
			if (keys & (1 << o.id)) == 0:
				return _reject("locked")
			unlocked |= 1 << o.id
			event = "unlock"
		"lever":
			choice = 1 - choice
			event = "lever"
		"circuit":
			bits ^= o.mask
			event = "circuit"
		"sequence":
			if sequence_complete():
				return {"ok": true, "event": "none"}
			if def.sequence.order[sequence] == o.id:
				sequence += 1
				event = "sequence_done" if sequence_complete() else "sequence"
			else:
				sequence = 0
				_refresh()
				return _reject("sequence_wrong")
		"portal":
			if blocked(o.tx, o.tz):
				return _reject("portal_blocked")
			hero = Vector2(o.tx, o.tz)
			event = "portal"
		"mirror":
			o.dir = 1 - o.dir
			_trace_light()
			event = "mirror"
		"dial":
			var links: Array = def.dials.links[o.id]
			for i in links.size():
				dial_values[i] = (dial_values[i] + links[i]) % 4
			event = "dial"
		"weight":
			if carried != -1:
				return _reject("hands_full")
			carried = o.id
			weight_places[o.id] = 2
			event = "pickup_weight"
		"pan":
			if carried != -1:
				weight_places[carried] = o.id
				carried = -1
				event = "place_weight"
			else:
				var take: int = weight_places.rfind(o.id)
				if take < 0:
					return _reject("pan_empty")
				carried = take
				weight_places[take] = 2
				event = "pickup_weight"
		"brick":
			brick_mode = "carried"
			event = "pickup_brick"
		"brickSocket":
			if brick_mode == "socket":
				brick_mode = "carried"
				event = "pickup_brick"
			elif brick_mode != "carried":
				return _reject("no_brick")
			else:
				# Reject a placement whose footprint (plus clearance) covers the hero.
				var r := rect_for(o.x, o.z, 0.92, 0.56)
				if hero.x > r[0] and hero.x < r[1] and hero.y > r[2] and hero.y < r[3]:
					return _reject("socket_occupied")
				brick_mode = "socket"
				brick_at = Vector2(o.x, o.z)
				event = "place_brick"
	_refresh()
	if hero_blocked():
		# Never let a mechanism close on the hero: undo and reject.
		_restore(before)
		_refresh()
		return _reject("would_trap")
	changed.emit()
	return {"ok": true, "event": event}


func _reject(reason: String) -> Dictionary:
	return {"ok": false, "event": "reject", "reason": reason}


## Put the carried weight down on the floor at (or as close as possible to) `at`,
## so a wrong choice on the balance can be undone freely. Returns the spot or null.
func drop_weight(at: Vector2, facing_yaw: float) -> Variant:
	if carried < 0:
		return null
	var obstacles := active_rects()
	var tries: Array = [at]
	for ring in [0.75, 1.1]:
		for i in 8:
			var a := facing_yaw + i * PI / 4.0
			tries.append(at + Vector2(sin(a), cos(a)) * ring)
	for p in tries:
		if p.x < -3.4 or p.x > 3.4 or p.y < -2.7 or p.y > 2.65:
			continue
		var r := [p.x - 0.32, p.x + 0.32, p.y - 0.32, p.y + 0.32]
		var blocked := false
		for q in obstacles:
			if r[0] < q[1] and r[1] > q[0] and r[2] < q[3] and r[3] > q[2]:
				blocked = true
				break
		for o in objects:  # keep a clear gap from other floor objects
			if not blocked and o.type != "weight" and o.type != "lock" and is_visible(o) and Vector2(o.x, o.z).distance_to(p) < 0.6:
				blocked = true
		for o in objects:
			if not blocked and o.type == "weight" and o.id != carried and weight_places[o.id] == -1 and Vector2(o.x, o.z).distance_to(p) < 0.62:
				blocked = true
		if blocked:
			continue
		for o in objects:
			if o.type == "weight" and o.id == carried:
				o.x = p.x
				o.z = p.y
		weight_places[carried] = -1
		carried = -1
		_refresh()
		changed.emit()
		return p
	return null


## Level 21: put the carried brick down near the hero. Returns the drop point
## or null. Never places it inside walls, water, closed gates or off the board.
func drop_brick(facing_yaw: float) -> Variant:
	if brick_mode != "carried":
		return null
	var obstacles := active_rects()
	for i in 8:
		var a := facing_yaw + i * PI / 4.0
		var x := hero.x + sin(a) * 1.12
		var z := hero.y + cos(a) * 1.12
		if x < -3.45 or x > 3.45 or z < -2.75 or z > 2.7:
			continue
		var r := [x - 0.47, x + 0.47, z - 0.29, z + 0.29]
		var hit := false
		for q in obstacles:
			if r[0] < q[1] and r[1] > q[0] and r[2] < q[3] and r[3] > q[2]:
				hit = true
				break
		if hit:
			continue
		brick_mode = "floor"
		brick_at = Vector2(x, z)
		_refresh()
		changed.emit()
		return brick_at
	return null


## Levels 1–2: finish a crate push (the presentation animates the slide).
func complete_push(index: int) -> void:
	var c: Dictionary = crates[index]
	c.pos = c.to
	c.done = true
	_refresh()
	changed.emit()


func push_position(index: int) -> Vector2:
	var c: Dictionary = crates[index]
	return c.pos - c.dir * 0.95


func _refresh() -> void:
	solved = compute_solved()


func refresh() -> void:
	_refresh()


# --- light -------------------------------------------------------------------

func _trace_light() -> void:
	light_segments.clear()
	light = false
	if not def.has("optics"):
		return
	var cfg: Dictionary = def.optics
	var x: float = cfg.source[0]
	var z: float = cfg.source[1]
	var dx: float = cfg.source[2]
	var dz: float = cfg.source[3]
	var mirrors := objects.filter(func(o): return o.type == "mirror")
	for bounce in 12:
		var distance: float
		if dx > 0: distance = 3.82 - x
		elif dx < 0: distance = x + 3.82
		elif dz > 0: distance = 3.25 - z
		else: distance = z + 3.25
		var hit = null
		var candidates: Array = []
		for m in mirrors:
			candidates.append({"x": m.x, "z": m.z, "mirror": m})
		candidates.append({"x": cfg.receiver[0], "z": cfg.receiver[1], "receiver": true})
		for p in candidates:
			var along: float = (p.x - x) * dx + (p.z - z) * dz
			var off: float = absf((p.x - x) * dz - (p.z - z) * dx)
			if along > 0.02 and off < 0.08 and along < distance:
				distance = along
				hit = p
		for w in def.walls:
			var lo_x: float = w[0] - w[2] / 2.0
			var hi_x: float = w[0] + w[2] / 2.0
			var lo_z: float = w[1] - w[3] / 2.0
			var hi_z: float = w[1] + w[3] / 2.0
			var along := INF
			if dx != 0 and z > lo_z and z < hi_z:
				along = (lo_x - x) if dx > 0 else (x - hi_x)
			if dz != 0 and x > lo_x and x < hi_x:
				along = (lo_z - z) if dz > 0 else (z - hi_z)
			if along > 0.01 and along < distance:
				distance = along
				hit = null
		light_segments.append([Vector2(x, z), Vector2(x + dx * distance, z + dz * distance)])
		if hit == null:
			break
		if hit.has("receiver"):
			light = true
			break
		x = hit.x
		z = hit.z
		var old_dx := dx
		dx = dz if hit.mirror.dir else -dz
		dz = old_dx if hit.mirror.dir else -old_dx


# --- solver support ------------------------------------------------------------

func state_key() -> String:
	var mirrors := []
	for o in objects:
		if o.type == "mirror":
			mirrors.append(o.dir)
	var crate_bits := 0
	for i in crates.size():
		if crates[i].done:
			crate_bits |= 1 << i
	return "%d|%d|%d|%d|%d|%d|%s|%s|%s|%d|%s|%s|%d" % [keys, gems, unlocked, choice, bits, sequence,
		str(mirrors), str(dial_values), str(weight_places), carried, brick_mode,
		str(brick_at.snapped(Vector2(0.01, 0.01))), crate_bits]


func clone() -> PuzzleState:
	var s := PuzzleState.new(level)
	s.keys = keys; s.gems = gems; s.unlocked = unlocked; s.choice = choice; s.bits = bits
	s.sequence = sequence; s.dial_values = dial_values.duplicate(); s.weight_places = weight_places.duplicate()
	s.carried = carried; s.brick_mode = brick_mode; s.brick_at = brick_at; s.hero = hero
	for i in crates.size():
		s.crates[i].pos = crates[i].pos
		s.crates[i].done = crates[i].done
	for i in objects.size():
		if objects[i].type == "mirror":
			s.objects[i].dir = objects[i].dir
	s._trace_light()
	s._refresh()
	return s
