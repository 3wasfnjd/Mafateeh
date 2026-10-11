class_name SceneSurfaces
extends Node
## Optional real-surface detection through the Meta Scene API (OpenXR Vendors
## OpenXRFbSceneManager). Only reports surfaces the headset actually provides;
## when the user has no room setup or denies permission, `available()` stays
## false and the game uses explicit manual placement instead.

signal surfaces_changed

const Probe := preload("res://scripts/xr/scene_anchor_probe.gd")

var manager: Node = null
var status := "unavailable"  # unavailable | waiting | ready | no_data


func attach(origin: XROrigin3D) -> void:
	if not ClassDB.class_exists("OpenXRFbSceneManager"):
		return
	manager = ClassDB.instantiate("OpenXRFbSceneManager")
	var probe := Node3D.new()
	probe.set_script(Probe)
	var packed := PackedScene.new()
	packed.pack(probe)
	probe.free()
	manager.set("default_scene", packed)
	manager.set("auto_create", true)
	origin.add_child(manager)
	status = "waiting"
	if manager.has_signal("openxr_fb_scene_anchor_created"):
		manager.connect("openxr_fb_scene_anchor_created", func(_a, _b): _changed())
	if manager.has_signal("openxr_fb_scene_data_missing"):
		manager.connect("openxr_fb_scene_data_missing", func(): status = "no_data")


func _changed() -> void:
	status = "ready"
	surfaces_changed.emit()


func surfaces() -> Array:
	var out: Array = []
	for p in Probe.registry:
		if is_instance_valid(p) and p.is_inside_tree():
			out.append(p.describe())
	return out


func has_table() -> bool:
	for s in surfaces():
		if s.label == "table":
			return true
	return false
