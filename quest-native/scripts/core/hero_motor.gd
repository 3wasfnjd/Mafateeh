class_name HeroMotor
extends RefCounted
## Character control on the board plane, independent of visuals and input
## devices. Ported from the web reference (steerHero, update, startPush,
## startExit, approachObject) with an explicit "acting" phase so the
## character animation plays before the puzzle state changes.

signal acted(obj: Dictionary, result: Dictionary)
signal push_started(index: int)
signal push_finished(index: int)
signal exit_started
signal level_finished
signal walk_rejected(obj: Dictionary)
signal brick_dropped(at: Vector2)
signal weight_dropped(at: Vector2)

const SPEED := 1.6  # board units per second (an unhurried, brisk old man)
const MAX_DT := 0.04
const DEAD_ZONE := 0.18
const PUSH_TIME := 1.5
const FREE_PUSH_TIME := 0.9  # one tile, free crates
const FINISH_TIME := 2.0

var state: PuzzleState
var nav: Navigator
var yaw := 0.0
var mode := "idle"  # idle | steering | walking | acting | pushing | finishing | complete
var route: Array = []
var pending_obj = null  # object to use when the route ends
var act_obj = null
var act_time := 0.0
var act_duration := 0.0
var act_applied := false
var push_index := -1
var push_from := Vector2.ZERO
var push_dir := Vector2.ZERO  # free crates: direction of this push (or pull)
var pulling := false
var mode_time := 0.0
var needs_release := false  # stick must return to centre after an interruption
var speed_now := 0.0  # actual planar speed, units/s (drives the walk cycle)
var last_result := {}


func _init(s: PuzzleState) -> void:
	state = s
	nav = Navigator.new(s)
	yaw = s.def.get("start_yaw", PI)


var pos: Vector2:
	get: return state.hero
	set(v): state.hero = v


static func read_stick(raw: Vector2, dead_zone := DEAD_ZONE) -> Vector2:
	if not is_finite(raw.x) or not is_finite(raw.y):
		return Vector2.ZERO
	var length := raw.length()
	if length <= dead_zone:
		return Vector2.ZERO
	var strength := (minf(length, 1.0) - dead_zone) / (1.0 - dead_zone)
	return raw / length * strength


func busy() -> bool:
	return mode in ["acting", "pushing", "finishing", "complete"]


func carrying() -> String:
	if state.brick_mode == "carried":
		return "brick"
	if state.carried >= 0:
		return "weight"
	return ""


func cancel() -> void:
	## Input interruption (tracking loss, system menu, level change).
	route.clear()
	pending_obj = null
	if mode in ["steering", "walking"]:
		mode = "idle"
	needs_release = true
	speed_now = 0.0


# --- commands ------------------------------------------------------------------

func walk_to(target: Vector2) -> bool:
	if busy():
		return false
	var path := nav.find_path(pos, target)
	if path.is_empty():
		return false
	route = path
	pending_obj = null
	mode = "walking"
	return true


func use_object(o: Dictionary) -> bool:
	if busy() or not state.is_visible(o):
		return false
	var path := nav.route_to_object(o, pos)
	if path.is_empty():
		walk_rejected.emit(o)
		last_result = {"ok": false, "event": "reject", "reason": "unreachable"}
		acted.emit(o, last_result)
		return false
	route = path
	pending_obj = o
	mode = "walking"
	needs_release = true
	return true


## Tapping a free crate: when the hero stands at one of its sides he pulls it one
## tile toward himself; otherwise he walks to the nearest side, ready to push.
func use_crate(index: int) -> bool:
	if busy() or index < 0:
		return false
	var c: Dictionary = state.crates[index]
	if not c.free:
		return start_push(index)
	var best := Vector2.ZERO
	var best_d := INF
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var at: Vector2 = c.pos - d * 0.95
		if pos.distance_to(at) < 0.3:
			return _begin_free(index, d, true)
		if nav.blocked(at.x, at.y):
			continue
		var dist := pos.distance_to(at)
		if dist < best_d:
			best_d = dist
			best = d
	if best == Vector2.ZERO:
		return false
	var target: Vector2 = c.pos - best * 0.95
	var path := nav.find_path(pos, target)
	if path.is_empty():
		return false
	route = path
	pending_obj = {"type": "_face_crate", "index": index, "dx": best.x, "dz": best.y}
	mode = "walking"
	needs_release = true
	return true


