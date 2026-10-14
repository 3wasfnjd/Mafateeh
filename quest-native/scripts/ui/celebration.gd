class_name Celebration
extends Node3D
## Level-complete celebration in the Diriyah / Najdi identity: a carved wooden panel
## rises over the gatehouse with a Sadu-weave band and stepped crenellations, a short
## Saudi word of praise in gold, the stars earned as eight-pointed Najdi stars, the
## secret gem if found, and rose petals and palm leaflets drifting down in lantern
## light. Board space (child of Game). Never touches puzzle rules.

const IDENTITY := "res://assets/ui/identity/"
const GOLD := Color("e7bf62")
const IVORY := Color("f3ead8")
const DIM := Color(1, 0.95, 0.85, 0.22)
# Light-hearted Najdi praise («فريحية»), with an English line for English players.
const PRAISE := [
	["كفو!", "Well done!"], ["عفيه عليك!", "Bravo!"], ["ما شاء الله!", "Masha'Allah!"],
	["يا زينها!", "Beautiful!"], ["هذا هو الشغل!", "That's the way!"], ["الله يعطيك العافية!", "Splendid work!"],
	["يا سلام عليك!", "Marvellous!"], ["بيّضت الوجه!", "You did us proud!"]]

var _font: FontFile
var panel: Node3D
var _t := -1.0
var _petals: CPUParticles3D
var _leaves: CPUParticles3D
var _glow: OmniLight3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_font = load("res://assets/fonts/cairo-arabic-700-normal.woff2") as FontFile
	if _font:
		var latin := load("res://assets/fonts/cairo-latin-700-normal.woff2") as FontFile
		if latin:
			_font.fallbacks = [latin]
	visible = false


