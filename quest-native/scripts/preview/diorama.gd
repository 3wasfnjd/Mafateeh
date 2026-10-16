class_name Diorama
extends Node3D
## A scene diorama (assets/world/scene<N>/scene<N>.glb, built in real metres by
## tools/blender/build_scene<N>.py), shown small on a table in mixed reality, and brought to
## life: the old man (live, dressed from the wardrobe), cats, hens, sparrows pecking and
## hopping, the falcon circling. What lives where is in LAYOUTS. The parent moves, turns and
## resizes this node.
##
## Positions below are in the model's own metres (Godot axes: +Z is the gate side).
## A level can switch off the pacing cat and the sparrows outside the gate (set before setup)
## and use model_point() / scare_birds() / play_shaib().

const SHAIB := "res://assets/character/shaib.glb"
const BASE_SCALE := 1.0 / 50.0   # 33 m island -> about 66 cm on the table
# true to the old man (1.6 m): cat about 0.43 m, hen about 0.42 m, sparrow about 0.16 m;
# the falcon, always up in the air, a little larger than life so it reads
const LIFE_SCALE := {"cat": 1.6, "sparrow": 1.15, "falcon": 2.2, "shaib": 1.25, "hen": 0.62}
const HEN := "res://assets/world/props/hen.glb"
const ROOSTER := "res://assets/world/props/rooster.glb"

# One layout per scene (model metres, Godot axes):
#   scene     the baked diorama (tools/blender/build_scene<N>.py)
#   cats      [position, facing in degrees, role]: cats that just live there
#   cat_walk  the pacing cat's two ends (when pacing_cat)
#   sparrows  spots they peck at and hop between; the first `inside` are the ones kept
#             when birds_outside is off
#   hens      [kind, start]; they wander inside hen_area (kept clear of walls and porch)
#   falcon    centre, radius and height of its circle
#   shaib     where the old man is, and his first clip
const LAYOUTS := {
	1: {
		"scene": "res://assets/world/scene1/scene1.glb",
		"cats": [[Vector3(5.6, 0.0, 1.0), 200.0, "sleep"]],   # asleep in a corner of the courtyard
		"cat_walk": [Vector3(0.35, 0.0, 7.6), Vector3(0.35, 0.0, 12.4)],
		"sparrows": [
			Vector3(-1.4, 0, 2.6), Vector3(-0.6, 0, 3.3), Vector3(2.2, 0, 3.0), Vector3(3.0, 0, 2.2),
			Vector3(-4.0, 0, -0.5), Vector3(4.2, 0, -4.4),
			Vector3(-2.0, 0, 9.0), Vector3(-2.7, 0, 9.8), Vector3(2.1, 0, 9.4), Vector3(2.8, 0, 10.4)],
		"inside": 6,
		"hens": [["hen", Vector3(-4.6, 0, 2.6)], ["hen", Vector3(-3.4, 0, 4.4)], ["rooster", Vector3(4.2, 0, 3.6)]],
		"hen_area": Rect2(-7.0, 2.4, 12.0, 3.0),  # x0, z0, w, d: clear of the walls, the tower's corner and the porch
		"falcon": [Vector3(8.25, 0.0, 6.25), 4.8, 10.5],      # round the tower
		"shaib": [Vector3(0.0, 0.0, 0.75), 0.0, "sit_idle"],   # seated on the porch, facing the gate
	},
	2: {
		"scene": "res://assets/world/scene2/scene2.glb",
		"cats": [],
		"cat_walk": [],
		"sparrows": [
			Vector3(-5.0, 0, 5.0), Vector3(-3.6, 0, 6.0), Vector3(3.0, 0, 5.6), Vector3(5.2, 0, 4.0),
			Vector3(-6.4, 0, 1.6), Vector3(2.6, 0, 6.6)],
		"inside": 6,
		"hens": [],
		"hen_area": Rect2(),
		"falcon": [Vector3(-3.5, 0.0, -3.0), 5.5, 9.5],       # round the tall house
		"shaib": [Vector3(-1.8, 0.0, 2.6), 40.0, "idle"],      # standing in the lane
	},
	3: {
		"scene": "res://assets/world/scene3/scene3.glb",
		"cats": [],
		"cat_walk": [],
		"sparrows": [
			Vector3(-2.6, 0, 0.6), Vector3(-3.4, 0, -2.0), Vector3(2.2, 0, 0.8), Vector3(1.6, 0, -5.2),
			Vector3(-1.2, 0, -5.0), Vector3(3.6, 0, -3.0)],
		"inside": 6,
		"hens": [],
		"hen_area": Rect2(),
		"falcon": [],                                          # the level's own falcon is the hero
		"shaib": [Vector3(0.0, 0.0, -2.0), 0.0, "sit_idle"],   # seated at the front of the arish, facing the gate
	},
}
const SPARROWS := 7

