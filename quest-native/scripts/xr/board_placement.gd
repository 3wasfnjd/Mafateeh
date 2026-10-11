class_name BoardPlacement
extends Node3D
## The miniature world's root. Board-local units (1 = one floor tile) are
## mapped to meters by a uniform scale; game logic always works in
## board-local units, so targeting and collision stay exact at any size or
## rotation.

signal placed(source: String)  # "front" | "detected_table" | "detected_floor" | "manual"

const MIN_SCALE := 0.06
const MAX_SCALE := 0.26
const BASE_DEPTH := 0.42  # board units from the play floor down to the base
const HALF_EXTENT := Vector2(4.6, 4.2)  # board-local footprint incl. exit tunnel

var board_scale := 0.12
var surface_height := 0.75  # meters, where the board base rests
var placement_source := "front"
var surfaces: Array = []  # [{label, center: Vector3, size: Vector2, basis: Basis}]
var _drag_offset := Transform3D()


func set_board_scale(s: float) -> void:
	board_scale = clampf(s, MIN_SCALE, MAX_SCALE)
	scale = Vector3.ONE * board_scale
	position.y = surface_height + BASE_DEPTH * board_scale


func rotate_board(radians: float) -> void:
	rotation.y = wrapf(rotation.y + radians, -PI, PI)


func face(head: Vector3) -> void:
	var to := head - global_position
	rotation.y = atan2(to.x, to.z)


## Place the board in front of the viewer at a comfortable reach.
func place_in_front(head: Transform3D, seated_height: float) -> void:
	var fwd := -head.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()
	var distance := 0.55 + board_scale * 2.2
	var p := head.origin + fwd * distance
	surface_height = maxf(seated_height, head.origin.y - 0.62)
	position = Vector3(p.x, 0.0, p.z)
	set_board_scale(board_scale)
	face(head.origin)
	placement_source = "front"
	placed.emit(placement_source)


## Snap to the nearest detected horizontal surface in front of the viewer.
## Only real scene data reaches `surfaces`; without it this returns false.
func place_on_surface(head: Transform3D) -> bool:
	var best = null
	var best_score := INF
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.01 else Vector3(0, 0, -1)
	for s in surfaces:
		if s.label != "table":
			continue
		var to: Vector3 = s.center - head.origin
		var flat := Vector3(to.x, 0, to.z)
		var d := flat.length()
		if d > 3.0 or d < 0.2:
			continue
		var facing := flat.normalized().dot(fwd)
		var score := d - facing
		if score < best_score:
			best_score = score
			best = s
	if best == null:
		return false
	surface_height = best.center.y
	position = Vector3(best.center.x, 0.0, best.center.z)
	# Fit the board on the table top when possible.
	var fit := minf(best.size.x / (HALF_EXTENT.x * 2.0), best.size.y / (HALF_EXTENT.y * 2.0))
	if fit >= MIN_SCALE:
		board_scale = minf(board_scale, fit)
	set_board_scale(board_scale)
	face(head.origin)
	placement_source = "detected_table"
	placed.emit(placement_source)
	return true


func begin_drag(controller: Transform3D) -> void:
	_drag_offset = Transform3D(Basis(), controller.origin).affine_inverse() * Transform3D(Basis(), global_position)


func update_drag(controller: Transform3D) -> void:
	var p := (Transform3D(Basis(), controller.origin) * _drag_offset).origin
	position = Vector3(p.x, p.y, p.z)
	surface_height = p.y - BASE_DEPTH * board_scale


func end_drag(head: Transform3D) -> void:
	# Snap down onto a detected table if the base is released close to it.
	var base := Vector3(position.x, surface_height, position.z)
	for s in surfaces:
		var local: Vector3 = s.basis.inverse() * (base - s.center)
		if absf(local.x) < s.size.x / 2.0 + 0.1 and absf(local.z) < s.size.y / 2.0 + 0.1 \
				and absf(base.y - s.center.y) < 0.15:
			surface_height = s.center.y
			set_board_scale(board_scale)
			face(head.origin)
			placement_source = "detected_" + s.label
			placed.emit(placement_source)
			return
	set_board_scale(board_scale)
	placement_source = "manual"
	placed.emit(placement_source)


## World ray -> board-local ray (origin in board units, unit direction).
func to_local_ray(origin: Vector3, direction: Vector3) -> Array:
	var inv := global_transform.affine_inverse()
	return [inv * origin, (inv.basis * direction).normalized()]


func to_world_point(local: Vector3) -> Vector3:
	return global_transform * local
