class_name Diorama
extends Node3D
## The scene-1 diorama (assets/world/scene1/scene1.glb, built in real metres by
## tools/blender/build_scene1.py), shown small on a table in mixed reality, and brought to
## life: the old man (live, dressed from the wardrobe), cats in a few spots, sparrows pecking
## and hopping, the falcon circling the tower. The parent moves, turns and resizes this node.
##
## Positions below are in the model's own metres (Godot axes: +Z is the gate side).
## Animals and the old man are drawn larger than life (LIFE_SCALE) so they read at table size.
## A level can switch off the pacing cat and the sparrows outside the gate (set before setup)
## and use model_point() / scare_birds() / play_shaib().

const SCENE1 := "res://assets/world/scene1/scene1.glb"
const SHAIB := "res://assets/character/shaib.glb"
const BASE_SCALE := 1.0 / 50.0   # 33 m island -> about 66 cm on the table
const LIFE_SCALE := {"cat": 2.4, "sparrow": 3.0, "falcon": 4.0, "shaib": 1.25}

# cats: position, facing (degrees), role
const CATS := [
	[Vector3(1.8, 3.19, 1.2), 10.0, "sit"],     # on the porch roof, watching the gate
	[Vector3(4.1, 0.0, -1.0), 200.0, "sleep"],  # asleep in the courtyard
	[Vector3(-1.9, 0.0, 0.7), 160.0, "sit"],    # by the house door
]
const CAT_WALK := [Vector3(0.35, 0.0, 7.6), Vector3(0.35, 0.0, 12.4)]  # along the stone path outside
# sparrow spots: they peck here and hop between them (the first six are inside the walls)
const SPARROW_SPOTS := [
	Vector3(-1.4, 0, 2.6), Vector3(-0.6, 0, 3.3), Vector3(2.2, 0, 3.0), Vector3(3.0, 0, 2.2),
	Vector3(-4.0, 0, -0.5), Vector3(4.2, 0, -4.4),
	Vector3(-2.0, 0, 9.0), Vector3(-2.7, 0, 9.8), Vector3(2.1, 0, 9.4), Vector3(2.8, 0, 10.4)]
const INSIDE_SPOTS := 6
const SPARROWS := 7
const SHAIB_AT := Vector3(0.9, 0.0, 4.4)
const FALCON_CENTRE := Vector3(8.25, 0.0, 6.25)  # the tower
const FALCON_RADIUS := 4.8
const FALCON_HEIGHT := 10.5

var model: Node3D
var shaib: Node3D
var shaib_anim: AnimationPlayer
var pacing_cat := true      # one cat walks the stone path outside the gate
var birds_outside := true   # sparrows also peck outside the gate
var _walker: Node3D
var _walk_t := 0.0
var _falcon: Node3D
var _falcon_a := 0.0
var _birds: Array = []  # {node, from, to, t, wait}
var _rng := RandomNumberGenerator.new()


func setup(path := SCENE1) -> void:
	var ps := load(path) as PackedScene
	if ps == null:
		push_error("Diorama: cannot load " + path)
		return
	model = ps.instantiate()
	add_child(model)
	model.scale = Vector3.ONE * BASE_SCALE
	_rng.seed = 7
	_add_shaib()
	_add_life()
	_no_shadows(self)


## The point on the diorama ground (model metres) hit by a world-space ray, or null.
func model_point(origin: Vector3, dir: Vector3):
	if model == null:
		return null
	var plane := Plane(model.global_basis.y.normalized(), model.global_position)
	var hit = plane.intersects_ray(origin, dir)
	if hit == null:
		return null
	var p: Vector3 = model.to_local(hit)
	p.y = 0.0
	return p


## Re-dress the old man (after the wardrobe changed).
func dress() -> void:
	var save := get_node_or_null("/root/Save")  # absent in headless tool scripts
	Wardrobe.apply(shaib, save.wearing if save else {})


