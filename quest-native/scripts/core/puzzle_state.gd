class_name PuzzleState
extends RefCounted
## Pure puzzle rules for one level: no nodes, no rendering, no audio.
## Originally ported from the web reference (src/game.js); v2 adds coloured keys,
## pressure plates (dakka), free crates (push and pull), the falaj (sluices, pools,
## stepping stones), the falcon companion, palm shade on hot tiles with a sundial,
## lamps and portals in the light path, a data-driven brick, secret gems and a full
## snapshot for undo.
## Every action that could close a mechanism on top of the hero is reverted and
## rejected, so no action strands the hero.

signal changed

const PAD := 0.29
const COURT := [-3.65, 3.65, -3.03, 3.05]  # default playable bounds: min x, max x, min z, max z
const CRATE_HALF := 0.86
const FREE_CRATE_HALF := 0.78  # free crates sit on tile centres, one tile per push
const PLATE_REACH := 0.45
const SECRET_ID := 7  # bit of the optional secret gem (never part of the goal)

var level := 1
var def: Dictionary
var bounds: Array = COURT
var keys := 0
var gems := 0
var unlocked := 0
var choice := 0
var bits := 0
var sequence := 0
var light := false
var lamps_lit := 0  # bitmask of lamps the beam passes through
var light_segments: Array = []  # [[Vector2 from, Vector2 to], ...] for rendering
var dial_values: Array = []
var weight_places: Array = []  # -1 floor, 0/1 pan side, 2 carried
var carried := -1
var brick_mode := ""  # "floor" | "carried" | "socket"
var brick_at := Vector2.ZERO
var crates: Array = []  # [{pos, to, dir, done, free}]
var sluices := 0  # bitmask of open sluice gates
var sun := 0  # shade phase (advances with every action and the sundial)
var falcon_used := false
var falcon_plate := -1  # plate the falcon sits on
var solved := false

var objects: Array = []  # interactable dictionaries
var mechanisms: Array = []  # {kind, condition, id, rect, x, z}
var static_rects: Array = []
var hero := Vector2.ZERO  # hero position on the board plane (x, z)


func _init(level_number: int, level_def := {}) -> void:
	level = level_number
	def = level_def if not level_def.is_empty() else LevelData.get_level(level_number)
	bounds = def.get("bounds", COURT)
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
		if c.has("to"):
			crates.append({"pos": Vector2(c.at[0], c.at[1]), "to": Vector2(c.to[0], c.to[1]),
				"dir": Vector2(c.dir[0], c.dir[1]), "done": false, "free": false})
		else:
			crates.append({"pos": Vector2(c.at[0], c.at[1]), "to": Vector2.ZERO, "dir": Vector2.ZERO,
				"done": true, "free": true})
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
	# Water with stepping stones that rise when its pool fills (falaj levels): the
	# whole area blocks until then. [x, z, w, d, pool id]
	for w in def.get("waters", []):
		mechanisms.append({"kind": "stones", "condition": "pool", "id": w[4], "x": w[0], "z": w[1],
			"w": w[2], "d": w[3], "rect": rect_for(w[0], w[1], w[2], w[3], 0.22)})
	# Hot tiles: walkable only while a palm's shadow covers them. [x, z, w, d]
	if def.has("shade"):
		var hot: Array = def.shade.hot
		for i in hot.size():
			var h: Array = hot[i]
			mechanisms.append({"kind": "hot", "condition": "shade", "id": i, "x": h[0], "z": h[1],
				"w": h[2], "d": h[3], "rect": rect_for(h[0], h[1], h[2], h[3], 0.18)})
		if def.shade.has("sundial"):
			_add("sundial", def.shade.sundial[0], def.shade.sundial[1])
	for k in def.get("keys", []):
		_add("key", k[0], k[1], {"id": k[2]})
	for g in def.get("gems", []):
		_add("gem", g[0], g[1], {"id": g[2]})
	if def.has("secret"):
		_add("gem", def.secret[0], def.secret[1], {"id": SECRET_ID, "secret": true})
	for l in def.get("levers", []):
		_add("lever", l[0], l[1], {"id": l[2]})
	for p in def.get("plates", []):
		_add("plate", p[0], p[1], {"id": p[2]})
	for s in def.get("sluices", []):
		_add("sluice", s[0], s[1], {"id": s[2]})
	if def.has("falcon"):
		_add("falcon", def.falcon.at[0], def.falcon.at[1])
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
		for a in [[-2.6, 0.8], [2.6, 0.8], [2.8, -1.1]]:
			for side in [-1, 1]:
				static_rects.append(rect_for(a[0] + side * 0.775, a[1], 0.15, 0.25))
		static_rects.append([-3.85, -2.72, -2.86, -0.04])
		static_rects.append([-1.38, -0.25, -2.86, -0.04])
		mechanisms.append({"kind": "pool_bridge", "condition": "brickSocket", "id": 0, "x": -2.05, "z": -1.45,
			"rect": [-2.72, -1.38, -2.86, -0.04]})
	var brick: Dictionary = def.get("brick", {"at": [-2.6, 0.8], "sockets": [[-3.35, 0.08]]} if def.get("pool_room", false) else {})
	if not brick.is_empty():
		brick_mode = "floor"
		brick_at = Vector2(brick.at[0], brick.at[1])
		_add("brick", brick.at[0], brick.at[1])
		for i in brick.sockets.size():
			_add("brickSocket", brick.sockets[i][0], brick.sockets[i][1], {"id": i})
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