## The falcon flies to `o` (a key or a plate) while the hero whistles.
func send_falcon(o: Dictionary) -> bool:
	if busy() or not state.falcon_can(o):
		return false
	route.clear()
	pending_obj = null
	var turn := Vector2(o.x, o.z) - pos
	if turn.length() > 0.01:
		yaw = atan2(turn.x, turn.y)
	_begin_act({"type": "_falcon", "target": o, "x": o.x, "z": o.z}, 0.9)
	return true


func start_push(index: int) -> bool:
	if busy() or index < 0 or state.crates[index].done:
		return false
	var at := state.push_position(index)
	var path := nav.find_path(pos, at)
	if path.is_empty() and pos.distance_to(at) > 0.05:
		return false
	route = path
	pending_obj = {"type": "_push", "index": index}
	mode = "walking"
	needs_release = true
	return true


func start_exit() -> bool:
	if busy():
		return false
	needs_release = true
	if not state.solved:
		walk_to(Vector2(LevelData.exit_x(state.def), -2.65))
		return false
	var path := nav.find_path(pos, Vector2(LevelData.exit_x(state.def), -4.38))
	if path.is_empty():
		return false
	route = path
	pending_obj = {"type": "_exit"}
	mode = "walking"
	return true


## Put the carried weight down: on the spot the player pointed at (walking there
## first), or right in front of the hero.
func drop_weight(at = null) -> bool:
	if busy() or state.carried < 0:
		return false
	if at != null and pos.distance_to(at) > 0.9:
		var path := nav.find_path(pos, at)
		if path.is_empty():
			return false
		route = path
		pending_obj = {"type": "_drop_weight", "x": at.x, "z": at.y}
		mode = "walking"
		needs_release = true
		return true
	var target: Vector2 = at if at != null else pos + Vector2(sin(yaw), cos(yaw)) * 0.75
	var spot = state.drop_weight(target, yaw)
	if spot == null:
		last_result = {"ok": false, "event": "reject", "reason": "no_room"}
		acted.emit({"type": "drop"}, last_result)
		return false
	route.clear()
	_begin_act({"type": "_drop", "x": spot.x, "z": spot.y}, 0.5)
	act_applied = true
	weight_dropped.emit(spot)
	return true


func drop_brick() -> bool:
	if busy() or state.brick_mode != "carried":
		return false
	var at = state.drop_brick(yaw)
	if at == null:
		last_result = {"ok": false, "event": "reject", "reason": "no_room"}
		acted.emit({"type": "drop"}, last_result)
		return false
	route.clear()
	_begin_act({"type": "_drop", "x": at.x, "z": at.y}, 0.5)
	act_applied = true  # state already changed; the animation just plays out
	brick_dropped.emit(at)
	return true


# --- per-frame -------------------------------------------------------------------

## `move` is the stick vector already converted into board axes (x, z),
## length <= 1 after the dead zone. Returns true when the hero moved.
func update(dt: float, move: Vector2) -> void:
	mode_time += dt
	var strength := move.length()
	if strength < 0.001:
		needs_release = false
		if mode == "steering":
			mode = "idle"
	elif not needs_release and not busy():
		_steer(dt, move)
	if mode == "walking":
		_follow_route(dt)
	elif mode == "acting":
		_update_act(dt)
	elif mode == "pushing":
		_update_push()
	elif mode == "finishing":
		if mode_time >= FINISH_TIME:
			mode = "complete"
			level_finished.emit()
	if mode in ["idle", "acting", "complete"] and strength < 0.001:
		speed_now = 0.0


