class_name HeroView
extends Node3D
## Presentation of the hero (assets/character/hero.glb). Reads HeroMotor each
## frame and never changes rules. Walk-type clips play at a rate matched to the
## real ground speed so the feet do not slide; footstep sounds fire on the
## clips' foot contacts, not on a timer.

signal footstep(surface: String, at: Vector3, strength: float)
signal cloth(at: Vector3, strength: float)

const HERO_SCENE := "res://assets/character/hero.glb"
const CYCLE_DISTANCE := 0.72  # board units covered by one walk/carry cycle at speed 1
const STAIRS_CYCLE := 0.6
const PUSH_CYCLE := 0.55
const LOOPS := ["idle", "walk", "turn", "push", "carry", "carry_idle", "stairs_up", "stairs_down"]
const CONTACTS := [0.25, 0.75]  # foot plants within each locomotion cycle

var motor: HeroMotor
var model: Node3D
var anim: AnimationPlayer
var skeleton: Skeleton3D
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
var _fallback := false


func _ready() -> void:
	var scene: PackedScene = load(HERO_SCENE) if ResourceLoader.exists(HERO_SCENE) else null
	if scene:
		model = scene.instantiate()
		add_child(model)
		anim = model.find_children("*", "AnimationPlayer", true, false)[0]
		skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
		for name in anim.get_animation_list():
			anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR if name in LOOPS else Animation.LOOP_NONE
		anim.playback_default_blend_time = 0.15
		var spring := ShemaghSpring.new()
		skeleton.add_child(spring)
		_build_carry()
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		_fallback = true
		model = Node3D.new()
		add_child(model)
		Kit.add(model, Kit.cylinder(0.16, 0.26, 0.75, 14), Kit.mat("plaster_top"), Vector3(0, 0.4, 0))
		Kit.add(model, Kit.sphere(0.24, 14), Kit.mat("wood_light"), Vector3(0, 0.98, 0))
	shadow = Kit.add(self, Kit.box(Vector3(0.75, 0.002, 0.6)), Kit.mat("shadow_blob"), Vector3(0, 0.0, 0), false)


func _build_carry() -> void:
	var att := BoneAttachment3D.new()
	att.bone_name = "CarrySocket"
	skeleton.add_child(att)
	carry_root = Node3D.new()
	att.add_child(carry_root)
	# Hand-sized versions of the level objects, sized to sit between the palms.
	carry_brick = Node3D.new()
	carry_root.add_child(carry_brick)
	Kit.add_piece(carry_brick, "mud_brick", Kit.box(Vector3(0.22, 0.12, 0.16)), Kit.mat("plaster"), Vector3(0, -0.02, 0)).scale = Vector3.ONE * (0.24 if Kit.piece("mud_brick") else 1.0)
	carry_weight = Node3D.new()
	carry_root.add_child(carry_weight)
	Kit.add(carry_weight, Kit.cylinder(0.07, 0.08, 0.04, 12), Kit.mat("stone_dark"), Vector3(0, -0.06, 0))
	Kit.add(carry_weight, Kit.sphere(0.055, 10), Kit.mat("brass"), Vector3(0, 0.0, 0))
	carry_brick.visible = false
	carry_weight.visible = false


func reset(m: HeroMotor) -> void:
	motor = m
	_current = ""
	_react = ""
	_last_yaw = m.yaw
	sync(0.0)


func react(event: String) -> void:
	match event:
		"reject", "sequence_wrong":
			_react = "reject"
		"think":
			_react = "think"
		"solved", "sequence_done", "gem":
			_react = "celebrate" if event == "solved" else ""
		_:
			return
	_react_t = 0.0


func _play(name: String, speed := 1.0, blend := -1.0) -> void:
	if anim == null:
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
	if d.get("pool_room", false) and p.x > -2.72 and p.x < -1.38 and p.y > -2.86 and p.y < -0.04:
		return "stone"
	return "stone"


func _on_stairs() -> int:
	var d: Dictionary = motor.state.def
	if not d.get("storeys", false) or absf(motor.pos.y) > 0.95:
		return 0
	# Facing the back (−z) climbs.
	return 1 if cos(motor.yaw) < 0.0 else -1


func sync(dt: float) -> void:
	if motor == null:
		return
	var y := LevelData.surface_y(motor.state.def, motor.pos.x, motor.pos.y)
	position = Vector3(motor.pos.x, y + 0.035, motor.pos.y)
	rotation.y = motor.yaw
	shadow.global_position = Vector3(global_position.x, global_position.y, global_position.z)
	shadow.position.y = 0.03
	visible = not (motor.mode in ["finishing", "complete"] and motor.mode_time > 0.6)
	if _fallback or dt <= 0.0:
		return
	var carrying := motor.carrying()
	carry_brick.visible = carrying == "brick"
	carry_weight.visible = carrying == "weight"
	var yaw_rate := absf(wrapf(motor.yaw - _last_yaw, -PI, PI)) / dt
	_last_yaw = motor.yaw
	var speed := motor.speed_now
	var locomotion := false
	var cycle := CYCLE_DISTANCE
	_react_t += dt
	if motor.mode == "acting" and motor.act_obj != null:
		var t: String = motor.act_obj.type
		var clip := "interact"
		if t in ["key", "gem", "weight", "brick"]:
			clip = "pickup"
		elif t in ["pan", "brickSocket"]:
			clip = "place" if motor.last_result.get("event", "") != "pickup_weight" and carrying == "" else "pickup"
		elif t == "_drop":
			clip = "place"
		elif t == "portal":
			clip = "celebrate"
		var length := anim.get_animation(clip).length
		_play(clip, length / maxf(motor.act_duration, 0.2), 0.1)
	elif motor.mode == "pushing":
		_play("push", speed / PUSH_CYCLE * anim.get_animation("push").length * 0.5)
		locomotion = true
		cycle = PUSH_CYCLE
	elif motor.mode in ["finishing", "complete"]:
		_play("celebrate" if motor.mode_time < 1.2 else "idle")
	elif speed > 0.05:
		var stairs := _on_stairs()
		var clip := "carry" if carrying != "" else "walk"
		cycle = CYCLE_DISTANCE
		if stairs != 0 and carrying == "":
			clip = "stairs_up" if stairs > 0 else "stairs_down"
			cycle = STAIRS_CYCLE
		_play(clip, speed * anim.get_animation(clip).length / cycle)
		locomotion = true
		_react = ""
	elif _react != "" and _react_t < anim.get_animation(_react).length:
		_play(_react, 1.0, 0.12)
	elif yaw_rate > 1.2:
		_turn_t = 0.2
		_play("turn", 1.0)
		locomotion = true
	elif _turn_t > 0.0:
		_turn_t -= dt
	else:
		_react = ""
		_play("carry_idle" if carrying != "" else "idle")
	_emit_steps(locomotion, speed)


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