## Balanced pans. Classic levels need every weight on a pan; "free" balances let
## decoys stay on the floor (any subset whose two sides are equal and non-empty).
func balanced() -> bool:
	if not def.has("balance"):
		return false
	if not def.balance.get("free", false):
		for p in weight_places:
			if p != 0 and p != 1:
				return false
	elif carried >= 0:
		return false
	var s := pan_sums()
	var target: int = def.balance.get("target", 0)
	return s[0] == s[1] and s[0] > 0 and (target == 0 or s[0] == target)


func sequence_complete() -> bool:
	return def.has("sequence") and sequence == def.sequence.order.size()


func circuit_complete() -> bool:
	return def.has("circuit") and bits == (1 << int(def.circuit.count)) - 1


## Something heavy rests on plate `id`: a crate, a weight or the brick on the floor,
## or the falcon.
func plate_pressed(id: int) -> bool:
	for o in objects:
		if o.type != "plate" or o.id != id:
			continue
		var at := Vector2(o.x, o.z)
		if falcon_plate == id:
			return true
		for c in crates:
			if c.pos.distance_to(at) < PLATE_REACH:
				return true
		for w in objects:
			if w.type == "weight" and weight_places[w.id] == -1 and Vector2(w.x, w.z).distance_to(at) < PLATE_REACH:
				return true
		if brick_mode == "floor" and brick_at.distance_to(at) < PLATE_REACH + 0.1:
			return true
	return false


## Water reaches pool `id` through the falaj: channels open unless their sluice is shut.
func pool_full(id: int) -> bool:
	if not def.has("falaj"):
		return false
	var f: Dictionary = def.falaj
	var reached := {int(f.source): true}
	var grew := true
	while grew:
		grew = false
		for ch in f.channels:
			var gate: int = ch[2]
			if gate >= 0 and (sluices & (1 << gate)) == 0:
				continue
			for pair in [[ch[0], ch[1]], [ch[1], ch[0]]]:
				if reached.has(int(pair[0])) and not reached.has(int(pair[1])):
					reached[int(pair[1])] = true
					grew = true
	for p in f.pools:
		if int(p[1]) == id and reached.has(int(p[0])):
			return true
	return false


## Water currently flows along channel `i` (both ends wet, gate open).
func channel_wet(i: int) -> bool:
	if not def.has("falaj"):
		return false
	var ch: Array = def.falaj.channels[i]
	if ch[2] >= 0 and (sluices & (1 << int(ch[2]))) == 0:
		return false
	return _node_wet(int(ch[0])) or _node_wet(int(ch[1]))


