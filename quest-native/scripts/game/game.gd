class_name Game
extends Node3D
## Level lifecycle and the bridge between input, rules and presentation.
## Lives under the BoardPlacement node, so everything here is in board units.

signal level_loaded(n: int)
signal level_completed(n: int)
signal feedback(event: String, at: Vector3)  # consumed by audio
signal mechanism(kind: String, opened: bool, at: Vector3)

var level := 1
var state: PuzzleState
var motor: HeroMotor
var view: LevelView
var hero: HeroView
var transition := 0.0  # 0 = visible, 1 = faded out
var _pending_level := -1
var _fade_dir := 0.0
var marker: MeshInstance3D
var _marker_t := 10.0
var weather_rect_cache := {}


func _ready() -> void:
	hero = HeroView.new()
	hero.name = "Hero"
	add_child(hero)
	marker = Kit.add(self, Kit.torus(0.1, 0.13), Kit.mat("glow"), Vector3.ZERO, false)
	marker.visible = false


func load_level(n: int) -> void:
	level = clampi(n, 1, LevelData.COUNT)
	if view:
		view.queue_free()
		view = null
	state = PuzzleState.new(level)
	motor = HeroMotor.new(state)
	motor.acted.connect(_on_acted)
	motor.push_started.connect(func(i): feedback.emit("push_start", _w(state.crates[i].pos)))
	motor.push_finished.connect(_on_push_finished)
	motor.exit_started.connect(func(): feedback.emit("exit", _w(Vector2(LevelData.EXIT_X, -3.6))))
	motor.level_finished.connect(_on_level_finished)
	motor.brick_dropped.connect(func(at): feedback.emit("drop_brick", _w(at)))
	state.changed.connect(_on_state_changed)
	view = LevelView.new()
	view.name = "Level%02d" % level
	add_child(view)
	view.build(state)
	view.mechanism_changed.connect(func(k, o, at): mechanism.emit(k, o, at))
	move_child(view, 0)
	hero.reset(motor)
	_was_solved = state.solved
	level_loaded.emit(level)


func _w(p: Vector2) -> Vector3:
	return Vector3(p.x, LevelData.surface_y(state.def, p.x, p.y) + 0.3, p.y)


var _was_solved := false


func _on_state_changed() -> void:
	if state.solved and not _was_solved:
		feedback.emit("solved", _w(Vector2(LevelData.EXIT_X, -3.2)))
		hero.react("solved")
	_was_solved = state.solved


func _on_acted(o: Dictionary, r: Dictionary) -> void:
	var at := _w(Vector2(o.get("x", motor.pos.x), o.get("z", motor.pos.y)))
	if r.ok:
		feedback.emit(r.event, at)
		hero.react(r.event)
	else:
		feedback.emit("reject", at)
		hero.react("reject")


func _on_push_finished(_i: int) -> void:
	feedback.emit("crate_settle", _w(motor.pos))
	_on_state_changed()


func _on_level_finished() -> void:
	level_completed.emit(level)


## Fade out, swap level, fade in.
func go_to_level(n: int) -> void:
	_pending_level = n
	_fade_dir = 1.0


func restart() -> void:
	go_to_level(level)


func busy_transition() -> bool:
	return _fade_dir != 0.0


## Called every frame with the movement stick already mapped to board axes.
func tick(dt: float, move: Vector2) -> void:
	if _fade_dir != 0.0:
		transition = clampf(transition + _fade_dir * dt / 0.45, 0.0, 1.0)
		if transition >= 1.0 and _fade_dir > 0.0:
			load_level(_pending_level)
			_fade_dir = -1.0
		elif transition <= 0.0 and _fade_dir < 0.0:
			_fade_dir = 0.0
		move = Vector2.ZERO
	# Short, comfortable transition: the miniature sinks into its plinth and rises again.
	var sink := smoothstep(0.0, 1.0, transition)
	scale = Vector3(1.0, maxf(1.0 - sink, 0.02), 1.0)
	visible = sink < 0.99
	if state == null:
		return
	motor.update(dt, move)
	view.sync(dt, motor.pos)
	hero.sync(dt)
	_marker_t += dt
	marker.visible = _marker_t < 0.8
	if marker.visible:
		var k := _marker_t / 0.8
		marker.scale = Vector3.ONE * (1.0 + k * 0.6)
		marker.transparency = k


# --- picking (board-local ray) ---------------------------------------------------------

static func ray_box(o: Vector3, d: Vector3, center: Vector3, half: Vector3) -> float:
	var tmin := -INF
	var tmax := INF
	for a in 3:
		if absf(d[a]) < 1e-9:
			if o[a] < center[a] - half[a] or o[a] > center[a] + half[a]:
				return INF
		else:
			var t1 := (center[a] - half[a] - o[a]) / d[a]
			var t2 := (center[a] + half[a] - o[a]) / d[a]
			tmin = maxf(tmin, minf(t1, t2))
			tmax = minf(tmax, maxf(t1, t2))
	if tmax < maxf(tmin, 0.0):
		return INF
	return maxf(tmin, 0.0)