var layout: Dictionary = LAYOUTS[1]
var model: Node3D
var stage: Node3D       # everything but the ground: it sinks into the ground and rises (set_rise)
var shaib: Node3D
var shaib_anim: AnimationPlayer
var pacing_cat := true      # one cat walks the stone path outside the gate
var birds_outside := true   # sparrows also peck outside the gate
var _walker: Node3D
var _walk_t := 0.0
var _falcon: Node3D
var _falcon_a := 0.0
var _birds: Array = []  # {node, from, to, t, wait}
var _hens: Array = []   # {node, target, wait, peck, speed}
var _rng := RandomNumberGenerator.new()


func setup(scene := 1) -> void:
	layout = LAYOUTS[scene]
	var ps := load(layout.scene) as PackedScene
	if ps == null:
		push_error("Diorama: cannot load " + str(layout.scene))
		return
	model = ps.instantiate()
	add_child(model)
	model.scale = Vector3.ONE * BASE_SCALE
	# the ground and its plinth stay; the buildings, palms and life move to the stage
	stage = Node3D.new()
	stage.name = "Stage"
	for c in model.get_children():
		if not (str(c.name).begins_with("Ground") or str(c.name).begins_with("Plinth")):
			model.remove_child(c)
			c.owner = null   # (its own children keep the scene as owner, still an ancestor)
			stage.add_child(c)
	model.add_child(stage)
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


## Level change: 1 = the scene stands; 0 = sunk into the ground (squashed flat, a little below).
## The ground itself stays.
func set_rise(k: float) -> void:
	if stage == null:
		return
	var e := smoothstep(0.0, 1.0, k)
	stage.scale = Vector3(1.0, maxf(e, 0.01), 1.0)
	stage.position.y = -0.6 * (1.0 - e)
	stage.visible = e > 0.005


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
	stage.add_child(shaib)
	shaib.scale = Vector3.ONE * LIFE_SCALE.shaib
	shaib.position = layout.shaib[0]
	shaib.rotation.y = deg_to_rad(layout.shaib[1])
	var aps := shaib.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		shaib_anim = aps[0]
		for a in ["idle", "walk", "push", "ardah", "idle_look", "sit_idle", "sit_pet"]:
			if shaib_anim.has_animation(a):
				shaib_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		var first: String = layout.shaib[2] if shaib_anim.has_animation(layout.shaib[2]) else "idle"
		shaib_anim.play(first)
	dress()


func _creature(kind: String, at: Vector3, yaw_deg: float, role: String) -> Node3D:
	var c := CreatureSlot.spawn(stage, kind)
	if c == null:
		return null
	c.scale = Vector3.ONE * LIFE_SCALE[kind]
	c.position = at
	c.rotation.y = deg_to_rad(yaw_deg)
	CreatureSlot.play(c, role, 0.0, _rng.randf() * 3.0)
	return c


func _spots() -> Array:
	var all: Array = layout.sparrows
	return all if birds_outside else all.slice(0, layout.inside)


