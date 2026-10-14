class_name CreatureSlot
extends RefCounted
## Replaceable creature models. Each creature is a "slot": drop a new GLB at its path
## (same file name) and the game picks it up with no code changes:
##   * size: the model is measured and scaled to the slot's height (board units), and
##     its feet are put on the ground, whatever units it was authored in;
##   * facing: the game expects the head toward +Z (Blender: -Y); set "yaw" (degrees)
##     in SLOTS if a new model faces another way;
##   * animations: each role (perch, fly, sit, walk, sleep, peck, ...) takes the first
##     clip whose name matches one of its aliases (case-insensitive, "Armature|" style
##     prefixes ignored). A model with no matching clip simply holds still.
## See assets/creatures/README.md for the list of slots.

const SLOTS := {
	"falcon": {"path": "res://assets/creatures/falcon.glb", "height": 0.22, "yaw": 0.0,
		"clips": {"perch": ["perch", "idle", "sit", "stand"], "fly": ["fly", "flap", "flying", "fly_loop"],
			"land": ["land", "landing"]}},
	"cat": {"path": "res://assets/creatures/cat.glb", "height": 0.27, "yaw": 0.0,
		"clips": {"sit": ["sit", "idle_sit", "sitting", "idle"], "walk": ["walk", "walking", "walk_loop"],
			"sleep": ["sleep", "lie", "lying", "rest", "sleeping"]}},
	"sparrow": {"path": "res://assets/creatures/sparrow.glb", "height": 0.14, "yaw": 0.0,
		"clips": {"peck": ["peck", "eat", "idle"], "fly": ["fly", "flap", "flying"]}},
}


## Instances the slot's model under a new Node3D (normalised size and facing), or
## returns null when the file is missing. The node keeps its AnimationPlayer and
## role → clip map as metadata for play().
static func spawn(parent: Node, kind: String) -> Node3D:
	var cfg: Dictionary = SLOTS[kind]
	if not ResourceLoader.exists(cfg.path):
		return null
	var root := Node3D.new()
	root.name = kind.capitalize()
	parent.add_child(root)
	var model: Node3D = (load(cfg.path) as PackedScene).instantiate()
	root.add_child(model)
	var box := _bounds(model)
	if box.size.y > 1e-4:
		var k: float = cfg.height / box.size.y
		model.scale = Vector3.ONE * k
		model.position = Vector3(-box.get_center().x * k, -box.position.y * k, -box.get_center().z * k)
	model.rotation.y = deg_to_rad(cfg.yaw)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var aps: Array = model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		var ap: AnimationPlayer = aps[0]
		var roles := {}
		for role in cfg.clips:
			var clip := _match(ap, cfg.clips[role])
			if clip != "":
				roles[role] = clip
				ap.get_animation(clip).loop_mode = Animation.LOOP_NONE if role == "land" else Animation.LOOP_LINEAR
		root.set_meta("anim", ap)
		root.set_meta("roles", roles)
	return root


## Plays a role (e.g. "fly"); returns false if the model has no clip for it.
static func play(root: Node3D, role: String, blend := 0.2, seek := -1.0) -> bool:
	if root == null or not root.has_meta("anim"):
		return false
	var roles: Dictionary = root.get_meta("roles")
	if not roles.has(role):
		return false
	var ap: AnimationPlayer = root.get_meta("anim")
	if ap.current_animation != roles[role]:
		ap.play(roles[role], blend)
	if seek >= 0.0:
		ap.seek(fmod(seek, maxf(ap.current_animation_length, 0.01)), true)
	return true


static func current_role(root: Node3D) -> String:
	if root == null or not root.has_meta("anim"):
		return ""
	var ap: AnimationPlayer = root.get_meta("anim")
	var roles: Dictionary = root.get_meta("roles")
	for r in roles:
		if roles[r] == ap.current_animation:
			return r
	return ""


static func _match(ap: AnimationPlayer, aliases: Array) -> String:
	var names := ap.get_animation_list()
	for want in aliases:
		for n in names:
			var short := String(n).get_slice("|", String(n).get_slice_count("|") - 1).to_lower()
			if short == want:
				return n
	for want in aliases:  # looser: "Falcon_Fly_Loop" matches "fly"
		for n in names:
			if String(n).to_lower().contains(want):
				return n
	return ""


static func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := _relative(m, n)
		var b: AABB = xf * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func _relative(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
