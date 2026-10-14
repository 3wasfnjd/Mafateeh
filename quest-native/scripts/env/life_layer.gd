class_name LifeLayer
extends Node3D
## Ambient life around the miniature (board space, rebuilt per level, seeded so a
## level always looks the same): sparrows peck between the paving stones and flit up
## to the wall tops when the old man comes close, a sandy courtyard cat dozes or sits
## on a wall, and a villager in a white ghutra strolls round outside the walls.
## Purely decorative: never touches the puzzle and never stands where the hero walks.

const VILLAGER := "res://assets/character/shaib.glb"
const FLEE_DIST := 1.1
const VILLAGER_SPEED := 0.45

var game: Game
var _rng := RandomNumberGenerator.new()
var _birds: Array = []  # {node, ground: Vector3, perch: Vector3, mode, t, from, to}
var _cat: Node3D
var _walker: Node3D
var _walker_anim: AnimationPlayer
var _walk_path: Array = []
var _walk_s := 0.0
var _walk_len := 0.0


func setup(g: Game) -> void:
	game = g


func _instance(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var n: Node3D = (load(path) as PackedScene).instantiate()
	add_child(n)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return n


func _anim(n: Node3D) -> AnimationPlayer:
	var a: Array = n.find_children("*", "AnimationPlayer", true, false)
	return a[0] if not a.is_empty() else null


func _loop(ap: AnimationPlayer, clips: Array) -> void:
	if ap == null:
		return
	for c in clips:
		if ap.has_animation(c):
			ap.get_animation(c).loop_mode = Animation.LOOP_LINEAR


func build(level: int, def: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	_birds.clear()
	_cat = null
	_walker = null
	_rng.seed = 7000 + level * 31
	var bd: Array = def.get("bounds", PuzzleState.COURT)
	var ey := LevelData.exit_y(def)
	var ex := LevelData.exit_x(def)
	# Wall-top perches: the low front wall, the side walls, the back wall away from the gate.
	var perches: Array = []
	for i in 6:
		var x := _rng.randf_range(bd[0] + 0.4, bd[1] - 0.4)
		perches.append(Vector3(x, 0.47, bd[3] + 0.54))
	for sx in [bd[0] - 0.44, bd[1] + 0.44]:
		for i in 2:
			perches.append(Vector3(sx, 1.0, _rng.randf_range(-2.6, 2.6)))
	for i in 3:
		var x := _rng.randf_range(bd[0] + 0.3, bd[1] - 0.3)
		if absf(x - ex) > 1.2:
			perches.append(Vector3(x, ey + 1.1, -3.59))
	# Sparrows: two peck on the paving near the edges, two wait on the walls.
	var n_birds := 4 if _rng.randf() < 0.8 else 2
	for i in n_birds:
		var b := CreatureSlot.spawn(self, "sparrow")
		if b == null:
			break
		var perch: Vector3 = perches[_rng.randi() % perches.size()]
		var ground := perch
		if i < 2:
			var gx := _rng.randf_range(bd[0] + 0.3, bd[1] - 0.3)
			var gz: float = bd[3] - _rng.randf_range(0.2, 0.6)
			if LevelData.surface_y(def, gx, gz) < 0.05:
				ground = Vector3(gx, 0.07, gz)
		b.position = ground
		b.rotation.y = _rng.randf() * TAU
		CreatureSlot.play(b, "peck", 0.0, _rng.randf() * 2.0)
		_birds.append({"node": b, "ground": ground, "perch": perch, "mode": "ground" if ground != perch else "perch",
			"t": 0.0, "from": ground, "to": ground})
	# The cat: dozing on the back wall or sitting on a corner of the front wall.
	if _rng.randf() < 0.75:
		_cat = CreatureSlot.spawn(self, "cat")
		if _cat:
			var on_back := _rng.randf() < 0.5
			var x: float = _rng.randf_range(bd[0] + 0.5, bd[1] - 0.5)
			if on_back and absf(x - ex) < 1.3:
				x = bd[0] + 0.7
			_cat.position = Vector3(x, ey + 1.08, -3.59) if on_back else Vector3(bd[1] + 0.44, 0.97, _rng.randf_range(-2.0, 2.0))
			_cat.rotation.y = PI if on_back else -PI / 2
			if not (on_back and CreatureSlot.play(_cat, "sleep", 0.0)):
				CreatureSlot.play(_cat, "sit", 0.0)
	# A villager strolling round outside the walls (not in every level).
	if _rng.randf() < 0.6:
		_walker = _instance(VILLAGER)
		if _walker:
			_walker.scale = Vector3.ONE * 0.94
			_walker_anim = _anim(_walker)
			_loop(_walker_anim, ["walk"])
			if _walker_anim and _walker_anim.has_animation("walk"):
				_walker_anim.play("walk")
				_walker_anim.speed_scale = VILLAGER_SPEED * _walker_anim.get_animation("walk").length / 0.66
			_dress_villager(_walker)
			var xl: float = bd[0] - 1.05
			var xr: float = bd[1] + 1.05
			_walk_path = [Vector2(xl, 3.9), Vector2(xl, -4.55), Vector2(xr, -4.55), Vector2(xr, 3.9)]
			if _rng.randf() < 0.5:
				_walk_path.reverse()
			_walk_len = 0.0
			for i in _walk_path.size() - 1:
				_walk_len += _walk_path[i].distance_to(_walk_path[i + 1])
			_walk_s = _rng.randf() * _walk_len


## Finale: a row of villagers performs the ardah outside the low front wall, facing
## the player, swaying their canes in time like the swords of the Najdi war dance.
func ardah(def: Dictionary) -> void:
	var bd: Array = def.get("bounds", PuzzleState.COURT)
	var n := 7
	var span: float = minf(bd[1] - bd[0] + 0.6, 6.4)
	for i in n:
		var d := _instance(VILLAGER)
		if d == null:
			return
		_dress_villager(d, true)
		var x: float = (bd[0] + bd[1]) / 2.0 - span / 2.0 + span * i / float(n - 1)
		d.position = Vector3(x, -0.05, bd[3] + 1.15 + 0.12 * absf(i - (n - 1) / 2.0))
		d.rotation.y = -0.08 * (i - (n - 1) / 2.0)
		d.scale = Vector3.ONE * _rng.randf_range(0.9, 0.98)
		var ap := _anim(d)
		_loop(ap, ["ardah"])
		if ap and ap.has_animation("ardah"):
			ap.play("ardah")
			ap.seek(fmod(i * 0.1, 0.4))
			ap.speed_scale = 1.0


## Villagers: white ghutra, beige or white thobe, no cane in hand, no falcon.
func _dress_villager(n: Node3D, with_cane := false) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		if nm.begins_with("Bisht") or nm.begins_with("Glasses") or nm.begins_with("Misbaha") or (nm.begins_with("Cane") and not with_cane):
			mi.visible = false
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if base == null:
				continue
			if base.resource_name.begins_with("shemagh"):
				var o := base.duplicate() as StandardMaterial3D
				o.albedo_texture = load("res://assets/character/wardrobe/ghutra.png")
				o.normal_enabled = false
				mi.set_surface_override_material(i, o)
			elif base.resource_name == "thobe" and _rng.randf() < 0.5:
				var o := base.duplicate() as StandardMaterial3D
				o.albedo_color = Color("e9dcc2")
				mi.set_surface_override_material(i, o)


func _path_point(s: float) -> Array:
	var left := fmod(s, _walk_len * 2.0)
	var forward := left < _walk_len
	if not forward:
		left = _walk_len * 2.0 - left
	for i in _walk_path.size() - 1:
		var seg: float = _walk_path[i].distance_to(_walk_path[i + 1])
		if left <= seg:
			var a: Vector2 = _walk_path[i]
			var b: Vector2 = _walk_path[i + 1]
			var p := a.lerp(b, left / maxf(seg, 1e-4))
			var d := (b - a).normalized() * (1.0 if forward else -1.0)
			return [p, d]
		left -= seg
	return [_walk_path[-1], Vector2(0, 1)]


func _process(dt: float) -> void:
	if game == null or game.state == null:
		return
	var hero: Vector2 = game.motor.pos
	for b in _birds:
		var n: Node3D = b.node
		b.t += dt
		match b.mode:
			"ground":
				if Vector2(n.position.x, n.position.z).distance_to(hero) < FLEE_DIST:
					_fly(b, b.perch)
			"perch":
				if b.ground != b.perch and b.t > 6.0 and Vector2(b.ground.x, b.ground.z).distance_to(hero) > FLEE_DIST * 2.0:
					_fly(b, b.ground)
			"fly":
				var k := clampf(b.t / 0.9, 0.0, 1.0)
				var p: Vector3 = b.from.lerp(b.to, k)
				p.y += sin(k * PI) * 0.5
				n.position = p
				if k >= 1.0:
					b.mode = "perch" if b.to == b.perch else "ground"
					b.t = 0.0
					CreatureSlot.play(b.node, "peck", 0.15)
	if _walker and _walk_len > 0.0:
		_walk_s += dt * VILLAGER_SPEED
		var pd := _path_point(_walk_s)
		_walker.position = Vector3(pd[0].x, -0.05, pd[0].y)
		_walker.rotation.y = atan2(pd[1].x, pd[1].y)


func _fly(b: Dictionary, to: Vector3) -> void:
	b.mode = "fly"
	b.t = 0.0
	b.from = b.node.position
	b.to = to
	var d: Vector3 = to - b.from
	if Vector2(d.x, d.z).length() > 0.01:
		b.node.rotation.y = atan2(d.x, d.z)
	CreatureSlot.play(b.node, "fly", 0.1)
