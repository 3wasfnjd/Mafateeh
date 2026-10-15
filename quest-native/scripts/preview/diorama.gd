class_name Diorama
extends Node3D
## Tabletop preview of a scene diorama (assets/world/scene1/scene1.glb, built in real metres by
## tools/blender/build_scene1.py), shown small on a table in mixed reality. No gameplay.
## The parent moves, turns and resizes this node; this node only loads and scales the model.

const SCENE1 := "res://assets/world/scene1/scene1.glb"
const BASE_SCALE := 1.0 / 50.0   # 33 m island -> about 66 cm on the table

var model: Node3D


func setup(path := SCENE1) -> void:
	var ps := load(path) as PackedScene
	if ps == null:
		push_error("Diorama: cannot load " + path)
		return
	model = ps.instantiate()
	add_child(model)
	model.scale = Vector3.ONE * BASE_SCALE
	for mi in model.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# hidden wardrobe pieces, if the export kept any
	for n in model.find_children("*", "Node3D", true, false):
		if String(n.name).begins_with("Bisht") or String(n.name).begins_with("Glasses") or String(n.name).begins_with("Misbaha"):
			(n as Node3D).visible = false
