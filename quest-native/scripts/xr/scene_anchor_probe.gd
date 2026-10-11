extends Node3D
## Instanced by OpenXRFbSceneManager for each Meta scene entity (room data the
## user captured in Space Setup). Records horizontal TABLE / FLOOR planes so the
## board can rest on a real surface. Nothing is shown for the entity itself.

static var registry: Array = []

var label := ""
var rect := Rect2()


func setup_scene(entity) -> void:
	var labels: PackedStringArray = entity.get_semantic_labels()
	if labels.is_empty():
		return
	label = String(labels[0]).to_lower()
	if label != "table" and label != "floor":
		return
	# Bounded 2D component: the plane lies in the anchor's local XY.
	if entity.has_method("get_bounding_box_2d"):
		rect = entity.get_bounding_box_2d()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	registry.append(self)


func _exit_tree() -> void:
	registry.erase(self)


func describe() -> Dictionary:
	var gt := global_transform
	var center := gt * Vector3(rect.get_center().x, rect.get_center().y, 0.0)
	var ax := Vector3(gt.basis.x.x, 0.0, gt.basis.x.z).normalized()
	var az := Vector3(gt.basis.y.x, 0.0, gt.basis.y.z).normalized()
	if ax.length_squared() < 0.5 or az.length_squared() < 0.5:
		ax = Vector3.RIGHT
		az = Vector3.BACK
	return {"label": label, "center": center, "size": rect.size, "basis": Basis(ax, Vector3.UP, az)}
