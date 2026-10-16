class_name Diorama
extends Node3D
## Tabletop preview of a scene diorama (assets/world/scene1/scene1.glb, built in real metres by
## tools/blender/build_scene1.py), shown small on a table in mixed reality. No gameplay.
## The parent moves, turns and resizes this node; this node loads the model and brings it to
## life: cats in a few spots (sitting, asleep, one walking the path), sparrows pecking and
## hopping from spot to spot, and the falcon circling the tower.
##
## Positions below are in the model's own metres (Godot axes: +Z is the gate side).
## The animals are drawn larger than life (LIFE_SCALE) so they still read at table size.

const SCENE1 := "res://assets/world/scene1/scene1.glb"
const BASE_SCALE := 1.0 / 50.0   # 33 m island -> about 66 cm on the table
const LIFE_SCALE := {"cat": 2.4, "sparrow": 3.0, "falcon": 4.0}

# cats: position, facing (degrees), role
const CATS := [
	[Vector3(1.8, 3.19, 1.2), 10.0, "sit"],     # on the porch roof, watching the gate
	[Vector3(4.1, 0.0, -1.0), 200.0, "sleep"],  # asleep in the courtyard
	[Vector3(-1.9, 0.0, 0.7), 160.0, "sit"],    # by the house door
]
const CAT_WALK := [Vector3(0.35, 0.0, 7.6), Vector3(0.35, 0.0, 12.4)]  # along the stone path outside
# sparrow spots: they peck here and hop between them
const SPARROW_SPOTS := [
	Vector3(-1.4, 0, 2.6), Vector3(-0.6, 0, 3.3), Vector3(2.2, 0, 3.0), Vector3(3.0, 0, 2.2),
	Vector3(-2.0, 0, 9.0), Vector3(-2.7, 0, 9.8), Vector3(2.1, 0, 9.4), Vector3(2.8, 0, 10.4),
	Vector3(-4.0, 0, -0.5), Vector3(4.2, 0, -4.4)]
const SPARROWS := 7
const FALCON_CENTRE := Vector3(8.25, 0.0, 6.25)  # the tower
const FALCON_RADIUS := 4.8
const FALCON_HEIGHT := 10.5

var model: Node3D
var _walker: Node3D
var _walk_t := 0.0
var _falcon: Node3D
var _falcon_a := 0.0
var _birds: Array = []  # {node, spot, from, to, t, wait}
var _rng := RandomNumberGenerator.new()


func setup(path := SCENE1) -> void:
	var ps := load(path) as PackedScene
	if ps == null:
		push_error("Diorama: cannot load " + path)
		return
	model = ps.instantiate()
	add_child(model)
	model.scale = Vector3.ONE * BASE_SCALE
	for n in model.find_children("*", "Node3D", true, false):
		var nm := String(n.name)
		if nm.begins_with("Bisht") or nm.begins_with("Glasses") or nm.begins_with("Misbaha"):
			(n as Node3D).visible = false
	_rng.seed = 7
	_add_life()
	_no_shadows(self)


func _creature(kind: String, at: Vector3, yaw_deg: float, role: String) -> Node3D:
	var c := CreatureSlot.spawn(model, kind)
	if c == null:
		return null
	c.scale = Vector3.ONE * LIFE_SCALE[kind]
	c.position = at
	c.rotation.y = deg_to_rad(yaw_deg)
	CreatureSlot.play(c, role, 0.0, _rng.randf() * 3.0)
	return c


func _add_life() -> void:
	for cat in CATS:
		_creature("cat", cat[0], cat[1], cat[2])
	_walker = _creature("cat", CAT_WALK[0], 0.0, "walk")
	for i in SPARROWS:
		var spot: int = i % SPARROW_SPOTS.size()
		var b := _creature("sparrow", SPARROW_SPOTS[spot], _rng.randf_range(0, 360), "peck")
		if b:
			_birds.append({"node": b, "from": b.position, "to": b.position, "t": 1.0,
				"wait": _rng.randf_range(2.0, 9.0)})
	_falcon = _creature("falcon", FALCON_CENTRE + Vector3(FALCON_RADIUS, FALCON_HEIGHT, 0), 0.0, "fly")


func _process(dt: float) -> void:
	if model == null:
		return
	# the walking cat paces the path: out, turn, back
	if _walker:
		_walk_t += dt * 0.12
		var u := pingpong(_walk_t, 1.0)
		var a: Vector3 = CAT_WALK[0]
		var b: Vector3 = CAT_WALK[1]
		_walker.position = a.lerp(b, smoothstep(0.0, 1.0, u))
		var going_out := fmod(_walk_t, 2.0) < 1.0
		_walker.rotation.y = 0.0 if going_out else PI
	# the falcon circles the tower, banking gently
	if _falcon:
		_falcon_a += dt * 0.35
		var p := FALCON_CENTRE + Vector3(cos(_falcon_a) * FALCON_RADIUS, FALCON_HEIGHT + sin(_falcon_a * 2.0) * 0.8,
			sin(_falcon_a) * FALCON_RADIUS)
		_falcon.position = p
		_falcon.rotation = Vector3(0, -_falcon_a + PI, deg_to_rad(18))
	# sparrows peck, then now and then hop-fly to another spot
	for bd in _birds:
		var n: Node3D = bd.node
		if bd.t < 1.0:
			bd.t = minf(1.0, bd.t + dt / 1.2)
			var f: Vector3 = bd.from
			var to: Vector3 = bd.to
			n.position = f.lerp(to, bd.t) + Vector3(0, sin(bd.t * PI) * 1.6, 0)
			if bd.t >= 1.0:
				CreatureSlot.play(n, "peck")
		else:
			bd.wait -= dt
			if bd.wait <= 0.0:
				var to: Vector3 = SPARROW_SPOTS[_rng.randi() % SPARROW_SPOTS.size()] + Vector3(_rng.randf_range(-0.5, 0.5), 0, _rng.randf_range(-0.5, 0.5))
				bd.from = n.position
				bd.to = to
				bd.t = 0.0
				bd.wait = _rng.randf_range(4.0, 12.0)
				var d: Vector3 = to - n.position
				if Vector2(d.x, d.z).length() > 0.01:
					n.rotation.y = atan2(d.x, d.z)
				CreatureSlot.play(n, "fly")


static func _no_shadows(n: Node) -> void:
	for mi in n.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
