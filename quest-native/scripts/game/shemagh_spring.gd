class_name ShemaghSpring
extends SkeletonModifier3D
## Cheap secondary motion for the cloth: the shemagh tails (two segments each side and
## at the back) and the thobe hem (front/back/left/right) follow a damped spring driven
## by the hero's planar acceleration and turning, on top of the motion baked into the
## clips. No cloth simulation; a few multiplies per frame.

const STIFFNESS := 70.0
const DAMPING := 9.0
const MAX_ANGLE := 0.45
# bone -> [swing weight (back/forward), sway weight (sideways)]
const BONES := {
	"Shemagh.L": [0.7, 0.7], "Shemagh.L2": [0.5, 0.5],
	"Shemagh.R": [0.7, 0.7], "Shemagh.R2": [0.5, 0.5],
	"Shemagh.B": [1.0, 0.8], "Shemagh.B2": [0.6, 0.5],
	"Skirt.F": [0.35, 0.0], "Skirt.B": [0.45, 0.0],
	"Skirt.L": [0.0, 0.3], "Skirt.R": [0.0, 0.3],
}

var bones := {}  # name -> {idx, pitch: Vector3, roll: Vector3}
var _prev_pos := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _prev_yaw := 0.0
var _offset := Vector2.ZERO  # x: swing back/forward, y: swing sideways (radians)
var _vel := Vector2.ZERO
var _ready_once := false


func _setup() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for name in BONES:
		var i := sk.find_bone(name)
		if i < 0:
			continue
		# Skeleton-space axes (character faces +Z) expressed in the bone's rest frame.
		var rest := sk.get_bone_global_rest(i).basis.orthonormalized()
		bones[name] = {"idx": i, "pitch": (rest.inverse() * Vector3.RIGHT).normalized(),
			"roll": (rest.inverse() * Vector3.BACK).normalized()}


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if bones.is_empty():
		_setup()
	var dt := get_process_delta_time() if is_inside_tree() else 1.0 / 72.0
	dt = clampf(dt, 1.0 / 240.0, 1.0 / 20.0)
	var owner3d := sk.get_parent() as Node3D
	var gt := sk.global_transform
	var pos := gt.origin
	var yaw := owner3d.global_rotation.y if owner3d else 0.0
	if not _ready_once:
		_prev_pos = pos
		_prev_yaw = yaw
		_ready_once = true
	var vel := (pos - _prev_pos) / dt
	var acc := (vel - _prev_vel) / dt
	var yaw_rate := wrapf(yaw - _prev_yaw, -PI, PI) / dt
	_prev_pos = pos
	_prev_vel = vel
	_prev_yaw = yaw
	# Work in the character's own frame; scale-independent (board can be resized).
	var s := maxf(gt.basis.get_scale().x, 1e-4)
	var local_acc := gt.basis.inverse() * acc * s * s
	var local_vel := gt.basis.inverse() * vel * s * s
	var target := Vector2(
		clampf(local_vel.z * 0.09 + local_acc.z * 0.006, -MAX_ANGLE, MAX_ANGLE),
		clampf(-local_acc.x * 0.006 - yaw_rate * 0.05, -MAX_ANGLE, MAX_ANGLE))
	var force := (target - _offset) * STIFFNESS - _vel * DAMPING
	_vel += force * dt
	_offset += _vel * dt
	_offset = _offset.clamp(Vector2(-MAX_ANGLE, -MAX_ANGLE), Vector2(MAX_ANGLE, MAX_ANGLE))
	for name in bones:
		var b: Dictionary = bones[name]
		var w: Array = BONES[name]
		var q := Quaternion(b.pitch, _offset.x * w[0]) * Quaternion(b.roll, _offset.y * w[1])
		sk.set_bone_pose_rotation(b.idx, sk.get_bone_pose_rotation(b.idx) * q)