func _set_mode(m: String) -> void:
	mode = m
	mode_time = 0.0


func _steer(dt: float, move: Vector2) -> void:
	var strength := minf(move.length(), 1.0)
	route.clear()
	pending_obj = null
	_set_mode("steering")
	var dir := move.normalized()
	# Pushing uses the crate's own direction and only from the correct side.
	for i in state.crates.size():
		var c: Dictionary = state.crates[i]
		if not c.done and dir.dot(c.dir) > 0.6 and pos.distance_to(state.push_position(i)) < 0.25:
			_begin_push(i)
			return
		if c.free:
			# Free crates: walking into a side face pushes it one tile along that axis.
			var axis := Vector2(signf(dir.x), 0) if absf(dir.x) > absf(dir.y) else Vector2(0, signf(dir.y))
			var rel: Vector2 = c.pos - pos
			if dir.dot(axis) > 0.8 and absf(rel.dot(axis) - 0.95) < 0.2 and absf(rel.dot(Vector2(axis.y, axis.x))) < 0.3:
				if _begin_free(i, axis, false):
					return
	if state.solved and absf(pos.x - LevelData.exit_x(state.def)) < 0.55 and pos.y < -2.75 and dir.y < -0.2:
		mode = "idle"
		start_exit()
		return
	var start := pos
	var distance := minf(dt, MAX_DT) * SPEED * strength
	var target := pos + dir * distance
	if nav.clear_segment(pos, target):
		pos = target
	else:
		# Slide along walls without cutting through gaps.
		var axes := [0, 1] if absf(dir.x) > absf(dir.y) else [1, 0]
		for axis in axes:
			var step := pos
			if axis == 0:
				step.x = target.x
			else:
				step.y = target.y
			if nav.clear_segment(pos, step):
				pos = step
	_turn_toward(dir, dt)
	speed_now = start.distance_to(pos) / maxf(minf(dt, MAX_DT), 1e-5)
	_auto_collect()


func _auto_collect() -> void:
	var hy := LevelData.surface_y(state.def, pos.x, pos.y)
	for o in state.objects:
		if (o.type == "key" or o.type == "gem") and state.is_visible(o):
			var p := Vector2(o.x, o.z)
			if pos.distance_to(p) < 0.42 and absf(hy - LevelData.surface_y(state.def, o.x, o.z)) < 0.4 \
					and nav.clear_segment(pos, p):
				_begin_act(o, 0.45)
				return


func _turn_toward(dir: Vector2, dt: float) -> void:
	var wanted := atan2(dir.x, dir.y)
	var delta := wrapf(wanted - yaw, -PI, PI)
	yaw += delta * minf(1.0, dt * 14.0)


func _follow_route(dt: float) -> void:
	var left := minf(dt, MAX_DT) * SPEED
	var start := pos
	while not route.is_empty() and left > 0.0:
		var p: Vector2 = route[0]
		var d := pos.distance_to(p)
		if d > 0.0001:
			_turn_toward(p - pos, dt)
		if d <= left:
			pos = p
			left -= d
			route.pop_front()
		else:
			pos += (p - pos) / d * left
			left = 0.0
	speed_now = start.distance_to(pos) / maxf(minf(dt, MAX_DT), 1e-5)
	if route.is_empty():
		var o = pending_obj
		pending_obj = null
		_set_mode("idle")
		if o == null:
			return
		match o.type:
			"_push": _begin_push(o.index)
			"_face_crate":
				var fd := Vector2(o.dx, o.dz)
				yaw = atan2(fd.x, fd.y)
			"_drop_weight":
				drop_weight()  # arrived: set it down just in front
			"_exit":
				_set_mode("finishing")
				exit_started.emit()
			_:
				var turn := Vector2(o.x, o.z) - pos
				if turn.length() > 0.01 and o.type != "portal" and o.type != "sequence":
					yaw = atan2(turn.x, turn.y)
				_begin_act(o, _act_time_for(o.type))
	elif mode == "walking":
		_auto_collect_in_route()


