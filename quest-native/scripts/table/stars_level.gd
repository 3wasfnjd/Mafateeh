class_name TableStarsLevel
extends Node3D
## Level 7 on the table, «نجم سهيل» (Suhail's star). Wordless. Night.
## Scene 7: a caravan camped for the night among high dunes, camels couched, the old man by the
## fire. Over the diorama hangs the sky as three rings of stars round the Pleiades (الثريا).
## Each ring carries one bright star. Tap a ring and it turns an eighth, and the ring outside
## it turns with it (the outer ring turns alone). When the three bright stars stand in one
## line from the Pleiades towards the cairn in the gap of the dunes, with Suhail the last of
## them, the line lights up, the camels rise and the old man leads the caravan out.
##
## The night wind gusts now and then and pushes one ring round a notch (twice at most): no
## standing about admiring the sky. The ring the pointer is on glows.
##
## Lives under Diorama.stage: positions are in the diorama's own metres (Godot axes).

signal level_won

const SKY_Y := 8.5
const RADII := [2.4, 4.4, 6.4]
const SLOTS := 8
const TARGET := 2                 # slot 2 points south, towards the cairn (+z)
const START := [0, 6, 7]          # each ring's bright star starts here (slot): five taps away
const DECOYS := [[3, 6], [1, 4, 6], [1, 5]]   # dimmer stars on each ring, slots from its bright one
const FIRE := Vector3(1.6, 0, -0.6)
const CAIRN := Vector3(0.0, 0, 9.2)
const CAMELS := [[Vector3(3.0, 0, -3.4), 200.0], [Vector3(4.8, 0, -1.0), 250.0], [Vector3(-0.8, 0, -3.6), 160.0]]
const KNEEL := "res://assets/world/props/camel_kneeling.glb"
const STAND := "res://assets/world/props/camel_ride.glb"   # standing, its legs free to walk (build_mounts.py)
# After the win the caravan files out behind the old man: each camel its own way round the fire
# and the others (x, z waypoints), leaving one after another so they never meet.
const ROUTES := [
	[Vector2(5.4, -2.6), Vector2(5.2, 1.4), Vector2(3.7, 3.7)],                       # the east camel, last
	[Vector2(4.6, 1.6), Vector2(2.6, 5.0), Vector2(1.5, 6.9)],                        # the near one, first
	[Vector2(-2.0, -2.0), Vector2(-2.2, 2.4), Vector2(-1.0, 6.1)],                    # the west one
]
const LEAVE := [3.2, 0.4, 1.6]     # s after the old man sets off
const CAMEL_SPEED := 1.05          # m/s, a slow walk
const OLD_MAN := Vector3(0.6, 0, 0.3)
const HINT_AFTER := 20.0
const STAR := Color("f4f1e6")
const SUHAIL := Color("ffd27a")

var diorama: Diorama
var offsets: Array = START.duplicate()
var _rings: Array = []          # {node, bright}
var _busy := false
var _won := false
var _was_held := false
var _ray := []
var _idle_t := 0.0
var _t := 0.0
var _hint := -1
var _demo: Array = []
var _camels: Array = []
var _walkers: Array = []        # {node, legs, path: [Vector3], wait, phase}
var _fire: Node3D
var _gust_wait := 28.0
var _gusts := 2
var _hot := -1


