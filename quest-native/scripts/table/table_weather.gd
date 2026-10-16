class_name TableWeather
extends Node3D
## Weather over a table diorama, brought over from the board game (scripts/env): light motes
## of dust drifting over the scene, gusts of blown sand (the camp in the dunes), and a short
## shower that stops on the roofs and the palms instead of falling through them (after the
## well waters the farm). Lives under Diorama.stage, so it is in the scene's own metres and
## sinks with it. Everything moves in vertex shaders: no work per frame on the CPU.
##   dust(on)        the drifting motes
##   gusts(on)       now and then a gust of sand streaks across, every 20 to 35 s
##   shower(seconds) rain for a while, easing in and out

const HALF := Vector2(11.5, 9.5)   # the area it covers (x, z half sizes)
const MOTES := 300
const STREAKS := 220
const DROPS := 700
const TOP := 11.0

var _dust: MultiMeshInstance3D
var _sand: MultiMeshInstance3D
var _rain: MultiMeshInstance3D
var _gusts := false
var _gust_wait := 12.0
var _model: Node3D

const DUST_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;
uniform float amount = 1.0;
uniform float wind = 0.4;
uniform vec2 half_size = vec2(11.5, 9.5);
uniform vec4 tint : source_color = vec4(1.0, 0.87, 0.62, 1.0);
varying float fade;
void vertex() {
	vec4 c = INSTANCE_CUSTOM;   // x, z: start; y: height; w: seed
	float t = TIME * (0.5 + c.w * 0.5) + c.w * 40.0;
	vec3 p = vec3(c.x + wind * t, c.y + sin(t * 1.1 + c.w * 9.0) * 0.25, c.z + wind * 0.35 * t);
	p.x = mod(p.x + half_size.x, 2.0 * half_size.x) - half_size.x;
	p.z = mod(p.z + half_size.y, 2.0 * half_size.y) - half_size.y;
	vec3 right = normalize((inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[0].xyz, 0.0)).xyz) * 0.07;
	vec3 up = normalize((inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[1].xyz, 0.0)).xyz) * 0.07;
	VERTEX = p + right * VERTEX.x + up * VERTEX.y;
	// thin out towards the edges of the island, twinkle, and follow amount
	float edge = 1.0 - smoothstep(0.75, 1.0, max(abs(p.x) / half_size.x, abs(p.z) / half_size.y));
	fade = step(c.w, amount) * edge * (0.45 + 0.55 * sin(t * 0.7 + c.w * 20.0));
}
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = tint.rgb;
	ALPHA = clamp((1.0 - smoothstep(0.15, 1.0, d)) * fade * 0.6, 0.0, 1.0);
}
"""

const SAND_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;
uniform float amount = 0.0;
uniform vec2 half_size = vec2(11.5, 9.5);
uniform vec4 tint : source_color = vec4(0.86, 0.66, 0.42, 1.0);
varying float fade;
varying vec2 uv;
void vertex() {
	vec4 c = INSTANCE_CUSTOM;   // x, z: start; y: height; w: seed
	float t = TIME * (5.0 + c.w * 4.0) + c.w * 90.0;
	vec3 p = vec3(c.x + t, c.y + sin(t * 0.3 + c.w * 7.0) * 0.2, c.z + t * 0.28);
	p.x = mod(p.x + half_size.x, 2.0 * half_size.x) - half_size.x;
	p.z = mod(p.z + half_size.y, 2.0 * half_size.y) - half_size.y;
	// a streak along the wind, turned to face up and to the camera as well as it can
	vec3 along = normalize(vec3(1.0, 0.0, 0.28)) * (0.9 + c.w * 0.8);
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
	vec3 side = normalize(cross(along, cam - p)) * 0.035;
	VERTEX = p + along * VERTEX.x + side * VERTEX.y;
	float edge = 1.0 - smoothstep(0.7, 1.0, max(abs(p.x) / half_size.x, abs(p.z) / half_size.y));
	fade = step(c.w, amount) * edge;
	uv = UV;
}
void fragment() {
	float a = sin(uv.x * 3.14159) * (1.0 - abs(uv.y - 0.5) * 2.0);
	ALBEDO = tint.rgb;
	ALPHA = clamp(a * fade * 0.5, 0.0, 1.0);
}
"""

