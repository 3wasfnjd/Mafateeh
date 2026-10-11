extends Node
## Counts draw items (mesh instances x surfaces) per level as a static proxy
## for draw calls. Real frame timing must be measured on a Quest headset.

func _ready() -> void:
	var g := Game.new()
	add_child(g)
	await get_tree().process_frame
	var worst := 0
	var lines := []
	for n in range(1, LevelData.COUNT + 1):
		g.load_level(n)
		await get_tree().process_frame
		var draws := 0
		var tris := 0
		for mi in g.find_children("*", "MeshInstance3D", true, false):
			if mi.is_visible_in_tree() and mi.mesh:
				draws += mi.mesh.get_surface_count()
				for s in mi.mesh.get_surface_count():
					var arr = mi.mesh.surface_get_arrays(s)
					var idx = arr[Mesh.ARRAY_INDEX]
					tris += (idx.size() if idx else arr[Mesh.ARRAY_VERTEX].size()) / 3
		for mm in g.find_children("*", "MultiMeshInstance3D", true, false):
			if mm.is_visible_in_tree():
				draws += 1
		worst = maxi(worst, draws)
		lines.append("level %2d: %4d draw items, %6d triangles" % [n, draws, tris])
	print("\n".join(lines))
	print("DRAW_BUDGET worst=%d (limit 400): %s" % [worst, "PASS" if worst <= 400 else "FAIL"])
	get_tree().quit(0 if worst <= 400 else 1)