func setup(d: Diorama) -> void:
	diorama = d
	if diorama.shaib:
		diorama.shaib.position = OLD_MAN
		TableKit.face(diorama.shaib, FIRE - OLD_MAN)
		diorama.play_shaib("sit_idle", "")
	var sky := Node3D.new()
	add_child(sky)
	sky.position = Vector3(0, SKY_Y, 0)
	# the Pleiades: a tight little cluster in the middle
	for i in 7:
		var a := TAU * i / 6
		var p := Vector3(cos(a), 0, sin(a)) * (0.0 if i == 6 else 0.32)
		TableKit.sphere(sky, 0.1, TableKit.lit_mat(STAR, 2.0), p, 6)
	for k in RADII.size():
		var ring := Node3D.new()
		sky.add_child(ring)
		var line := TableKit.ring(ring, RADII[k], Color("9fb2d8"), 0.35, 0.012)
		line.position.y = -0.02
		var bright := TableKit.sphere(ring, 0.32 if k == 2 else 0.22, TableKit.lit_mat(SUHAIL if k == 2 else STAR, 2.6), _slot_pos(k, 0), 8)
		for s in DECOYS[k]:
			TableKit.sphere(ring, 0.16, TableKit.lit_mat(STAR, 1.4), _slot_pos(k, s), 6)
		_rings.append({"node": ring, "bright": bright, "line": line})
		ring.rotation.y = -TAU * offsets[k] / SLOTS
	_line = TableKit.box(sky, Vector3(0.08, 0.08, RADII[2]), TableKit.lit_mat(SUHAIL, 2.0), Vector3(0, 0, RADII[2] / 2))
	_line.visible = false
	for c in CAMELS:
		var m := TableKit.model(self, KNEEL, c[0], deg_to_rad(c[1]))
		_camels.append(m)
	_fire = Node3D.new()
	add_child(_fire)
	_fire.position = FIRE
	for i in 4:
		var a := TAU * i / 4
		TableKit.cyl(_fire, 0.0, 0.14, 0.55, TableKit.lit_mat(Color("ff9a3c") if i % 2 else Color("ffd27a"), 2.5),
			Vector3(cos(a) * 0.14, 0.28, sin(a) * 0.14), 6)
	_show_aligned()


var _line: MeshInstance3D


func _slot_pos(k: int, s: int) -> Vector3:
	var a := TAU * s / SLOTS
	return Vector3(cos(a), 0, sin(a)) * RADII[k]


func aligned() -> bool:
	for k in offsets.size():
		if offsets[k] != TARGET:
			return false
	return true


## Turning ring k turns it and the ring outside it (the outer ring turns alone).
static func turned(o: Array, k: int) -> Array:
	var n := o.duplicate()
	n[k] = (n[k] + 1) % SLOTS
	if k + 1 < n.size():
		n[k + 1] = (n[k + 1] + 1) % SLOTS
	return n


## Shortest list of rings to tap from here.
func solution() -> Array:
	var goal := str([TARGET, TARGET, TARGET])
	var prev := {str(offsets): null}
	var queue: Array = [offsets]
	var head := 0
	while head < queue.size():
		var s: Array = queue[head]
		head += 1
		if str(s) == goal:
			var taps: Array = []
			var key := goal
			while prev[key] != null:
				taps.push_front(prev[key][1])
				key = prev[key][0]
			return taps
		for k in offsets.size():
			var n := turned(s, k)
			if not prev.has(str(n)):
				prev[str(n)] = [str(s), k]
				queue.append(n)
	return []


func aim(origin: Vector3, dir: Vector3) -> void:
	_ray = [origin, dir]


func pointer(held: bool, p) -> void:
	var pressed := held and not _was_held
	_was_held = held
	if not pressed or _busy or _won:
		return
	var best := _ring_under(_ray)
	if best >= 0:
		_tap(best)


## Where the ray crosses the sky (world), for the pointer; null off the sky.
func hover_point(ray: Array) -> Variant:
	var hit = _sky_hit(ray)
	return to_global(hit) if hit != null and _ring_under(ray) >= 0 else null


## Where the ray crosses the sky's plane picks the ring (-1: none near).
func _ring_under(ray: Array) -> int:
	var hit = _sky_hit(ray)
	if hit == null:
		return -1
	var r := Vector2(hit.x, hit.z).length()
	var best := -1
	var best_d := 1.0
	for k in RADII.size():
		if absf(r - RADII[k]) < best_d:
			best_d = absf(r - RADII[k])
			best = k
	return best