const RAIN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;
uniform float amount = 0.0;
uniform float speed = 14.0;
varying float fade;
void vertex() {
	vec4 c = INSTANCE_CUSTOM;   // x, z: where; y: the surface under it; w: seed
	float top = 11.0;
	float span = max(top - c.y, 0.5);
	float k = fract(TIME * speed / span + c.w * 7.0);
	vec3 p = vec3(c.x, mix(top, c.y, k), c.z);
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), cam - p)) * 0.025;
	VERTEX = p + side * VERTEX.x + vec3(0.0, 0.55, 0.0) * VERTEX.y;
	fade = step(c.w, amount) * smoothstep(0.0, 0.1, k) * (1.0 - smoothstep(0.95, 1.0, k));
}
void fragment() {
	ALBEDO = vec3(0.86, 0.9, 0.95);
	ALPHA = 0.42 * fade;
}
"""


func setup(model: Node3D) -> void:
	_model = model
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	_dust = _field(DUST_SHADER, MOTES, Vector2(2, 2), func(i: int) -> Color:
		return Color(rng.randf_range(-HALF.x, HALF.x), rng.randf_range(0.3, 5.0), rng.randf_range(-HALF.y, HALF.y), rng.randf()))
	_sand = _field(SAND_SHADER, STREAKS, Vector2(1, 1), func(i: int) -> Color:
		return Color(rng.randf_range(-HALF.x, HALF.x), rng.randf_range(0.1, 2.6), rng.randf_range(-HALF.y, HALF.y), rng.randf()))
	_amount(_dust, 0.0)
	_amount(_sand, 0.0)


## Drifting dust (a warm tint by day, a dimmer one in the evening).
func dust(on: bool, evening := false) -> void:
	(_dust.material_override as ShaderMaterial).set_shader_parameter("tint", Color(1.0, 0.8, 0.55) if evening else Color(1.0, 0.87, 0.62))
	_fade(_dust, 0.75 if on else 0.0, 1.5)


func gusts(on: bool) -> void:
	_gusts = on
	if not on:
		_fade(_sand, 0.0, 1.0)


## A shower for `seconds`: it builds up, rains, and thins out.
func shower(seconds := 8.0) -> void:
	if _rain == null:
		_rain = _rain_field()
	var tw := create_tween()
	tw.tween_method(func(v: float): _amount(_rain, v), 0.0, 1.0, 1.5)
	tw.tween_interval(maxf(0.0, seconds - 3.0))
	tw.tween_method(func(v: float): _amount(_rain, v), 1.0, 0.0, 1.5)
	# and its patter, on the surroundings bus
	var st := load("res://audio/ambience/rain.ogg") as AudioStream
	if st:
		var p := AudioStreamPlayer.new()
		p.stream = st
		p.bus = "Ambience" if AudioServer.get_bus_index("Ambience") >= 0 else "Master"
		p.volume_db = -30.0
		add_child(p)
		p.play()
		var ts := create_tween()
		ts.tween_property(p, "volume_db", 0.0, 1.5)
		ts.tween_interval(maxf(0.0, seconds - 3.0))
		ts.tween_property(p, "volume_db", -40.0, 1.8)
		ts.tween_callback(p.queue_free)


func _process(dt: float) -> void:
	if not _gusts:
		return
	_gust_wait -= dt
	if _gust_wait > 0.0:
		return
	_gust_wait = randf_range(20.0, 35.0)
	var tw := create_tween()
	tw.tween_method(func(v: float): _amount(_sand, v), 0.0, 1.0, 1.4).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(3.5)
	tw.tween_method(func(v: float): _amount(_sand, v), 1.0, 0.0, 2.0).set_trans(Tween.TRANS_SINE)
	TableKit.sfx(self, "bridge_move", Vector3(-6, 1, 0), -10.0, 0.8)


func _field(code: String, count: int, quad: Vector2, data: Callable) -> MultiMeshInstance3D:
	var q := QuadMesh.new()
	q.size = quad
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = count
	for i in count:
		mm.set_instance_transform(i, Transform3D())
		mm.set_instance_custom_data(i, data.call(i))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-HALF.x - 2, -1, -HALF.y - 2), Vector3(HALF.x * 2 + 4, TOP + 2, HALF.y * 2 + 4))
	add_child(mi)
	return mi


## The rain: every drop knows the height of whatever is under it (roof, palm, ground), so it
## stops there. The heights come from the scene's own triangles, once.
func _rain_field() -> MultiMeshInstance3D:
	var faces := PackedVector3Array()
	if _model:
		var inv := _model.global_transform.affine_inverse()
		for n in _model.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var x := inv * mi.global_transform
			var f := mi.mesh.get_faces()
			for i in f.size():
				f[i] = x * f[i]
			faces.append_array(f)
	var tm := TriangleMesh.new()
	var ok := faces.size() >= 3 and tm.create_from_faces(faces)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	return _field(RAIN_SHADER, DROPS, Vector2(1, 1), func(i: int) -> Color:
		var x := rng.randf_range(-HALF.x, HALF.x)
		var z := rng.randf_range(-HALF.y, HALF.y)
		var y := 0.0
		if ok:
			var hit := tm.intersect_ray(Vector3(x, TOP + 5.0, z), Vector3.DOWN)
			if not hit.is_empty():
				y = hit.position.y
		return Color(x, y, z, rng.randf()))


func _fade(mi: MultiMeshInstance3D, to: float, seconds: float) -> void:
	var from := float((mi.material_override as ShaderMaterial).get_shader_parameter("amount"))
	create_tween().tween_method(func(v: float): _amount(mi, v), from, to, seconds)


static func _amount(mi: MultiMeshInstance3D, v: float) -> void:
	(mi.material_override as ShaderMaterial).set_shader_parameter("amount", v)
	mi.visible = v > 0.005
