class_name HeroView
extends Node3D
## Presentation of the hero «الشايب» (assets/character/shaib.glb). Reads HeroMotor
## each frame and never changes rules. Locomotion clips play at a rate matched to
## the real ground speed so planted feet do not slide (the cycle distances match
## tools/blender/shaib_anim.py); footstep sounds fire on the clips' foot contacts.
## The face is driven here with blend shapes: blinking and an expression per state.

signal footstep(surface: String, at: Vector3, strength: float)
signal cloth(at: Vector3, strength: float)

const HERO_SCENE := "res://assets/character/shaib.glb"
# Board units covered by one loop of each locomotion clip (see shaib_anim.CYCLES).
const CYCLE := {"walk": 0.66, "carry": 0.66, "stairs_up": 0.56, "stairs_down": 0.56, "push": 0.50}
const LOOPS := ["idle", "walk", "turn", "push", "carry", "carry_idle", "stairs_up", "stairs_down", "ardah"]
const CONTACTS := [0.25, 0.75]  # left / right heel strikes within each locomotion cycle
const IDLE_LOOK_AFTER := 7.0    # seconds standing still before he glances around

# Expressions: blend shape weights (0..1). Unlisted shapes relax to 0.
const FACES := {
	"rest": {"smile": 0.14},
	"walk": {"smile": 0.22},
	"push": {"brows_angry": 0.55, "frown": 0.25, "eyes_happy": 0.25},
	"carry": {"smile": 0.3},
	"think": {"brow_raise_L": 1.0, "brows_angry": 0.3, "frown": 0.3},
	"reject": {"brows_sad": 0.9, "frown": 0.7},
	"celebrate": {"smile": 1.0, "eyes_happy": 0.8, "mouth_open": 0.7, "brows_up": 0.5},
	"excited": {"smile": 0.85, "eyes_wide": 0.35, "brows_up": 0.6},
	"ardah": {"smile": 1.0, "eyes_happy": 0.9, "brows_up": 0.3},
	"tired": {"brows_sad": 0.45, "mouth_open": 0.3, "eyes_happy": 0.3},
	"pickup": {"eyes_wide": 0.25, "smile": 0.3, "mouth_oo": 0.3},
}

var motor: HeroMotor
var model: Node3D
var anim: AnimationPlayer
var skeleton: Skeleton3D
var face: MeshInstance3D
var shadow: MeshInstance3D
var carry_root: Node3D
var carry_brick: Node3D
var carry_weight: Node3D
var _current := ""
var _react := ""
var _react_t := 0.0
var _last_phase := 0.0
var _last_yaw := 0.0
var _turn_t := 0.0
var _still_t := 0.0
var _was_stairs := false
var _fallback := false
var _shape := {}        # blend shape name -> index on the face mesh
var _weights := {}      # current blend shape weights
var _blink_t := 2.5
var _blink := 0.0
var _expr := "rest"
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	var scene: PackedScene = load(HERO_SCENE) if ResourceLoader.exists(HERO_SCENE) else null
	if scene:
		model = scene.instantiate()
		add_child(model)
		anim = model.find_children("*", "AnimationPlayer", true, false)[0]
		skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
		for name in anim.get_animation_list():
			anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR if name in LOOPS else Animation.LOOP_NONE
		anim.playback_default_blend_time = 0.18
		var spring := ShemaghSpring.new()
		skeleton.add_child(spring)
		_build_carry()
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_blend_shape_count() > 0:
				face = mi
		if face:
			for i in face.mesh.get_blend_shape_count():
				_shape[str(face.mesh.get_blend_shape_name(i))] = i
	else:
		_fallback = true
		model = Node3D.new()
		add_child(model)
		Kit.add(model, Kit.cylinder(0.13, 0.15, 0.85, 14), Kit.mat("plaster_top"), Vector3(0, 0.45, 0))
		Kit.add(model, Kit.sphere(0.17, 14), Kit.mat("wood_light"), Vector3(0, 1.05, 0))
	shadow = Kit.add(self, Kit.box(Vector3(0.6, 0.002, 0.5)), Kit.mat("shadow_blob"), Vector3(0, 0.0, 0), false)