func _sky_hit(ray: Array) -> Variant:
	if ray.size() != 2:
		return null
	var o := to_local(ray[0])
	var d := to_local(ray[0] + ray[1]) - o
	if absf(d.y) < 1e-5:
		return null
	var t := (SKY_Y - o.y) / d.y
	if t < 0:
		return null
	return o + d * t


func _tap(k: int) -> void:
	_idle_t = 0.0
	_hint = -1
	_busy = true
	var n := turned(offsets, k)
	var tw := create_tween().set_parallel()
	for j in offsets.size():
		if n[j] != offsets[j]:
			var ring: Node3D = _rings[j].node
			tw.tween_property(ring, "rotation:y", ring.rotation.y - TAU / SLOTS, 0.45).set_trans(Tween.TRANS_SINE)
			TableKit.sfx(self, "dial_click", Vector3(0, SKY_Y, 0) + _slot_pos(j, 0), -6.0, 1.0 + 0.15 * j)
	offsets = n
	tw.chain().tween_callback(func():
		_busy = false
		_show_aligned()
		if aligned():
			_win())


## A bright star in its place swells a little: feedback for each ring on its own.
func _show_aligned() -> void:
	for k in _rings.size():
		var b: Node3D = _rings[k].bright
		b.scale = Vector3.ONE * (1.3 if offsets[k] == TARGET else 1.0)


func _win() -> void:
	_won = true
	TableKit.sfx(self, "success", Vector3(0, SKY_Y, 0), -2.0)
	_line.visible = true
	_line.rotation.y = 0.0
	_line.scale = Vector3(1, 1, 0.01)
	create_tween().tween_property(_line, "scale", Vector3.ONE, 1.2)
	# the camels rise; the old man stands and leads them out past the cairn
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_callback(func():
		for i in _camels.size():
			var old: Node3D = _camels[i]
			if old == null:
				continue
			var m := TableKit.model(self, STAND, old.position, old.rotation.y)
			old.queue_free()
			_camels[i] = m
		diorama.play_shaib("idle", ""))
	tw.tween_interval(0.8)
	tw.tween_callback(_set_off)
	tw.tween_interval(16.0)   # the caravan in its place behind him
	tw.tween_callback(func():
		TableKit.sfx(self, "level_complete", CAIRN)
		level_won.emit())


func _set_off() -> void:
	var lead := CAIRN + Vector3(0.8, 0, 0)
	if diorama.shaib:
		var sh := diorama.shaib
		TableKit.face(sh, lead - sh.position)
		diorama.play_shaib("walk", "")
		var t1 := create_tween()
		t1.tween_property(sh, "position", lead, sh.position.distance_to(lead) / 1.2)
		t1.tween_callback(func():
			TableKit.face(sh, Vector3(0, 0, -1))
			diorama.play_shaib("celebrate", "idle"))
	for i in _camels.size():
		var m: Node3D = _camels[i]
		if m == null:
			continue
		var legs := []
		for n in ["Leg_FL", "Leg_FR", "Leg_BL", "Leg_BR"]:
			var l := m.find_child(n, true, false)
			if l:
				legs.append(l)
		var path := []
		for w in ROUTES[i]:
			path.append(Vector3(w.x, 0, w.y))
		_walkers.append({"node": m, "legs": legs, "path": path, "wait": LEAVE[i], "phase": i * 1.3, "k": 0.0})