func _node_wet(n: int) -> bool:
	var f: Dictionary = def.falaj
	if n == int(f.source):
		return true
	for p in f.pools:
		if int(p[0]) == n:
			return pool_full(int(p[1]))
	# interior node: wet when an open channel joins it to the source
	var reached := {int(f.source): true}
	var grew := true
	while grew:
		grew = false
		for ch in f.channels:
			if ch[2] >= 0 and (sluices & (1 << int(ch[2]))) == 0:
				continue
			for pair in [[ch[0], ch[1]], [ch[1], ch[0]]]:
				if reached.has(int(pair[0])) and not reached.has(int(pair[1])):
					reached[int(pair[1])] = true
					grew = true
	return reached.has(n)


## Where a palm's shadow falls in the current sun phase.
func shadow_points() -> Array:
	var out: Array = []
	if not def.has("shade"):
		return out
	var path: Array = def.shade.path
	var off: Array = path[sun % path.size()]
	for p in def.shade.palms:
		out.append(Vector2(p[0] + off[0], p[1] + off[1]))
	return out


func shaded(id: int) -> bool:
	var h: Array = def.shade.hot[id]
	for s in shadow_points():
		if absf(s.x - h[0]) < h[2] / 2.0 + 0.05 and absf(s.y - h[1]) < h[3] / 2.0 + 0.05:
			return true
	return false


func condition(type: String, id := 0) -> bool:
	match type:
		"brickSocket": return brick_mode == "socket"
		"dials": return dials_match()
		"balance": return balanced()
		"light": return light
		"lamp": return (lamps_lit & (1 << id)) != 0
		"keyChoice": return choice == id and (keys & 1) != 0
		"lock": return (unlocked & (1 << id)) != 0
		"choice": return choice == id
		"litChoice": return choice == id and light
		"circuit": return circuit_complete()
		"final": return (keys & 1) != 0 and sequence_complete()
		"plate": return plate_pressed(id)
		"pool": return pool_full(id)
		"shade": return shaded(id)
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
	for p in def.get("need_plates", []):
		if not plate_pressed(p):
			return false
	for p in def.get("need_pools", []):
		if not pool_full(p):
			return false
	var lamps_needed: int = def.get("need_lamps", 0)
	if (lamps_lit & lamps_needed) != lamps_needed:
		return false
	return true


func has_secret() -> bool:
	return (gems & (1 << SECRET_ID)) != 0


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
	var ex := LevelData.exit_x(def)
	if z < bounds[2]:
		if not solved or absf(x - ex) > 0.29 or z < -4.43:
			return true
	elif x < bounds[0] or x > bounds[1] or z > bounds[3]:
		return true
	for r in (rects if rects != null else active_rects()):
		if x > r[0] and x < r[1] and z > r[2] and z < r[3]:
			return true
	if not ignore_crates:
		for c in crates:
			var h := FREE_CRATE_HALF if c.free else CRATE_HALF
			if absf(x - c.pos.x) < h and absf(z - c.pos.y) < h:
				return true
	return false


func hero_blocked() -> bool:
	return blocked(hero.x, hero.y)


# --- snapshots (undo, and reverting rejected actions) ----------------------------

func snapshot() -> Dictionary:
	var crate_state: Array = []
	for c in crates:
		crate_state.append([c.pos, c.done])
	return {"keys": keys, "gems": gems, "unlocked": unlocked, "choice": choice, "bits": bits,
		"sequence": sequence, "dials": dial_values.duplicate(), "weights": weight_places.duplicate(),
		"carried": carried, "brick_mode": brick_mode, "brick_at": brick_at, "hero": hero,
		"crates": crate_state, "sluices": sluices, "sun": sun, "falcon_used": falcon_used,
		"falcon_plate": falcon_plate,
		"weight_at": objects.filter(func(o): return o.type == "weight").map(func(o): return Vector2(o.x, o.z)),
		"mirrors": objects.filter(func(o): return o.type == "mirror").map(func(o): return o.dir)}