## Plays one of the old man's clips; a one-shot clip goes back to `then` afterwards.
func play_shaib(clip: String, then := "idle") -> void:
	if shaib_anim == null or not shaib_anim.has_animation(clip):
		return
	shaib_anim.play(clip, 0.25)
	if then != "" and shaib_anim.has_animation(then) and shaib_anim.get_animation(clip).loop_mode == Animation.LOOP_NONE:
		shaib_anim.queue(then)


## Sparrows within r metres of p fly off to another spot.
func scare_birds(p: Vector3, r: float) -> void:
	for bd in _birds:
		var n: Node3D = bd.node
		if bd.t >= 1.0 and Vector2(n.position.x - p.x, n.position.z - p.z).length() < r:
			bd.wait = 0.0


func _add_shaib() -> void:
	var ps := load(SHAIB) as PackedScene
	if ps == null:
		return
	shaib = ps.instantiate()
	model.add_child(shaib)
	shaib.scale = Vector3.ONE * LIFE_SCALE.shaib
	shaib.position = SHAIB_AT
	var aps := shaib.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		shaib_anim = aps[0]
		for a in ["idle", "walk", "ardah", "idle_look", "think"]:
			if shaib_anim.has_animation(a):
				shaib_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		if shaib_anim.has_animation("idle"):
			shaib_anim.play("idle")
	dress()


func _creature(kind: String, at: Vector3, yaw_deg: float, role: String) -> Node3D:
	var c := CreatureSlot.spawn(model, kind)
	if c == null:
		return null
	c.scale = Vector3.ONE * LIFE_SCALE[kind]
	c.position = at
	c.rotation.y = deg_to_rad(yaw_deg)
	CreatureSlot.play(c, role, 0.0, _rng.randf() * 3.0)
	return c


func _spots() -> Array:
	return SPARROW_SPOTS if birds_outside else SPARROW_SPOTS.slice(0, INSIDE_SPOTS)


func _add_life() -> void:
	for cat in CATS:
		_creature("cat", cat[0], cat[1], cat[2])
	if pacing_cat:
		_walker = _creature("cat", CAT_WALK[0], 0.0, "walk")
	var spots := _spots()
	for i in SPARROWS:
		var b := _creature("sparrow", spots[i % spots.size()], _rng.randf_range(0, 360), "peck")
		if b:
			_birds.append({"node": b, "from": b.position, "to": b.position, "t": 1.0,
				"wait": _rng.randf_range(2.0, 9.0)})
	_falcon = _creature("falcon", FALCON_CENTRE + Vector3(FALCON_RADIUS, FALCON_HEIGHT, 0), 0.0, "fly")


func _process(dt: float) -> void:
	if model == null:
		return
	# the pacing cat walks the path: out, turn, back
	if _walker:
		_walk_t += dt * 0.12
		var u := pingpong(_walk_t, 1.0)
		var a: Vector3 = CAT_WALK[0]
		var b: Vector3 = CAT_WALK[1]
		_walker.position = a.lerp(b, smoothstep(0.0, 1.0, u))
		var going_out := fmod(_walk_t, 2.0) < 1.0
		_walker.rotation.y = 0.0 if going_out else PI
	# the falcon circles the tower, head first, banking into the turn
	if _falcon:
		_falcon_a += dt * 0.35
		var p := FALCON_CENTRE + Vector3(cos(_falcon_a) * FALCON_RADIUS, FALCON_HEIGHT + sin(_falcon_a * 2.0) * 0.8,
			sin(_falcon_a) * FALCON_RADIUS)
		_falcon.position = p
		# it moves along (-sin a, 0, cos a); the model faces +Z, so its yaw is -a
		_falcon.rotation = Vector3(0, -_falcon_a, deg_to_rad(16))
	# sparrows peck, then now and then hop-fly to another spot
	var spots := _spots()
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
				var to: Vector3 = spots[_rng.randi() % spots.size()] + Vector3(_rng.randf_range(-0.5, 0.5), 0, _rng.randf_range(-0.5, 0.5))
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