func _add_life() -> void:
	for cat in layout.cats:
		_creature("cat", cat[0], cat[1], cat[2])
	if pacing_cat and not layout.cat_walk.is_empty():
		_walker = _creature("cat", layout.cat_walk[0], 0.0, "walk")
	var spots := _spots()
	for i in SPARROWS:
		var b := _creature("sparrow", spots[i % spots.size()], _rng.randf_range(0, 360), "peck")
		if b:
			_birds.append({"node": b, "from": b.position, "to": b.position, "t": 1.0,
				"wait": _rng.randf_range(2.0, 9.0)})
	if not layout.falcon.is_empty():
		_falcon = _creature("falcon", layout.falcon[0] + Vector3(layout.falcon[1], layout.falcon[2], 0), 0.0, "fly")
	for h in layout.hens:
		var ps := load(HEN if h[0] == "hen" else ROOSTER) as PackedScene
		if ps == null:
			continue
		var n: Node3D = ps.instantiate()
		stage.add_child(n)
		n.position = h[1]
		n.scale = Vector3.ONE * LIFE_SCALE.hen
		n.rotation.y = _rng.randf() * TAU
		_hens.append({"node": n, "target": h[1], "wait": _rng.randf_range(0.5, 3.0), "peck": 0.0, "speed": 0.0, "flee": 0.0})


## Hens near p run off (the cat walking by).
func scare_hens(p: Vector3, r: float) -> void:
	for hd in _hens:
		var n: Node3D = hd.node
		var d := Vector3(n.position.x - p.x, 0, n.position.z - p.z)
		if d.length() < r:
			var away := d.normalized() if d.length() > 0.01 else Vector3.RIGHT
			hd.target = _in_hen_area(n.position + away * 2.5)
			hd.flee = 1.0
			hd.wait = 0.0


func _in_hen_area(p: Vector3) -> Vector3:
	var r: Rect2 = layout.hen_area
	return Vector3(clampf(p.x, r.position.x, r.end.x), 0, clampf(p.z, r.position.y, r.end.y))


func _update_hens(dt: float) -> void:
	for hd in _hens:
		var n: Node3D = hd.node
		var to: Vector3 = hd.target - n.position
		to.y = 0
		var d := to.length()
		if d > 0.08:
			var speed := 2.6 if hd.flee > 0.0 else 0.8
			n.position += to / d * minf(d, speed * dt)
			var want := atan2(to.x, to.z)
			n.rotation.y = lerp_angle(n.rotation.y, want, clampf(dt * 8.0, 0, 1))
			var hop := absf(sin(Time.get_ticks_msec() * 0.001 * (14.0 if hd.flee > 0.0 else 9.0)))
			n.position.y = hop * (0.12 if hd.flee > 0.0 else 0.05)
			n.rotation.x = 0.0
			hd.peck = 0.0
		else:
			n.position.y = 0.0
			hd.flee = 0.0
			hd.wait -= dt
			hd.peck += dt
			# peck: dip forward now and then
			n.rotation.x = 0.45 * maxf(0.0, sin(hd.peck * 5.0)) ** 3
			if hd.wait <= 0.0:
				hd.target = _in_hen_area(n.position + Vector3(_rng.randf_range(-2.5, 2.5), 0, _rng.randf_range(-1.8, 1.8)))
				hd.wait = _rng.randf_range(1.5, 4.5)


func _process(dt: float) -> void:
	if model == null:
		return
	_update_hens(dt)
	# the pacing cat walks the path: out, turn, back
	if _walker:
		_walk_t += dt * 0.12
		var u := pingpong(_walk_t, 1.0)
		var a: Vector3 = layout.cat_walk[0]
		var b: Vector3 = layout.cat_walk[1]
		_walker.position = a.lerp(b, smoothstep(0.0, 1.0, u))
		var going_out := fmod(_walk_t, 2.0) < 1.0
		_walker.rotation.y = 0.0 if going_out else PI
	# the falcon circles the tower, head first, banking into the turn
	if _falcon:
		_falcon_a += dt * 0.35
		var c: Vector3 = layout.falcon[0]
		var fr: float = layout.falcon[1]
		var p := c + Vector3(cos(_falcon_a) * fr, layout.falcon[2] + sin(_falcon_a * 2.0) * 0.8, sin(_falcon_a) * fr)
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