func restore(s: Dictionary) -> void:
	keys = s.keys; gems = s.gems; unlocked = s.unlocked; choice = s.choice; bits = s.bits
	sequence = s.sequence; dial_values = s.dials.duplicate(); weight_places = s.weights.duplicate()
	carried = s.carried; brick_mode = s.brick_mode; brick_at = s.brick_at
	sluices = s.get("sluices", 0); sun = s.get("sun", 0)
	falcon_used = s.get("falcon_used", false); falcon_plate = s.get("falcon_plate", -1)
	if s.has("hero"):
		hero = s.hero
	if s.has("crates"):
		for i in crates.size():
			crates[i].pos = s.crates[i][0]
			crates[i].done = s.crates[i][1]
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
	_refresh()


# Kept for the old call sites.
func _snapshot() -> Dictionary:
	return snapshot()


func _restore(s: Dictionary) -> void:
	var h := hero
	restore(s)
	hero = h


# --- actions -----------------------------------------------------------------
# Each returns {"ok": bool, "event": String} so presentation can react
# (animation, sound) without the rules knowing about either.

func is_visible(o: Dictionary) -> bool:
	match o.type:
		"key": return (keys & (1 << o.id)) == 0
		"gem": return (gems & (1 << o.id)) == 0
		"weight": return weight_places[o.id] == -1
		"brick": return brick_mode != "carried"
		"falcon": return not falcon_used
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
			event = "secret" if o.get("secret", false) else "gem"
		"lock":
			if (keys & (1 << o.id)) == 0:
				return _reject("locked")
			unlocked |= 1 << o.id
			event = "unlock"
		"lever":
			choice = 1 - choice
			event = "lever"
		"sluice":
			sluices ^= 1 << o.id
			event = "sluice"
		"sundial":
			event = "wait"  # the sun moves on (below)
		"plate", "falcon":
			return {"ok": true, "event": "none"}  # plates are pressed by weight; the falcon is sent
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
			if carried != -1 or brick_mode == "carried":
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
			if carried != -1:
				return _reject("hands_full")
			brick_mode = "carried"
			event = "pickup_brick"
		"brickSocket":
			if brick_mode == "socket" and brick_at.distance_to(Vector2(o.x, o.z)) < 0.05:
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
	return _commit(before, event)


## Shared tail of every action: the sun moves on, the light is re-traced, and the
## action is undone if it would close something on the hero.
func _commit(before: Dictionary, event: String) -> Dictionary:
	if def.has("shade"):
		sun += 1
	_trace_light()
	_refresh()
	if hero_blocked():
		_restore(before)
		_refresh()
		return _reject("would_trap")
	changed.emit()
	return {"ok": true, "event": event}


func _reject(reason: String) -> Dictionary:
	return {"ok": false, "event": "reject", "reason": reason}


## The falcon «شاهين»: once per level it flies to a key (brings it back) or settles
## on a pressure plate and stays there. The hero needs no path to the target.
func falcon_can(o: Dictionary) -> bool:
	return def.has("falcon") and not falcon_used and is_visible(o) and o.type in ["key", "plate"]


func send_falcon(o: Dictionary) -> Dictionary:
	if not falcon_can(o):
		return _reject("falcon_unavailable")
	var before := _snapshot()
	falcon_used = true
	if o.type == "key":
		keys |= 1 << o.id
	else:
		falcon_plate = o.id
	return _commit(before, "falcon")