func _tex_mat(file: String, tint := Color.WHITE, unshaded := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(IDENTITY + file) if ResourceLoader.exists(IDENTITY + file) else null
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _quad(parent: Node3D, size: Vector2, mat: Material, pos: Vector3, uv_x := 1.0) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	if uv_x != 1.0 and mat is StandardMaterial3D:
		(mat as StandardMaterial3D).uv1_scale = Vector3(uv_x, 1, 1)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _text(parent: Node3D, text: String, size: int, color: Color, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 12
	l.outline_modulate = Color(0.12, 0.07, 0.03, 0.95)
	if _font:
		l.font = _font
	l.position = pos
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_direction = TextServer.DIRECTION_AUTO
	l.double_sided = false
	parent.add_child(l)
	return l


func _particles(tex: String, color: Color, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	p.mesh = q
	p.material_override = _tex_mat(tex, color, false)
	p.amount = amount
	p.lifetime = 3.4
	p.one_shot = true
	p.explosiveness = 0.15
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(3.6, 0.2, 3.0)
	p.direction = Vector3(0, -1, 0)
	p.spread = 25.0
	p.gravity = Vector3(0, -0.35, 0)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.5
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.particle_flag_rotate_y = true
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	p.emitting = false
	add_child(p)
	return p


## Shows the celebration for the level just finished.
func play(def: Dictionary, level: int, moves: int, stars: int, secret: bool) -> void:
	if panel:
		panel.queue_free()
	visible = true
	_t = 0.0
	var arabic := Save.arabic()
	var ey := LevelData.exit_y(def)
	var ex := LevelData.exit_x(def)
	panel = Node3D.new()
	panel.position = Vector3(ex - 0.2 if ex > 0 else ex + 0.2, ey + 2.75, -3.2)
	add_child(panel)
	var finale: bool = def.get("finale", false)
	var w := 3.4 if not finale else 4.2
	var h := 1.55 if not finale else 1.9
	# Carved wooden board with plaster face, Sadu band and crenellations on top.
	Kit.add(panel, Kit.box(Vector3(w + 0.16, h + 0.16, 0.08)), Kit.mat("wood"), Vector3(0, 0, -0.06))
	var face := StandardMaterial3D.new()
	face.albedo_color = Color("3a241a")
	face.roughness = 0.8
	Kit.add(panel, Kit.box(Vector3(w, h, 0.04)), face, Vector3(0, 0, -0.01))
	_quad(panel, Vector2(w, 0.2), _tex_mat("sadu_band.png", Color.WHITE, true), Vector3(0, h / 2.0 - 0.14, 0.015), w / 1.3)
	_quad(panel, Vector2(w, 0.2), _tex_mat("sadu_band.png", Color.WHITE, true), Vector3(0, -h / 2.0 + 0.14, 0.015), w / 1.3)
	_quad(panel, Vector2(w + 0.16, 0.3), _tex_mat("crenel.png", Color("d6a676"), false), Vector3(0, h / 2.0 + 0.2, -0.04), (w + 0.16) / 1.2)
	var praise: Array = PRAISE[_rng.randi() % PRAISE.size()]
	var bonus := LevelData.is_bonus(level)
	var fin_ar := "فُتح ديوان الجد!" if bonus else "فُتح بيت الجد!"
	var fin_en := "Grandfather's diwan is open!" if bonus else "Grandfather's house is open!"
	var title: String = (fin_ar if arabic else fin_en) if finale else (praise[0] if arabic else praise[1])
	_text(panel, title, 120 if not finale else 128, GOLD, Vector3(0, h * 0.18, 0.03))
	var name: String = def.get("title_ar" if arabic else "title_en", "")
	var sub := "%d · %s" % [level, name]
	if def.get("par", 0) > 0:
		sub += Save.text("   ·   الحركات %d  /  المثالي %d", "   ·   moves %d  /  best %d") % [moves, int(def.par)]
	_text(panel, sub, 40, IVORY, Vector3(0, -h * 0.06, 0.03))
	# Najdi stars, gold for each earned.
	for i in 3:
		var lit := i < stars
		var st := _quad(panel, Vector2(0.26, 0.26), _tex_mat("najdi_star.png", GOLD if lit else DIM, true), Vector3((i - 1) * 0.36, -h * 0.28, 0.03))
		st.set_meta("lit", lit)
		st.set_meta("k", i)
		st.scale = Vector3.ZERO
	if secret:
		_text(panel, Save.text("وجدت الجوهرة السرية!", "You found the secret gem!"), 34, Color("9fe8bf"), Vector3(0, -h * 0.42, 0.03))
	var ch := LevelData.chapter_of(level)
	if level == int(LevelData.CHAPTERS[ch].to) and ch + 1 < LevelData.CHAPTERS.size():
		var nxt: Dictionary = LevelData.CHAPTERS[ch + 1]
		var line := Save.text("الفصل التالي: %s", "Next chapter: %s") % (nxt.ar if arabic else nxt.en)
		if nxt.get("bonus", false) and not Save.bonus_open(Save.secrets):
			line = Save.text("اجمع كل الجواهر السرية ليُفتح «%s»", "Find every secret gem to open \"%s\"") % (nxt.ar if arabic else nxt.en)
		_text(panel, line, 34, Color("ffd9a0"), Vector3(0, h * 0.42 - 0.02, 0.03))
	panel.scale = Vector3.ONE * 0.01
	if _glow == null:
		_glow = OmniLight3D.new()
		_glow.light_color = Color("ffbf6a")
		_glow.omni_range = 4.0
		add_child(_glow)
	_glow.position = panel.position + Vector3(0, 0, 1.2)
	_glow.light_energy = 0.0
	if _petals == null:
		_petals = _particles("petal.png", Color.WHITE, 70)
		_leaves = _particles("palm_leaf.png", Color.WHITE, 26)
	for p in [_petals, _leaves]:
		p.position = Vector3(0, ey + 3.2, 0)
		p.amount = (140 if p == _petals else 50) if finale else (70 if p == _petals else 26)
		p.restart()
		p.emitting = true


func hide_now() -> void:
	visible = false
	_t = -1.0
	if _petals:
		_petals.emitting = false
		_leaves.emitting = false


func _process(dt: float) -> void:
	if _t < 0.0 or panel == null:
		return
	_t += dt
	var k := clampf(_t / 0.55, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	panel.scale = Vector3.ONE * lerpf(0.01, 1.0, e) * (1.0 + 0.04 * sin(clampf(_t, 0.0, 1.0) * PI))
	panel.position.y += 0.0
	_glow.light_energy = lerpf(_glow.light_energy, 1.4, 1.0 - exp(-dt * 3.0))
	for c in panel.get_children():
		if c.has_meta("k"):
			var d := clampf((_t - 0.45 - int(c.get_meta("k")) * 0.18) / 0.25, 0.0, 1.0)
			var pop := 1.0 - pow(1.0 - d, 3.0)
			c.scale = Vector3.ONE * pop * (1.0 + 0.25 * sin(d * PI))
			if c.get_meta("lit"):
				c.rotation.z = (1.0 - d) * 1.2