func _build_carry() -> void:
	var att := BoneAttachment3D.new()
	att.bone_name = "CarrySocket"
	skeleton.add_child(att)
	carry_root = Node3D.new()
	att.add_child(carry_root)
	# Hand-sized versions of the level objects, sized to sit between the palms.
	carry_brick = Node3D.new()
	carry_root.add_child(carry_brick)
	Kit.add_piece(carry_brick, "mud_brick", Kit.box(Vector3(0.20, 0.11, 0.14)), Kit.mat("plaster"), Vector3(0, -0.02, 0)).scale = Vector3.ONE * (0.22 if Kit.piece("mud_brick") else 1.0)
	carry_weight = Node3D.new()
	carry_root.add_child(carry_weight)
	Kit.add(carry_weight, Kit.cylinder(0.065, 0.075, 0.04, 12), Kit.mat("stone_dark"), Vector3(0, -0.06, 0))
	Kit.add(carry_weight, Kit.sphere(0.05, 10), Kit.mat("brass"), Vector3(0, 0.0, 0))
	carry_brick.visible = false
	carry_weight.visible = false


func reset(m: HeroMotor) -> void:
	motor = m
	_current = ""
	_react = ""
	_still_t = 0.0
	_last_yaw = m.yaw
	sync(0.0)


func react(event: String) -> void:
	match event:
		"reject", "sequence_wrong":
			_react = "reject"
		"think":
			_react = "think"
		"solved":
			_react = "celebrate"
		"gem", "secret", "sequence_done", "unlock", "falcon":
			_react = "excited"
		_:
			return
	_react_t = 0.0


func _play(name: String, speed := 1.0, blend := -1.0) -> void:
	if anim == null or not anim.has_animation(name):
		return
	if name != _current:
		anim.play(name, blend)
		_current = name
	anim.speed_scale = speed


func _surface() -> String:
	var d: Dictionary = motor.state.def
	var p := motor.pos
	if d.get("storeys", false) and absf(p.y) < 0.95:
		return "wood"  # wooden stair treads
	if d.get("moat", false) and absf(p.y) < 0.89:
		return "wood"  # plank bridges
	return "stone"


func _on_stairs() -> int:
	var d: Dictionary = motor.state.def
	if not d.get("storeys", false) or absf(motor.pos.y) > 0.95:
		return 0
	# Facing the back (−z) climbs.
	return 1 if cos(motor.yaw) < 0.0 else -1


func _len(clip: String) -> float:
	return anim.get_animation(clip).length if anim and anim.has_animation(clip) else 1.0


