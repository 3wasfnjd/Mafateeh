class_name DustField
extends Node3D
## Light drifting dust over the miniature (board-local, so it scales and turns
## with the board): a few hundred warm motes that float slowly on the breeze and
## catch the light. Fades out in rain and is dimmer at night. Purely visual;
## switched off in the atmosphere settings. Animated in the vertex shader, so it
## costs one draw call and no per-frame CPU work.

const MOTES := 260

var amount := 0.0:
	set(v):
		amount = v
		visible = v > 0.01
		if _mat:
			_mat.set_shader_parameter("amount", v)
var _mat: ShaderMaterial

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform float amount = 1.0;
uniform vec3 wind = vec3(0.35, 0.0, 0.12);
uniform vec4 tint : source_color = vec4(1.0, 0.86, 0.62, 1.0);
varying float fade;
void vertex() {
	vec4 c = INSTANCE_CUSTOM;  // x, z: start in board units; y: height; w: seed
	float t = TIME * (0.6 + c.w * 0.5) + c.w * 40.0;
	vec3 p = vec3(c.x, c.y, c.z) + wind * t;
	p.x = mod(p.x + 4.2, 8.4) - 4.2;  // wrap inside the courtyard volume
	p.z = mod(p.z + 3.8, 7.6) - 3.8;
	p.y += sin(t * 1.3 + c.w * 9.0) * 0.12;
	// Billboard the tiny quad toward the camera.
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz) * 0.035;
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz) * 0.035;
	VERTEX = p + right * VERTEX.x + up * VERTEX.y;
	fade = step(c.w, amount) * (0.5 + 0.5 * sin(t * 0.7 + c.w * 20.0));
}
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = tint.rgb;
	ALPHA = (1.0 - smoothstep(0.2, 1.0, d)) * fade * 0.55;
}
"""


func _ready() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = MOTES
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	for i in MOTES:
		mm.set_instance_transform(i, Transform3D())
		mm.set_instance_custom_data(i, Color(rng.randf_range(-4.2, 4.2), rng.randf_range(0.3, 3.2),
			rng.randf_range(-3.8, 3.8), rng.randf()))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-5, -1, -5), Vector3(10, 6, 10))
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	mi.material_override = _mat
	add_child(mi)
	amount = 0.0
