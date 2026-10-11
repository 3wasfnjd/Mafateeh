class_name RainField
extends Node3D
## Spatially bounded rain over the miniature board (board-local units, so it
## moves, rotates and scales with the board and never fills the real room).
## Each drop knows the height of whatever is beneath it (paving, terrace,
## roof, water), so rain stops on solid roofs instead of falling through.
## Animation runs entirely in the vertex shader: no per-frame CPU work.

const DROPS := 520
const SPLASHES := 160
const TOP := 5.2

var amount := 0.0:
	set(v):
		amount = v
		visible = v > 0.01
		if _drop_mat:
			_drop_mat.set_shader_parameter("amount", v)
			_splash_mat.set_shader_parameter("amount", v)
var hero := Vector2.ZERO
var _drops: MultiMeshInstance3D
var _splashes: MultiMeshInstance3D
var _drop_mat: ShaderMaterial
var _splash_mat: ShaderMaterial
var _puddles: Array = []

const DROP_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform float amount = 1.0;
uniform float speed = 9.0;
varying float fade;
void vertex() {
	vec4 c = INSTANCE_CUSTOM;          // x: seed, y: top, z: bottom, w: unused
	float span = max(c.y - c.z, 0.1);
	float phase = fract(TIME * speed / span + c.x);
	float y = mix(c.y, c.z, phase);
	VERTEX.y += y;
	fade = smoothstep(0.0, 0.08, phase) * (1.0 - smoothstep(0.92, 1.0, phase));
	fade *= step(c.x, amount);         // thin out when the shower starts or ends
}
void fragment() {
	ALBEDO = vec3(0.82, 0.86, 0.92);
	ALPHA = 0.38 * fade;
}
"""

const SPLASH_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform float amount = 1.0;
uniform float speed = 9.0;
varying float fade;
void vertex() {
	vec4 c = INSTANCE_CUSTOM;          // x: seed, y: top, z: bottom
	float span = max(c.y - c.z, 0.1);
	float phase = fract(TIME * speed / span + c.x);
	float age = phase < 0.12 ? phase / 0.12 : 1.0;
	VERTEX.xz *= 0.3 + age * 1.2;
	VERTEX.y += c.z + 0.01;
	fade = (1.0 - age) * step(c.x, amount);
}
void fragment() {
	ALBEDO = vec3(0.86, 0.9, 0.95);
	ALPHA = 0.45 * fade;
}
"""


func _ready() -> void:
	visible = false
	_drop_mat = ShaderMaterial.new()
	_drop_mat.shader = Shader.new()
	_drop_mat.shader.code = DROP_SHADER
	_splash_mat = ShaderMaterial.new()
	_splash_mat.shader = Shader.new()
	_splash_mat.shader.code = SPLASH_SHADER
	var streak := BoxMesh.new()
	streak.size = Vector3(0.012, 0.22, 0.012)
	_drops = _make(streak, DROPS, _drop_mat)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.035
	ring.outer_radius = 0.05
	ring.rings = 12
	ring.ring_segments = 3
	_splashes = _make(ring, SPLASHES, _splash_mat)


func _make(mesh: Mesh, count: int, m: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-4.5, -0.5, -4.5), Vector3(9, TOP + 1.0, 9))
	add_child(mmi)
	return mmi


## Height of the first solid surface under (x, z) for this level.
static func floor_height(def: Dictionary, x: float, z: float) -> float:
	for r in def.get("roofs", []):
		if absf(x - r[0]) < r[2] / 2.0 and absf(z - r[1]) < r[3] / 2.0:
			return 1.46
	var y := LevelData.surface_y(def, x, z)
	if def.get("storeys", false) and z < -0.95:
		y = LevelData.UPPER_HEIGHT
	# Walls catch the rain on their tops.
	for w in def.walls:
		if absf(x - w[0]) < w[2] / 2.0 and absf(z - w[1]) < w[3] / 2.0:
			return y + 0.8
	return y + 0.06


func rebuild(state: PuzzleState) -> void:
	var def := state.def
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + state.level
	for mmi in [_drops, _splashes]:
		var mm: MultiMesh = mmi.multimesh
		for i in mm.instance_count:
			var x := rng.randf_range(-4.0, 4.0)
			var z := rng.randf_range(-3.5, 3.45)
			var bottom := floor_height(def, x, z)
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(x, 0, z)))
			mm.set_instance_custom_data(i, Color(rng.randf(), TOP, bottom, 0))
	for p in _puddles:
		p.queue_free()
	_puddles.clear()
	# A few shallow puddles where nothing interactive stands.
	var spots := [Vector2(-3.2, 2.7), Vector2(3.1, 2.75), Vector2(-0.6, 2.95), Vector2(2.9, -2.6), Vector2(-3.3, -2.7)]
	for s in spots:
		var clear := true
		for o in state.objects:
			if Vector2(o.x, o.z).distance_to(s) < 0.8:
				clear = false
		if clear and not state.blocked(s.x, s.y, true):
			var p := MeshInstance3D.new()
			var m := CylinderMesh.new()
			m.top_radius = 0.38
			m.bottom_radius = 0.38
			m.height = 0.004
			m.radial_segments = 20
			p.mesh = m
			p.material_override = Kit.mat("water")
			p.position = Vector3(s.x, LevelData.surface_y(def, s.x, s.y) + 0.065, s.y)
			p.scale = Vector3(1.0, 1.0, 0.6)
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(p)
			_puddles.append(p)


func _process(_dt: float) -> void:
	for p in _puddles:
		p.visible = amount > 0.3