func _floor_hit(o: Vector3, d: Vector3) -> Dictionary:
	var best := {}
	var best_t := INF
	var storeys: bool = state.def.get("storeys", false)
	var heights := [0.065, LevelData.UPPER_HEIGHT + 0.065] if storeys else [0.065]
	for y in heights:
		if absf(d.y) < 1e-6:
			continue
		var t: float = (y - o.y) / d.y
		if t <= 0.0 or t >= best_t:
			continue
		var p := o + d * t
		if p.x < -4.0 or p.x > 4.0 or p.z < -4.5 or p.z > 3.6:
			continue
		if storeys and ((y < 1.0 and p.z < 0.95) or (y > 1.0 and p.z > -0.95)):
			continue
		best_t = t
		best = {"t": t, "point": p}
	if storeys:
		# Stair ramps.
		for s in state.def.stairs:
			for step in 24:
				var z0 := 0.95 - step * 1.9 / 24.0
				var z1 := z0 - 1.9 / 24.0
				var y := LevelData.surface_y(state.def, s[0], (z0 + z1) / 2.0)
				var t := ray_box(o, d, Vector3(s[0], y, (z0 + z1) / 2.0), Vector3(0.64, 0.05, 0.04))
				if t < best_t:
					best_t = t
					best = {"t": t, "point": o + d * t}
	return best


## Returns what the ray points at: {kind, t, point(local), obj?, index?}.
func pick(o: Vector3, d: Vector3) -> Dictionary:
	if state == null:
		return {}
	var best := {}
	var best_t := INF
	for obj in state.objects:
		if not state.is_visible(obj) or (obj.type == "lock" and state.condition("lock", obj.id)):
			continue
		var flat: bool = obj.type in ["sequence", "portal", "circuit", "dial", "brickSocket"]
		var y := LevelData.surface_y(state.def, obj.x, obj.z)
		var half := Vector3(0.45, 0.17, 0.45) if flat else Vector3(0.38, 0.5, 0.38)
		var c := Vector3(obj.x, y + (0.18 if flat else 0.5), obj.z)
		if obj.type == "lock":
			c.y = y + 0.55
			half = Vector3(0.3, 0.5, 0.3)
		var t := ray_box(o, d, c, half)
		if t < best_t:
			best_t = t
			best = {"kind": "object", "obj": obj}
	for i in state.crates.size():
		var cp: Vector2 = state.crates[i].pos
		var t := ray_box(o, d, Vector3(cp.x, 0.55, cp.y), Vector3(0.52, 0.55, 0.52))
		if t < best_t:
			best_t = t
			best = {"kind": "crate", "index": i}
	var hy := LevelData.surface_y(state.def, motor.pos.x, motor.pos.y)
	var ht := ray_box(o, d, Vector3(motor.pos.x, hy + 0.65, motor.pos.y), Vector3(0.32, 0.65, 0.32))
	if ht < best_t:
		best_t = ht
		best = {"kind": "hero"}
	var ey := LevelData.exit_y(state.def)
	var et := ray_box(o, d, Vector3(LevelData.EXIT_X, ey + 0.8, -3.75), Vector3(0.9, 0.8, 0.5))
	if et < best_t:
		best_t = et
		best = {"kind": "exit"}
	var f := _floor_hit(o, d)
	if not f.is_empty() and f.t < best_t:
		best_t = f.t
		best = {"kind": "floor"}
	if best.is_empty():
		return {}
	best["t"] = best_t
	best["point"] = o + d * best_t
	best["interactive"] = best.kind != "floor"
	return best


func activate(hit: Dictionary) -> void:
	if hit.is_empty() or motor.busy() or busy_transition():
		return
	match hit.kind:
		"object":
			motor.use_object(hit.obj)
		"crate":
			if not motor.start_push(hit.index):
				feedback.emit("reject", hit.point)
		"hero":
			if motor.carrying() == "brick":
				motor.drop_brick()
			else:
				hero.react("think")
				feedback.emit("think", hit.point)
		"exit":
			motor.start_exit()
		"floor":
			var p: Vector3 = hit.point
			# Point at a crate's plate: walk round and push it.
			for i in state.crates.size():
				var c: Dictionary = state.crates[i]
				if not c.done and absf(p.x - c.to.x) < 0.62 and absf(p.z - c.to.y) < 0.62:
					motor.start_push(i)
					return
			if absf(p.x - LevelData.EXIT_X) < 0.82 and p.z < -2.8:
				motor.start_exit()
				return
			if motor.walk_to(Vector2(p.x, p.z)):
				marker.position = Vector3(p.x, LevelData.surface_y(state.def, p.x, p.z) + 0.08, p.z)
				_marker_t = 0.0
				feedback.emit("tap", p)
			else:
				feedback.emit("reject", p)