## Free crates: is the tile `to` clear for a crate (walls, gates, other crates,
## objects on the floor)? Plates may be covered: that is what they are for.
func crate_spot_free(index: int, to: Vector2) -> bool:
	if to.x < bounds[0] + 0.3 or to.x > bounds[1] - 0.3 or to.y < bounds[2] + 0.3 or to.y > bounds[3] - 0.3:
		return false
	var rects := active_rects()
	for q in rects:
		if to.x + 0.42 > q[0] + PAD and to.x - 0.42 < q[1] - PAD and to.y + 0.42 > q[2] + PAD and to.y - 0.42 < q[3] - PAD:
			return false
	for j in crates.size():
		if j != index and crates[j].pos.distance_to(to) < 0.9:
			return false
	for o in objects:
		if o.type in ["plate", "lock"] or not is_visible(o):
			continue
		if Vector2(o.x, o.z).distance_to(to) < 0.6:
			return false
	return true


## Push a free crate one tile along `dir` (unit, axis-aligned). The hero ends one
## tile behind the crate's new position.
func push_crate(index: int, dir: Vector2) -> Dictionary:
	var c: Dictionary = crates[index]
	if not c.free:
		return _reject("not_free")
	var to: Vector2 = c.pos + dir
	if not crate_spot_free(index, to):
		return _reject("crate_blocked")
	var before := _snapshot()
	c.pos = to
	hero = to - dir * 0.95
	if hero_blocked():
		_restore(before)
		return _reject("crate_blocked")
	return _commit(before, "crate_push")


## Pull a free crate one tile toward the hero: the hero steps back one tile.
func pull_crate(index: int, dir: Vector2) -> Dictionary:
	var c: Dictionary = crates[index]
	if not c.free:
		return _reject("not_free")
	var to: Vector2 = c.pos - dir
	var back: Vector2 = to - dir * 0.95
	if not crate_spot_free(index, to) or blocked(back.x, back.y, true):
		return _reject("no_room")
	for j in crates.size():
		if j != index and absf(back.x - crates[j].pos.x) < FREE_CRATE_HALF and absf(back.y - crates[j].pos.y) < FREE_CRATE_HALF:
			return _reject("no_room")
	var before := _snapshot()
	c.pos = to
	hero = back
	return _commit(before, "crate_pull")


## Where the hero stands to push free crate `index` along `dir`.
func free_push_position(index: int, dir: Vector2) -> Vector2:
	return crates[index].pos - dir * 0.95


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
		if p.x < bounds[0] + 0.25 or p.x > bounds[1] - 0.25 or p.y < bounds[2] + 0.33 or p.y > bounds[3] - 0.4:
			continue
		var r := [p.x - 0.32, p.x + 0.32, p.y - 0.32, p.y + 0.32]
		var blocked := false
		for q in obstacles:
			if r[0] < q[1] and r[1] > q[0] and r[2] < q[3] and r[3] > q[2]:
				blocked = true
				break
		for o in objects:  # keep a clear gap from other floor objects (plates may be covered)
			if not blocked and o.type not in ["weight", "lock", "plate"] and is_visible(o) and Vector2(o.x, o.z).distance_to(p) < 0.6:
				blocked = true
		for o in objects:
			if not blocked and o.type == "weight" and o.id != carried and weight_places[o.id] == -1 and Vector2(o.x, o.z).distance_to(p) < 0.62:
				blocked = true
		if blocked:
			continue
		var before := _snapshot()
		for o in objects:
			if o.type == "weight" and o.id == carried:
				o.x = p.x
				o.z = p.y
		weight_places[carried] = -1
		carried = -1
		if not _commit(before, "drop_weight").ok:
			continue
		return p
	return null


## Put the carried brick down near the hero. Returns the drop point or null.
## Never places it inside walls, water, closed gates or off the board.
func drop_brick(facing_yaw: float) -> Variant:
	if brick_mode != "carried":
		return null
	var obstacles := active_rects()
	for i in 8:
		var a := facing_yaw + i * PI / 4.0
		var x := hero.x + sin(a) * 1.12
		var z := hero.y + cos(a) * 1.12
		if x < bounds[0] + 0.2 or x > bounds[1] - 0.2 or z < bounds[2] + 0.28 or z > bounds[3] - 0.35:
			continue
		var r := [x - 0.47, x + 0.47, z - 0.29, z + 0.29]
		var hit := false
		for q in obstacles:
			if r[0] < q[1] and r[1] > q[0] and r[2] < q[3] and r[3] > q[2]:
				hit = true
				break
		if hit:
			continue
		var before := _snapshot()
		brick_mode = "floor"
		brick_at = Vector2(x, z)
		if not _commit(before, "drop_brick").ok:
			continue
		return brick_at
	return null


