extends SceneTree
## Headless test runner:  godot --headless --xr-mode off --path quest-native -s tests/run_tests.gd
## Optional:  -- --levels=1,5,21   --skip-solver   --report=path.txt

var failures: Array = []
var lines: Array = []

# Gate mechanics that must be impossible to bypass: forbidding these object
# types must make the level unsolvable.
const BYPASS_CHECKS := {
	3: [["lock"]], 4: [["lever"]], 5: [["circuit"]], 8: [["portal"], ["lock"]], 9: [["lever"], ["mirror"]],
	10: [["circuit"], ["sequence"]], 11: [["dial"]], 12: [["weight"], ["pan"]], 13: [["circuit"]],
	14: [["dial"]], 15: [["weight"]], 16: [["mirror"]], 17: [["lever"], ["key"]], 18: [["portal"]],
	19: [["circuit"], ["weight"]], 20: [["lever"], ["key"]], 21: [["brick"], ["brickSocket"], ["lock"]],
}


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var parts := a.trim_prefix("--").split("=")
		args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	var levels: Array = []
	if args.has("levels"):
		for s in args.levels.split(","):
			levels.append(int(s))
	else:
		levels = range(1, LevelData.COUNT + 1)
	var t0 := Time.get_ticks_msec()
	_test_level_data()
	if not args.has("skip-solver"):
		for n in levels:
			_test_solver(n)
	if not args.has("skip-movement"):
		_test_movement()
	_test_save()
	var summary := "%d failure(s) in %.1fs" % [failures.size(), (Time.get_ticks_msec() - t0) / 1000.0]
	_log("")
	_log("RESULT: " + ("PASS" if failures.is_empty() else "FAIL") + " — " + summary)
	for f in failures:
		_log("  FAIL: " + f)
	if args.has("report"):
		var file := FileAccess.open(args.report, FileAccess.WRITE)
		if file:
			file.store_string("\n".join(lines) + "\n")
	quit(0 if failures.is_empty() else 1)


func _log(s: String) -> void:
	print(s)
	lines.append(s)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		_log("  ✗ " + msg)


# --- data ----------------------------------------------------------------------

func _test_level_data() -> void:
	_log("== Level data")
	check(LevelData.LEVELS.size() == 21, "expected 21 levels")
	for n in range(1, 22):
		var s := PuzzleState.new(n)
		check(not s.hero_blocked(), "level %d: spawn is inside an obstacle" % n)
		check(s.def.time in ["dawn", "day", "sunset", "night"], "level %d: bad time preset" % n)
		check(s.def.weather in ["clear", "rain"], "level %d: bad weather preset" % n)
		for roof in s.def.get("roofs", []):
			for o in s.objects:
				var inside: bool = absf(o.x - roof[0]) < roof[2] / 2.0 and absf(o.z - roof[1]) < roof[3] / 2.0
				check(not inside, "level %d: %s %d hidden under a roof" % [n, o.type, o.id])
	_log("  21 levels, spawns clear, presets valid, no interactable under a roof")


# --- solver ----------------------------------------------------------------------