## The caravan walking: along each camel's waypoints at a slow pace, on the sand (never up on a
## rock), turning smoothly, legs pacing (both of a side together) while it moves.
func _walk(dt: float) -> void:
	for w in _walkers:
		var m: Node3D = w.node
		if not is_instance_valid(m):
			continue
		var moving := false
		if w.wait > 0.0:
			w.wait -= dt
		elif not (w.path as Array).is_empty():
			var to: Vector3 = w.path[0]
			var flat := Vector3(to.x - m.position.x, 0, to.z - m.position.z)
			if flat.length() < 0.15:
				w.path.pop_front()
			else:
				moving = true
				var want := atan2(flat.x, flat.z)
				m.rotation.y = lerp_angle(m.rotation.y, want, 1.0 - exp(-4.0 * dt))
				var fwd := Vector3(sin(m.rotation.y), 0, cos(m.rotation.y))
				# goes on along where it faces, so it walks round the bend instead of sliding sideways
				var lined := clampf(cos(angle_difference(m.rotation.y, want)), 0.15, 1.0)   # turns on the spot first
				m.position += fwd * minf(CAMEL_SPEED * lined * dt, flat.length())
		var target_k := 1.0 if moving else 0.0
		w.k = lerpf(w.k, target_k, 1.0 - exp(-5.0 * dt))
		m.position.y = _ground(m.position)
		var legs: Array = w.legs
		for i in legs.size():
			var off := 0.0 if i % 2 == 0 else PI
			(legs[i] as Node3D).rotation.x = w.k * 0.42 * sin(_t * 4.2 + float(w.phase) + off)


func _ground(p: Vector3) -> float:
	if diorama == null:
		return 0.0
	var y := INF
	for o in [Vector2.ZERO, Vector2(0.6, 0), Vector2(-0.6, 0), Vector2(0, 0.6), Vector2(0, -0.6)]:
		y = minf(y, diorama.top_at(p.x + o.x, p.z + o.y))
	return clampf(y, 0.0, 3.0)


func demo() -> void:
	_demo_on = true
	_demo = solution()


var _demo_on := false


## A gust of the night wind turns one ring a notch on its own: one already in place if there
## is one (it undoes a little of the player's work), never so that it solves the sky.
func _gust() -> void:
	_gusts -= 1
	_gust_wait = randf_range(25.0, 40.0)
	var k := -1
	for j in RADII.size():
		if offsets[j] == TARGET:
			k = j
			break
	if k < 0:
		k = randi() % RADII.size()
	var after := offsets.duplicate()
	after[k] = (after[k] + 1) % SLOTS
	if str(after) == str([TARGET, TARGET, TARGET]):
		return   # (cannot happen from an unsolved sky with one in place, but never gift the win)
	_busy = true
	_hint = -1
	TableKit.sfx(self, "bridge_move", Vector3(0, SKY_Y, 0), -6.0, 0.7)
	var ring: Node3D = _rings[k].node
	offsets[k] = (offsets[k] + 1) % SLOTS
	var tw := create_tween()
	tw.tween_property(ring, "rotation:y", ring.rotation.y - TAU / SLOTS, 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		_busy = false
		_show_aligned())


func _process(dt: float) -> void:
	_t += dt
	_walk(dt)
	for c in _fire.get_children():
		c.scale.y = 1.0 + 0.2 * sin(_t * 9.0 + c.position.x * 30.0)
	# the ring under the pointer glows
	var hot := -1 if _won else _ring_under(_ray)
	if hot != _hot:
		_hot = hot
		for k in _rings.size():
			var line: MeshInstance3D = _rings[k].line
			(line.material_override as StandardMaterial3D).albedo_color.a = 0.85 if k == hot else 0.35
	if _won or _busy:
		return
	if not _demo.is_empty():
		_tap(_demo.pop_front())
		return
	_gust_wait -= dt
	if _gust_wait <= 0.0 and _gusts > 0 and not _demo_on:
		_gust()
		return
	_idle_t += dt
	if _idle_t > HINT_AFTER:
		if _hint < 0:
			var s := solution()
			_hint = s[0] if not s.is_empty() else -1
		for k in _rings.size():
			var b: Node3D = _rings[k].bright
			var base := 1.3 if offsets[k] == TARGET else 1.0
			b.scale = Vector3.ONE * (base * (1.0 + 0.35 * maxf(0.0, sin(_t * 5.0))) if k == _hint else base)