## Scripted crates (levels with a fixed destination): finish a push.
func complete_push(index: int) -> void:
	var c: Dictionary = crates[index]
	c.pos = c.to
	c.done = true
	if def.has("shade"):
		sun += 1
	_trace_light()
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
	lamps_lit = 0
	if not def.has("optics"):
		return
	var cfg: Dictionary = def.optics
	var x: float = cfg.source[0]
	var z: float = cfg.source[1]
	var dx: float = cfg.source[2]
	var dz: float = cfg.source[3]
	var mirrors := objects.filter(func(o): return o.type == "mirror")
	var portals := objects.filter(func(o): return o.type == "portal") if cfg.get("through_portals", false) else []
	var lamp_list: Array = cfg.get("lamps", [])
	var lim_x := maxf(absf(bounds[0]), absf(bounds[1])) + 0.17
	var lim_z := maxf(absf(bounds[2]), absf(bounds[3])) + 0.2
	for bounce in 16:
		var distance: float
		if dx > 0: distance = lim_x - x
		elif dx < 0: distance = x + lim_x
		elif dz > 0: distance = lim_z - z
		else: distance = z + lim_z
		var hit = null
		var candidates: Array = []
		for m in mirrors:
			candidates.append({"x": m.x, "z": m.z, "mirror": m})
		for p in portals:
			candidates.append({"x": p.x, "z": p.z, "portal": p})
		if cfg.has("receiver"):
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
		# Crates block the beam too.
		for c in crates:
			var along: float = (c.pos.x - x) * dx + (c.pos.y - z) * dz
			var off: float = absf((c.pos.x - x) * dz - (c.pos.y - z) * dx)
			if along > 0.3 and off < 0.45 and along - 0.45 < distance:
				distance = along - 0.45
				hit = null
		var end := Vector2(x + dx * distance, z + dz * distance)
		# Lamps along the segment light up; the beam passes through them.
		for l in lamp_list:
			var along: float = (l[0] - x) * dx + (l[1] - z) * dz
			var off: float = absf((l[0] - x) * dz - (l[1] - z) * dx)
			if along > 0.02 and along < distance + 0.01 and off < 0.08:
				lamps_lit |= 1 << int(l[2])
		light_segments.append([Vector2(x, z), end])
		if hit == null:
			break
		if hit.has("receiver"):
			light = true
			break
		if hit.has("portal"):
			x = hit.portal.tx
			z = hit.portal.tz
			continue
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
	var crate_pos := ""
	for i in crates.size():
		if crates[i].done:
			crate_bits |= 1 << i
		if crates[i].free:
			crate_pos += str(crates[i].pos.snapped(Vector2(0.01, 0.01)))
	var wpos := ""
	if def.has("balance") and def.balance.get("free", false) or not def.get("plates", []).is_empty():
		for o in objects:
			if o.type == "weight" and weight_places[o.id] == -1:
				wpos += str(Vector2(o.x, o.z).snapped(Vector2(0.5, 0.5)))
	var phase: int = (sun % int(def.shade.path.size())) if def.has("shade") else 0
	return "%d|%d|%d|%d|%d|%d|%s|%s|%s|%d|%s|%s|%d|%s|%d|%d|%d|%d|%s" % [keys, gems, unlocked, choice, bits, sequence,
		str(mirrors), str(dial_values), str(weight_places), carried, brick_mode,
		str(brick_at.snapped(Vector2(0.01, 0.01))), crate_bits, crate_pos, sluices, phase,
		int(falcon_used), falcon_plate, wpos]


func clone() -> PuzzleState:
	var s := PuzzleState.new(level, def)
	s.restore(snapshot())
	return s
