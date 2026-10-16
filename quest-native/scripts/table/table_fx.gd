class_name TableFx
extends RefCounted
## Little moments of joy on the table: the hidden gem of each level, the stars that rise over
## the diorama when a level is won.
## All in the diorama's own metres (they live under Diorama.stage).

const GEM_COLOUR := Color("8fd0e8")
const GOLD := Color("e3a83a")


## The level's hidden gem: a small cut stone that turns slowly and glints now and then.
static func gem(parent: Node3D, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = "Gem"
	parent.add_child(n)
	n.position = at
	var body := Node3D.new()
	n.add_child(body)
	body.position.y = 0.45
	var m := StandardMaterial3D.new()
	m.albedo_color = GEM_COLOUR
	m.metallic = 0.3
	m.roughness = 0.15
	m.emission_enabled = true
	m.emission = GEM_COLOUR
	m.emission_energy_multiplier = 0.6
	var crown := CylinderMesh.new()
	crown.top_radius = 0.16
	crown.bottom_radius = 0.3
	crown.height = 0.14
	crown.radial_segments = 8
	crown.rings = 1
	TableKit.mesh(body, crown, m, Vector3(0, 0.07, 0))
	var pav := CylinderMesh.new()
	pav.top_radius = 0.3
	pav.bottom_radius = 0.0
	pav.height = 0.32
	pav.radial_segments = 8
	pav.rings = 1
	TableKit.mesh(body, pav, m, Vector3(0, -0.16, 0))
	var glint := TableKit.sphere(body, 0.09, TableKit.glow_mat(Color(1, 1, 1), 0.0), Vector3(0.12, 0.12, 0.12), 6)
	glint.name = "Glint"
	var halo := TableKit.ring(n, 0.45, GEM_COLOUR.lightened(0.3), 0.35, 0.18)
	halo.position.y = 0.03
	return n


## Turns and bobs the gem; t is a running time in seconds.
static func gem_tick(g: Node3D, t: float) -> void:
	if g == null or not is_instance_valid(g) or g.get_child_count() == 0:
		return
	var body: Node3D = g.get_child(0)
	body.rotation.y = t * 1.2
	body.position.y = 0.45 + sin(t * 2.0) * 0.06
	var glint := body.get_node_or_null("Glint") as MeshInstance3D
	if glint:
		var k := clampf(sin(t * 1.7) * 6.0 - 5.0, 0.0, 1.0)   # a short flash every few seconds
		(glint.material_override as StandardMaterial3D).albedo_color.a = k * 0.9


## The gem is found: it leaps up spinning, flashes and is gone.
static func collect(g: Node3D) -> void:
	TableKit.sfx(g, "gem_pickup", Vector3(0, 0.5, 0), -2.0)
	TableKit.sfx(g, "unlock", Vector3(0, 0.5, 0), -8.0, 1.3)
	var tw := g.create_tween().set_parallel()
	tw.tween_property(g, "position:y", g.position.y + 2.2, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(g, "rotation:y", TAU * 2.0, 0.9)
	tw.tween_property(g, "scale", Vector3.ONE * 1.8, 0.6)
	tw.chain().tween_property(g, "scale", Vector3.ONE * 0.01, 0.3)
	tw.chain().tween_callback(g.queue_free)
	burst(g.get_parent(), g.position + Vector3(0, 2.2, 0), [GEM_COLOUR, Color.WHITE], 0.6, 24)


## The level's stars (of three) rise one after another above the scene.
static func stars(parent: Node3D, at: Vector3, earned: int) -> void:
	for k in 3:
		var s := badge(parent, "star", 2.6, GOLD if k < earned else Color(0.75, 0.62, 0.48, 0.7))
		s.position = at + Vector3((k - 1) * 3.2, 0, 0)
		s.scale = Vector3.ONE * 0.01
		var tw := s.create_tween()
		tw.tween_interval(0.35 + k * 0.4)
		tw.tween_callback(func():
			if k < earned:
				TableKit.sfx(s, "key_pickup", Vector3.ZERO, -6.0, 1.0 + k * 0.18)
				burst(parent, s.position, [GOLD, Color("fff1c8")], 0.5, 16))
		tw.tween_property(s, "scale", Vector3.ONE * (1.2 if k < earned else 0.8), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "position:y", at.y + 0.8, 1.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(s, "transparency", 1.0, 0.6)
		tw.tween_callback(s.queue_free)


## A flat icon (assets/ui/icons) that always faces the player, `size` diorama metres across.
## (A Sprite3D would not do: its billboard ignores the diorama's small scale.)
static func badge(parent: Node3D, icon: String, size: float, tint: Color) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = load("res://assets/ui/icons/%s.png" % icon)
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 10
	var mi := TableKit.mesh(parent, q, m)
	return mi


## A spray of glowing sparks at p (diorama metres).
static func burst(parent: Node3D, p: Vector3, colours: Array, speed := 1.0, amount := 60) -> void:
	var cp := CPUParticles3D.new()
	parent.add_child(cp)
	cp.position = p
	cp.one_shot = true
	cp.explosiveness = 1.0
	cp.amount = amount
	cp.lifetime = 1.6
	cp.direction = Vector3.UP
	cp.spread = 180.0
	cp.initial_velocity_min = 3.0 * speed
	cp.initial_velocity_max = 5.0 * speed
	cp.gravity = Vector3(0, -2.5, 0)
	cp.damping_min = 1.0
	cp.damping_max = 2.0
	cp.scale_amount_min = 0.6
	cp.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	cp.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, colours[0])
	grad.set_color(1, Color(colours[-1].r, colours[-1].g, colours[-1].b, 0.0))
	cp.color_ramp = grad
	var q := SphereMesh.new()
	q.radius = 0.2
	q.height = 0.4
	q.radial_segments = 6
	q.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = m
	cp.mesh = q
	cp.emitting = true
	# (freed after its sparks have died; its "finished" signal can come before they have)
	cp.get_tree().create_timer(cp.lifetime + 0.4).timeout.connect(cp.queue_free)