func _auto_collect_in_route() -> void:
	# Walking over a key or gem collects it, as when steering.
	if pending_obj != null and (pending_obj.type == "key" or pending_obj.type == "gem"):
		return
	for o in state.objects:
		if (o.type == "key" or o.type == "gem") and state.is_visible(o) and pos.distance_to(Vector2(o.x, o.z)) < 0.3:
			var r := state.activate(o)
			last_result = r
			acted.emit(o, r)


static func _act_time_for(type: String) -> float:
	match type:
		"key", "gem": return 0.45
		"weight", "brick", "brickSocket", "pan": return 0.7
		"portal": return 0.6
		"lock": return 0.6
	return 0.4


func _begin_act(o: Dictionary, duration: float) -> void:
	act_obj = o
	act_duration = duration
	act_applied = false
	speed_now = 0.0
	_set_mode("acting")


func _update_act(_dt: float) -> void:
	if not act_applied and mode_time >= act_duration * 0.5:
		act_applied = true
		if act_obj.type == "_falcon":
			last_result = state.send_falcon(act_obj.target)
			nav.invalidate()
			acted.emit(act_obj.target, last_result)
		elif not act_obj.type.begins_with("_"):
			last_result = state.activate(act_obj)
			nav.invalidate()
			acted.emit(act_obj, last_result)
	if mode_time >= act_duration:
		act_obj = null
		_set_mode("idle")


func _begin_free(index: int, dir: Vector2, pull: bool) -> bool:
	var c: Dictionary = state.crates[index]
	var ok := false
	if pull:
		var to: Vector2 = c.pos - dir
		var back: Vector2 = to - dir * 0.95
		ok = state.crate_spot_free(index, to) and not nav.blocked(back.x, back.y)
	else:
		ok = state.crate_spot_free(index, c.pos + dir)
	if not ok:
		last_result = {"ok": false, "event": "reject", "reason": "crate_blocked"}
		acted.emit({"type": "crate", "x": c.pos.x, "z": c.pos.y}, last_result)
		needs_release = true
		return false
	push_index = index
	push_from = c.pos
	push_dir = dir
	pulling = pull
	yaw = atan2(dir.x, dir.y)
	_set_mode("pushing")
	needs_release = true
	push_started.emit(index)
	return true


func _begin_push(index: int) -> void:
	push_dir = Vector2.ZERO
	pulling = false
	push_index = index
	push_from = state.crates[index].pos
	var dir: Vector2 = state.crates[index].dir
	yaw = atan2(dir.x, dir.y)
	_set_mode("pushing")
	needs_release = true
	push_started.emit(index)


func _update_push() -> void:
	var c: Dictionary = state.crates[push_index]
	if c.free:
		var tf := minf(1.0, mode_time / FREE_PUSH_TIME)
		var e := tf * tf * (3.0 - 2.0 * tf)
		var step := -push_dir if pulling else push_dir
		c.pos = push_from + step * e
		pos = c.pos - push_dir * 0.95
		speed_now = 1.0 / FREE_PUSH_TIME
		if tf >= 1.0:
			c.pos = push_from
			pos = push_from - push_dir * 0.95
			last_result = state.pull_crate(push_index, push_dir) if pulling else state.push_crate(push_index, push_dir)
			nav.invalidate()
			var i := push_index
			push_index = -1
			_set_mode("idle")
			push_finished.emit(i)
		return
	var t := minf(1.0, mode_time / PUSH_TIME)
	var ease := t * t * (3.0 - 2.0 * t)
	c.pos = push_from.lerp(c.to, ease)
	pos = c.pos - c.dir * 0.95
	speed_now = (c.to - push_from).length() / PUSH_TIME
	if t >= 1.0:
		state.complete_push(push_index)
		nav.invalidate()
		var i := push_index
		push_index = -1
		_set_mode("idle")
		push_finished.emit(i)


func crate_pos(index: int) -> Vector2:
	return state.crates[index].pos