func sync(dt: float) -> void:
	if motor == null:
		return
	var y := LevelData.surface_y(motor.state.def, motor.pos.x, motor.pos.y)
	position = Vector3(motor.pos.x, y + 0.035, motor.pos.y)
	rotation.y = motor.yaw
	shadow.global_position = Vector3(global_position.x, global_position.y, global_position.z)
	shadow.position.y = 0.03
	visible = not (motor.mode == "complete" and motor.mode_time > 0.6)
	if _fallback or dt <= 0.0:
		return
	var carrying := motor.carrying()
	carry_brick.visible = carrying == "brick"
	carry_weight.visible = carrying == "weight"
	var yaw_rate := absf(wrapf(motor.yaw - _last_yaw, -PI, PI)) / dt
	_last_yaw = motor.yaw
	var speed := motor.speed_now
	var locomotion := false
	_react_t += dt
	var expr := "rest"
	if motor.mode == "acting" and motor.act_obj != null:
		var t: String = motor.act_obj.type
		var clip := "interact"
		if t in ["key", "gem"]:
			clip = "pickup_small"
		elif t in ["weight", "brick"]:
			clip = "pickup"
		elif t in ["pan", "brickSocket"]:
			clip = "place" if motor.last_result.get("event", "") != "pickup_weight" and carrying == "" else "pickup"
		elif t == "_drop":
			clip = "place"
		elif t == "portal":
			clip = "celebrate"
		_play(clip, _len(clip) / maxf(motor.act_duration, 0.2), 0.12)
		expr = "pickup" if clip.begins_with("pickup") else "rest"
		_still_t = 0.0
	elif motor.mode == "pushing":
		# Pulling plays the push cycle backwards: the feet step back, hands stay on the crate.
		_play("push", speed * _len("push") / CYCLE.push * (-1.0 if motor.pulling else 1.0))
		locomotion = true
		expr = "push"
		_still_t = 0.0
	elif motor.mode in ["finishing", "complete"]:
		_play("ardah", 1.0, 0.25)
		expr = "ardah"
	elif speed > 0.05:
		var stairs := _on_stairs()
		var clip := "carry" if carrying != "" else "walk"
		if stairs != 0 and carrying == "":
			clip = "stairs_up" if stairs > 0 else "stairs_down"
		_was_stairs = _was_stairs or clip == "stairs_up"
		_play(clip, speed * _len(clip) / CYCLE[clip])
		locomotion = true
		_react = ""
		_still_t = 0.0
		expr = "carry" if carrying != "" else "walk"
	elif _react != "" and _react_t < _len(_react):
		_play(_react, 1.0, 0.15)
		expr = _react
	elif yaw_rate > 1.2:
		_turn_t = 0.2
		_play("turn", 1.0)
		locomotion = true
	elif _turn_t > 0.0:
		_turn_t -= dt
	else:
		_react = ""
		_still_t += dt
		if carrying != "":
			_play("carry_idle")
			expr = "carry"
		elif _was_stairs:
			# Catches his breath after climbing, once.
			_was_stairs = false
			_react = "tired"
			_react_t = 0.0
			_play("tired", 1.0, 0.2)
		elif _still_t > IDLE_LOOK_AFTER and _current == "idle":
			_still_t = -_len("idle_look") - _rng.randf_range(4.0, 9.0)
			_react = "idle_look"
			_react_t = 0.0
			_play("idle_look", 1.0, 0.3)
		elif _current != "idle_look" or not anim.is_playing():
			_play("idle")
	_face(dt, expr)
	_emit_steps(locomotion, speed)


func _face(dt: float, expr: String) -> void:
	if face == null:
		return
	_expr = expr
	var target: Dictionary = FACES.get(expr, FACES.rest).duplicate()
	if expr == "ardah":
		# chanting with the drum: the mouth opens on the beat
		target["mouth_open"] = 0.25 + 0.5 * maxf(0.0, sin(Time.get_ticks_msec() / 1000.0 * TAU / 1.6 * 2.0))
	elif expr == "tired":
		target["mouth_open"] = 0.15 + 0.3 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU / 0.8))
	# Blinks every few seconds (sometimes twice); none while the eyes are squeezed happy.
	_blink_t -= dt
	if _blink_t <= 0.0:
		_blink = 0.16
		_blink_t = _rng.randf_range(2.2, 5.0) if _rng.randf() > 0.2 else 0.28
	if _blink > 0.0:
		_blink -= dt
		target["blink"] = maxf(target.get("blink", 0.0), 1.0 - absf(_blink - 0.08) / 0.08)
	var rate := 1.0 - exp(-dt * 12.0)
	for name in _shape:
		var want: float = target.get(name, 0.0)
		var now: float = _weights.get(name, 0.0)
		now = lerpf(now, want, 1.0 if name == "blink" else rate)
		_weights[name] = now
		face.set_blend_shape_value(_shape[name], now)


func _emit_steps(locomotion: bool, speed: float) -> void:
	if not locomotion or anim == null or anim.current_animation == "":
		_last_phase = 0.0
		return
	var length := anim.current_animation_length
	var phase := fmod(anim.current_animation_position, length) / length
	for c in CONTACTS:
		var crossed: bool = (_last_phase < c and phase >= c) or (_last_phase > phase and (c > _last_phase or c <= phase))
		if crossed:
			var at := position + Vector3(0, 0.05, 0)
			var strength := clampf(speed / HeroMotor.SPEED, 0.35, 1.0)
			footstep.emit(_surface(), at, strength)
			cloth.emit(at + Vector3(0, 0.5, 0), strength * 0.7)
	_last_phase = phase
