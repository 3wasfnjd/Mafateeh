class_name FalconView
extends RefCounted
## The falcon «شاهين». Uses assets/creatures/falcon.glb (built in Blender by
## tools/blender/build_creatures.py) when present, with its "perch" and "fly" clips;
## otherwise a small procedural stand-in. Pure presentation.

const SCENE := "res://assets/creatures/falcon.glb"


static func make(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Falcon"
	parent.add_child(root)
	if ResourceLoader.exists(SCENE):
		var m: Node3D = (load(SCENE) as PackedScene).instantiate()
		root.add_child(m)
		var ap: Array = m.find_children("*", "AnimationPlayer", true, false)
		if not ap.is_empty():
			root.set_meta("anim", ap[0])
			for clip in ["perch", "fly"]:
				if (ap[0] as AnimationPlayer).has_animation(clip):
					(ap[0] as AnimationPlayer).get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			(ap[0] as AnimationPlayer).play("perch")
		return root
	# Stand-in: body, head with hooked beak, folded wings, tail.
	var brown := StandardMaterial3D.new()
	brown.albedo_color = Color("7a5636")
	var cream := StandardMaterial3D.new()
	cream.albedo_color = Color("e6d6b8")
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("2a2420")
	Kit.add(root, Kit.sphere(0.07, 10), cream, Vector3(0, 0.07, 0)).scale = Vector3(0.9, 1.3, 1.0)
	Kit.add(root, Kit.sphere(0.045, 10), brown, Vector3(0, 0.17, 0.02))
	Kit.add(root, Kit.prism(Vector3(0.02, 0.03, 0.03)), dark, Vector3(0, 0.165, 0.065)).rotation.x = PI / 2
	for side in [-1, 1]:
		var wing := Node3D.new()
		wing.name = "Wing" + str(side)
		wing.position = Vector3(side * 0.05, 0.11, 0)
		root.add_child(wing)
		var w := Kit.add(wing, Kit.box(Vector3(0.03, 0.1, 0.13)), brown, Vector3(side * 0.01, -0.03, -0.02))
		w.rotation.x = 0.3
	Kit.add(root, Kit.box(Vector3(0.05, 0.015, 0.1)), brown, Vector3(0, 0.02, -0.08)).rotation.x = -0.4
	return root


## Wing beat: amount 0 = folded at rest, 1 = full flapping flight.
static func flap(root: Node3D, t: float, amount: float) -> void:
	if root.has_meta("anim"):
		var ap: AnimationPlayer = root.get_meta("anim")
		var want := "fly" if amount > 0.5 else "perch"
		if ap.has_animation(want) and ap.current_animation != want:
			ap.play(want, 0.2)
		return
	for side in [-1, 1]:
		var wing := root.get_node_or_null("Wing" + str(side))
		if wing:
			wing.rotation.z = side * amount * (0.6 + 0.9 * sin(t * 18.0))
	root.rotation.z = amount * 0.08 * sin(t * 9.0)
