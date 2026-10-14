# Close portrait of the hero on a transparent background, rendered by Godot
# (replaces the Blender step when Blender isn't available).
# xvfb-run -a godot --rendering-driver opengl3 --resolution 1024x1024 --path quest-native \
#   --script res://tools/store/render_portrait.gd -- <out.png> [dist] [target_y]
extends SceneTree

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/hero_portrait.png"
	var dist: float = float(args[1]) if args.size() > 1 else 1.55
	var target_y: float = float(args[2]) if args.size() > 2 else 0.93
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	get_root().transparent_bg = true
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.86, 0.7)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root3d.add_child(we)
	var hero: Node3D = (load("res://assets/character/shaib.glb") as PackedScene).instantiate()
	root3d.add_child(hero)
	var ap := _find_player(hero)
	if ap:
		for n in ap.get_animation_list():
			if n.ends_with("idle"):
				ap.play(n)
				ap.seek(0.0, true)
				ap.pause()
				break
	var key := DirectionalLight3D.new()
	key.light_energy = 1.25
	key.light_color = Color(1.0, 0.95, 0.88)
	root3d.add_child(key)
	key.look_at_from_position(Vector3(0.6, 1.6, 1.0), Vector3(0, 0.9, 0))
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.6
	root3d.add_child(rim)
	rim.look_at_from_position(Vector3(-0.7, 1.4, -0.8), Vector3(0, 0.9, 0))
	var cam := Camera3D.new()
	cam.fov = 24.0
	root3d.add_child(cam)
	var target := Vector3(0, target_y, 0)
	var d := Vector3(0.32, 0.12, 1.0).normalized()
	cam.look_at_from_position(target + d * dist, target)
	cam.current = true
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png(out)
	print("portrait written to ", out)
	quit()

func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_player(c)
		if r:
			return r
	return null
