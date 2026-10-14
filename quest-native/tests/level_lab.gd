extends SceneTree
## Level design probe:  godot --headless --path . -s tests/level_lab.gd -- --level=N
## Prints what the hero can reach from the start and which objects respond.

func _initialize() -> void:
	var n := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			n = int(a.substr(8))
	var s := PuzzleState.new(n)
	var nav := Navigator.new(s)
	var f := nav.flood(s.hero)
	var count := 0
	for i in f.prev.size():
		if f.prev[i] != -2:
			count += 1
	print("level %d start %s blocked=%s reachable cells=%d solved=%s" % [n, str(s.hero), str(s.hero_blocked()), count, str(s.solved)])
	for o in s.objects:
		var path := nav.route_to_object(o, s.hero)
		print("  %-12s id=%d at (%.2f, %.2f) visible=%s reachable=%s" % [o.type, o.id, o.x, o.z, str(s.is_visible(o)), str(not path.is_empty() or s.hero.distance_to(Vector2(o.x, o.z)) < 0.9)])
	for m in s.mechanisms:
		print("  mech %-10s cond=%s id=%d open=%s" % [m.kind, m.condition, m.id, str(s.is_open(m))])
	print("  exit reachable: ", not nav.find_path(s.hero, Vector2(LevelData.exit_x(s.def), -4.38)).is_empty())
	quit()