func _test_solver(n: int) -> void:
	var t0 := Time.get_ticks_msec()
	var solver := LevelSolver.new(n)
	var r := solver.run()
	check(r.ok, "level %d: no solution found (%s)" % [n, r.get("error", "")])
	if not r.ok:
		return
	var sol := solver.solution()
	var dead := solver.dead_ends()
	check(dead.is_empty(), "level %d: %d dead-end state(s), e.g. %s" % [n, dead.size(),
		solver.describe(dead[0]) if not dead.is_empty() else ""])
	_log("== Level %d — %s: solvable in %d actions, %d states explored, %d dead ends (%.1fs)" % [
		n, LevelData.get_level(n).title_en, sol.size(), r.states, dead.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	_log("   " + " → ".join(sol))
	for forbid in BYPASS_CHECKS.get(n, []):
		var b := LevelSolver.new(n, forbid)
		b.sample_drops = false
		var br := b.run()
		check(not br.ok, "level %d: solvable without using %s (bypass)" % [n, str(forbid)])
		_log("   without %s: %s" % [str(forbid), "unsolvable ✓" if not br.ok else "SOLVABLE ✗"])


# --- movement (ported from tests/game.mjs movementCases) ------------------------------

func _sim(m: HeroMotor, seconds: float, move := Vector2.ZERO) -> void:
	for i in int(seconds * 60.0):
		m.update(1.0 / 60.0, move)
		if m.mode in ["steering", "walking"]:
			check(not m.state.hero_blocked() or m.state.hero.y < -3.03,
				"collision at %s on level %d" % [str(m.pos), m.state.level])


func _motor(level: int) -> HeroMotor:
	return HeroMotor.new(PuzzleState.new(level))


func _test_movement() -> void:
	_log("== Movement")
	var m := _motor(3)
	var spawn := m.pos
	_sim(m, 2.0, Vector2(1, 0))
	check(m.pos.x > spawn.x + 0.5 and m.pos.x < -0.42, "stick must stop at interior wall (x=%.2f)" % m.pos.x)
	_sim(m, 1.0 / 60.0)
	var stop := m.pos
	_sim(m, 0.5)
	check(m.pos.distance_to(stop) < 1e-6, "release must stop immediately")
	_sim(m, 3.0, Vector2(-1, 0))
	check(m.pos.x >= -3.65, "stick must respect outer boundary")

	m = _motor(11)
	var start := m.pos
	_sim(m, 0.1, Vector2(1, -1).limit_length(1.0))
	var straight := _motor(11)
	var straight_start := straight.pos
	_sim(straight, 0.1, Vector2(1, 0))
	check(m.pos.distance_to(start) <= straight.pos.distance_to(straight_start) + 1e-4,
		"diagonal must not be faster than straight")
	check(m.pos.distance_to(start) <= 0.211, "diagonal speed must be capped")

	m = _motor(4)
	_sim(m, 3.0, Vector2(0, -1))
	check(m.pos.y >= 0.89, "stick cannot cross closed water (z=%.2f)" % m.pos.y)

	m = _motor(14)
	m.pos = Vector2(-2.9, 1.5)
	_sim(m, 1.4, Vector2(0, -1))
	var y := LevelData.surface_y(m.state.def, m.pos.x, m.pos.y)
	check(m.pos.y < -0.95 and y >= 2.09, "stick must walk upstairs (z=%.2f y=%.2f)" % [m.pos.y, y])
	_sim(m, 1.0 / 60.0)
	_sim(m, 1.4, Vector2(0, 1))
	y = LevelData.surface_y(m.state.def, m.pos.x, m.pos.y)
	check(m.pos.y > 0.95 and y < 0.01, "stick must walk downstairs")

	m = _motor(13)
	m.pos = Vector2(-2.9, 1.5)
	_sim(m, 2.0, Vector2(0, -1))
	check(m.pos.y >= 1.24, "closed stairs must block movement (z=%.2f)" % m.pos.y)

	m = _motor(1)
	_sim(m, 2.0, Vector2(1, 0))
	_sim(m, 2.0)
	check(m.state.crates[0].done, "stick should push crate from the correct side")
	m = _motor(1)
	m.pos = Vector2(2.6, 1.35)
	_sim(m, 1.0, Vector2(-1, 0))
	check(not m.state.crates[0].done, "crate must not be pushed from the wrong side")

	m = _motor(3)
	check(m.walk_to(Vector2(-2.5, 1.3)), "tap route setup")
	_sim(m, 0.1)
	_sim(m, 0.2, Vector2(-1, 0))
	_sim(m, 1.0 / 60.0)
	var cancelled := m.pos
	_sim(m, 0.8)
	check(m.pos.distance_to(cancelled) < 1e-6, "stick overrides tap route without resuming it")

	m = _motor(3)
	m.cancel()
	var before := m.pos
	_sim(m, 0.2, Vector2(1, 0))
	check(m.pos == before, "movement waits for stick release after an interruption")
	_sim(m, 1.0 / 60.0)
	_sim(m, 0.1, Vector2(1, 0))
	check(m.pos.x > before.x, "movement resumes after re-centring the stick")

	m = _motor(21)
	var brick: Dictionary = m.state.objects.filter(func(o): return o.type == "brick")[0]
	check(m.use_object(brick), "brick reachable")
	_sim(m, 8.0)
	check(m.carrying() == "brick", "brick lifted")
	_sim(m, 0.3, Vector2(0, -1))
	check(m.carrying() == "brick", "carried brick stays attached while steering")
	_sim(m, 1.0 / 60.0)
	check(m.drop_brick(), "brick can be put down")
	_sim(m, 1.0)
	check(m.state.brick_mode == "floor", "brick on floor after drop")
	var bx: Vector2 = m.state.brick_at
	check(not m.nav.blocked(m.pos.x, m.pos.y), "drop must not trap the hero")
	check(bx.x > -3.45 and bx.x < 3.45, "drop stays on the board")

	m = _motor(3)
	var key: Dictionary = m.state.objects.filter(func(o): return o.type == "key")[0]
	m.pos = Vector2(key.x - 0.5, key.z)
	_sim(m, 0.2, Vector2(1, 0))
	_sim(m, 1.0)
	check(m.state.keys == 1, "walking onto a key collects it")

	check(HeroMotor.read_stick(Vector2(0.1, 0.1)) == Vector2.ZERO, "dead zone filters drift")
	check(HeroMotor.read_stick(Vector2(2, 0)).length() <= 1.0001, "stick magnitude capped at 1")
	check(HeroMotor.read_stick(Vector2(NAN, 0)) == Vector2.ZERO, "invalid stick input ignored")

	# Level 21 full scripted run, as in the web test.
	m = _motor(21)
	for type in ["brick", "brickSocket", "key", "lock", "gem"]:
		var o: Dictionary = m.state.objects.filter(func(q): return q.type == type)[0]
		check(m.use_object(o), "level 21: cannot reach %s from %s" % [type, str(m.pos)])
		_sim(m, 14.0)
	check(m.state.brick_mode == "socket", "level 21: brick on socket")
	check(m.state.solved, "level 21: solved after scripted run")
	check(m.start_exit(), "level 21: exit reachable")
	_sim(m, 15.0)
	check(m.mode == "complete", "level 21: completes through the exit")
	_log("  release, walls, water, stairs, crates, tap override, interruption, carrying, keys, level 21 run")


func _test_save() -> void:
	_log("== Save data")
	var save = load("res://scripts/core/save_data.gd").new()
	save.reset_progress()
	check(not save.can_play(5) or save.dev_tools_available(), "level 5 locked on a fresh save")
	save.mark_completed(1)
	save.mark_completed(2)
	var again = load("res://scripts/core/save_data.gd").new()
	again.load_data()
	check(again.unlocked_level == 3, "progress survives reload (unlocked=%d)" % again.unlocked_level)
	check(again.current_level == 3, "current level survives reload")
	save.reset_progress()
	save.free()
	again.free()
	_log("  progressive unlock and persistence")
