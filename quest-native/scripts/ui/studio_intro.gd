class_name StudioIntro
extends Node3D
## Aboden Games (عبودين قيمز) studio mark, shown once at launch before the board
## appears: the gold eight-point star settles in, the names rise beneath it and a
## short oud sting plays, then everything fades to reveal the room or the sky.
## About four seconds; any trigger or button skips it. Can be turned off in the
## display settings.

signal finished

const DURATION := 4.2
const DISTANCE := 1.6  # metres in front of the viewer

var _t := 0.0
var _done := false
var _veil: MeshInstance3D
var _veil_mat: StandardMaterial3D
var _emblem: Sprite3D
var _word: Sprite3D
var _glow: Sprite3D
var _sound: AudioStreamPlayer
var _skipped := false


func play(head: Transform3D, with_veil := true, level := true) -> void:
	var fwd := -head.basis.z
	if level:  # headset: keep the mark upright at eye height
		fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.01 else Vector3.FORWARD
	# Dark surround so the mark reads cleanly in mixed reality and VR alike.
	_veil = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 3.0
	sphere.height = 6.0
	sphere.flip_faces = true
	sphere.radial_segments = 24
	sphere.rings = 12
	_veil.mesh = sphere
	_veil_mat = StandardMaterial3D.new()
	_veil_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_veil_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_veil_mat.albedo_color = Color(0.07, 0.045, 0.03, 1.0)
	_veil_mat.disable_receive_shadows = true
	_veil_mat.render_priority = -10  # transparent sort: the veil (centred on the head) must draw first
	_veil.material_override = _veil_mat
	_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_veil.visible = with_veil
	add_child(_veil)
	_veil.global_position = head.origin

	var anchor := Node3D.new()
	add_child(anchor)
	anchor.global_position = head.origin + fwd * DISTANCE
	anchor.look_at(head.origin, Vector3.UP, true)
	_glow = _sprite(_glow_texture(), 0.0034, Vector3(0, 0.12, -0.01))
	_glow.render_priority = 9
	anchor.add_child(_glow)
	_emblem = _sprite(load("res://assets/brand/aboden_emblem.png"), 0.00052, Vector3(0, 0.12, 0))
	anchor.add_child(_emblem)
	_word = _sprite(load("res://assets/brand/aboden_wordmark.png"), 0.00036, Vector3(0, -0.22, 0))
	anchor.add_child(_word)

	_sound = AudioStreamPlayer.new()
	_sound.stream = load("res://audio/sfx/intro_sting.wav")
	_sound.volume_db = -2.0
	add_child(_sound)
	if not Save.muted:
		_sound.play()
	_update(0.0)


func _sprite(tex: Texture2D, pixel: float, pos: Vector3) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = pixel
	s.position = pos
	s.shaded = false
	s.double_sided = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.modulate = Color(1.3, 1.3, 1.3, 0.0)  # offsets the scene tonemapper so the gold stays bright
	s.render_priority = 10
	return s


## Soft warm halo behind the star (generated, no asset needed).
static func _glow_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.8, 0.45, 0.55))
	g.set_color(1, Color(1.0, 0.7, 0.35, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 256
	t.height = 256
	return t


static func _ease(x: float) -> float:
	return smoothstep(0.0, 1.0, clampf(x, 0.0, 1.0))


func _update(t: float) -> void:
	var out := 1.0 - _ease((t - (DURATION - 0.9)) / 0.9)  # final fade of everything
	var e_in := _ease((t - 0.2) / 0.9)
	_emblem.modulate.a = e_in * out
	_emblem.scale = Vector3.ONE * lerpf(0.82, 1.0, e_in)
	_emblem.rotation.z = lerpf(-0.39, 0.0, e_in)  # the star turns a sixteenth into place
	var flash := _ease((t - 1.35) / 0.25) * (1.0 - _ease((t - 1.6) / 1.2))
	_glow.modulate.a = (0.35 * e_in + 0.65 * flash) * out
	_glow.scale = Vector3.ONE * (0.9 + 0.25 * flash)
	var w_in := _ease((t - 1.3) / 0.7)
	_word.modulate.a = w_in * out
	_word.position.y = lerpf(-0.25, -0.22, w_in)
	_veil_mat.albedo_color.a = out
	if _sound and _skipped:
		_sound.volume_db = -2.0 + linear_to_db(maxf(out, 0.001))


func skip() -> void:
	if _done:
		return
	# Jump to the fade-out instead of cutting: smoother on the eyes.
	_skipped = true
	_t = maxf(_t, DURATION - 0.6)


func is_playing() -> bool:
	return not _done


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_update(_t)
	if _t >= DURATION:
		_done = true
		finished.emit()
		queue_free()
