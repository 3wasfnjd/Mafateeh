class_name TableRaidLevel
extends Node3D
## Level 10 on the table, «الغزوة» (the raid). Wordless. Day, in the open desert.
## Scene: the old man's camp at the front, open sand in the middle, high dunes at the back.
## Raiders of another tribe come over the dunes on camels and horses, their shemaghs drawn
## across their faces, and gallop down on the camp, firing as they come. The old man sits his
## horse at the front with three men of his tribe mounted beside him. Point at a raider and pull
## the trigger: the old man and his men fire on him, and he falls from his saddle and is gone,
## while his mount bolts back over the dunes. Unhorse them all and the raid is beaten:
## the old man's men fire into the sky for joy.
##
## Lives under Diorama.stage: positions are in the diorama's own metres (Godot axes).

signal level_won

const CAMEL := "res://assets/world/props/camel_ride.glb"   # tools/blender/build_mounts.py
const HORSE := "res://assets/world/props/horse.glb"
const RIDER_SCALE := Diorama.LIFE_SCALE.shaib
const HIPS := 0.5                     # the rider's hips above his feet, in his own units
const OLD_MAN := Vector3(0.0, 0.0, 2.6)   # in front of the tent, in the open
# the old man's men, mounted beside him: [where, camel?, dress]
const DEFENDERS := [
	[Vector3(-3.3, 0.0, 2.9), true, {"head": "ghutra"}],
	[Vector3(3.3, 0.0, 2.9), false, {"thobe": "thobe_beige"}],
	[Vector3(6.4, 0.0, 3.4), false, {"thobe": "thobe_grey", "head": "ghutra"}],
]
# the raiders, in waves: [seconds after the start, x where they come over the dunes, camel?]
const RAIDERS := [
	[1.0, -4.0, true], [2.2, 5.0, false],
	[9.0, -8.0, false], [9.8, 1.0, true], [10.6, 7.5, false],
	[18.0, -2.5, false], [18.6, 4.0, true], [19.4, -7.0, true],
]
const RAIDER_DRESS := [{"thobe": "thobe_grey"}, {"thobe": "thobe_beige"}, {}, {"thobe": "thobe_grey", "bisht": "bisht"}]
const RIM_Z := -12.6                  # where they come over the dunes
const NEAR_Z := -2.2                  # how close they ride before they wheel away again
const BACK_Z := -6.0                  # how far back they wheel before coming on again
const GALLOP := 3.4                   # metres a second
const HINT_AFTER := 9.0
const TRACER := Color("ffb347")
const GOLD := Color("e6b85a")

var diorama: Diorama
var assist := true                    # the targets move: the pointer snaps to them
var _t := 0.0
var _ray := []
var _was_held := false
var _raiders: Array = []              # {mount, rider, legs, camel, gun, state, to, fire_in, phase}
var _defenders: Array = []            # {mount, rider, gun, legs, camel, aim}
var _spawned := 0
var _down := 0
var _won := false
var _idle_t := 0.0
var _hint_ring: MeshInstance3D
var _demo := false
var _demo_t := 0.0


func setup(d: Diorama) -> void:
	diorama = d
	# the old man on his horse, in the middle of his men
	if diorama.shaib:
		var horse := _mount(false, _on_ground(OLD_MAN), PI)
		var seat: Node3D = horse.root.find_child("Seat", true, false)
		var s := diorama.shaib
		s.position = horse.root.position + _seat_offset(seat).rotated(Vector3.UP, PI)
		s.rotation.y = PI
		var cane := s.find_child("Cane", true, false)
		if cane:
			(cane as Node3D).visible = false
		diorama.play_shaib("ride", "")
		horse["rider"] = s
		horse["gun"] = _arm(s)
		horse["aim"] = Vector3.ZERO
		_defenders.append(horse)
	for k in DEFENDERS.size():
		var dfn: Array = DEFENDERS[k]
		var m := _mount(dfn[1], _on_ground(dfn[0]), PI)
		var r := _rider(m, dfn[2], false)
		m["rider"] = r
		m["gun"] = _arm(r)
		m["aim"] = Vector3.ZERO
		_defenders.append(m)
	_hint_ring = TableKit.ring(self, 0.9, GOLD, 0.9)
	_hint_ring.visible = false


# --- building the riders -------------------------------------------------------------------------

## A mount standing at `at` facing yaw (0 = +z): {root, legs, camel}.
func _mount(camel: bool, at: Vector3, yaw: float) -> Dictionary:
	var root := TableKit.model(self, CAMEL if camel else HORSE, at, yaw, 1.0)
	if root == null:
		root = Node3D.new()
		add_child(root)
		root.position = at
	var legs := []
	for n in ["Leg_FL", "Leg_FR", "Leg_BL", "Leg_BR"]:
		var l := root.find_child(n, true, false)
		if l:
			legs.append(l)
	if not camel:
		_coat(root)
	return {"root": root, "legs": legs, "camel": camel}


## Each horse its own colour: bay, chestnut, grey or near black.
func _coat(root: Node3D) -> void:
	var c: Color = [Color("8a5a35"), Color("a8643a"), Color("b8b2a8"), Color("3b2a22")][randi() % 4]
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i) as StandardMaterial3D
			if m and m.resource_name == "horse_coat":
				var m2 := m.duplicate() as StandardMaterial3D
				m2.albedo_color = c
				(mi as MeshInstance3D).set_surface_override_material(i, m2)


## Where the rider's feet go so his hips sit in the saddle (mount space).
func _seat_offset(seat: Node3D) -> Vector3:
	return (seat.position if seat else Vector3(0, 1.3, 0)) - Vector3(0, HIPS * RIDER_SCALE, 0)


## A man of the desert in the saddle of mount m, riding.
func _rider(m: Dictionary, dress: Dictionary, raider: bool) -> Node3D:
	var root: Node3D = m.root
	var r := TableKit.model(root, Diorama.SHAIB, Vector3.ZERO, 0.0, RIDER_SCALE)
	if r == null:
		return null
	r.position = _seat_offset(root.find_child("Seat", true, false))
	var w := dress.duplicate()
	if raider:
		w["litham"] = true   # the shemagh drawn across the face
	Wardrobe.apply(r, w)
	var cane := r.find_child("Cane", true, false)
	if cane:
		(cane as Node3D).visible = false
	var ap := _anim(r)
	if ap and ap.has_animation("ride"):
		ap.get_animation("ride").loop_mode = Animation.LOOP_LINEAR
		ap.play("ride")
		ap.seek(randf() * 0.6)
	return r


func _anim(n: Node) -> AnimationPlayer:
	var aps := n.find_children("*", "AnimationPlayer", true, false) if n else []
	return aps[0] if not aps.is_empty() else null


## A rifle in the man's right hand; it is turned to its mark every frame (_process).
func _arm(man: Node3D) -> Node3D:
	if man == null:
		return null
	var sks := man.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return null
	var hold := BoneAttachment3D.new()
	hold.bone_name = "Hand.R"
	(sks[0] as Skeleton3D).add_child(hold)
	var gun := TableChestLevel.rifle()
	hold.add_child(gun)
	gun.top_level = true
	return gun


# --- the raiders ---------------------------------------------------------------------------------

func _spawn(k: int) -> void:
	var r: Array = RAIDERS[k]
	var at := _on_ground(Vector3(r[1], 0, RIM_Z))
	var m := _mount(r[2], at, 0.0)
	m["rider"] = _rider(m, RAIDER_DRESS[k % RAIDER_DRESS.size()], true)
	m["gun"] = _arm(m.rider)
	m["state"] = "charge"
	m["to"] = Vector3(clampf(r[1] * 0.7, -7.0, 7.0), 0, NEAR_Z - randf() * 1.5)
	m["fire_in"] = randf_range(1.5, 2.5)
	m["phase"] = randf() * TAU
	m["id"] = k
	_raiders.append(m)
	TableKit.sfx(self, "gate_lift", at, -10.0, 1.6)   # hooves on the crest


func _process(dt: float) -> void:
	_t += dt
	while _spawned < RAIDERS.size() and _t >= RAIDERS[_spawned][0] and not _won:
		_spawn(_spawned)
		_spawned += 1
	for m in _raiders:
		_ride(m, dt)
	for m in _defenders:
		_legs(m, 0.0, dt)
	_aim_guns()
	if _won:
		return
	if _demo:
		_demo_t -= dt
		if _demo_t <= 0.0:
			for m in _raiders:
				if m.state in ["charge", "wheel"]:
					_fire_on(m)
					_demo_t = 0.8
					break
	_idle_t += dt
	_hint_ring.visible = false
	if _idle_t > HINT_AFTER:
		var m := _nearest_raider()
		if not m.is_empty():
			_hint_ring.visible = true
			var pulse := 1.0 + 0.12 * sin(_t * 6.0)
			_hint_ring.position = (m.root as Node3D).position + Vector3(0, 0.1, 0)
			_hint_ring.scale = Vector3(pulse * 1.6, 1.0, pulse * 1.6)


## One raider's ride this frame: charging down on the camp, wheeling back and coming on again,
## firing now and then; or, unhorsed, his mount bolting back over the dunes.
func _ride(m: Dictionary, dt: float) -> void:
	if m.state == "gone" or not is_instance_valid(m.root):
		return
	var root: Node3D = m.root
	var speed := GALLOP * (1.25 if m.state == "bolt" else 1.0)
	var to: Vector3 = m.to
	var flat := Vector3(to.x - root.position.x, 0, to.z - root.position.z)
	if flat.length() < 0.4:
		match m.state:
			"charge":
				m["state"] = "wheel"
				m["to"] = Vector3(clampf(root.position.x + randf_range(-3, 3), -8, 8), 0, BACK_Z + randf_range(-1.5, 1.5))
			"wheel":
				m["state"] = "charge"
				m["to"] = Vector3(clampf(root.position.x + randf_range(-3, 3), -7, 7), 0, NEAR_Z - randf() * 1.5)
			"bolt":   # over the crest and out of sight, never on past the edge of the scene
				m["state"] = "gone"
				TableFx.burst(self, root.position + Vector3(0, 0.6, 0), [Color("e8cf9a"), Color("d2b077")], 0.7, 30)
				var tw := create_tween()
				tw.tween_property(root, "scale", Vector3.ONE * 0.01, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
				tw.tween_callback(root.queue_free)
				return
		return
	var dir := flat.normalized()
	# turn smoothly towards where he is going
	var want := atan2(dir.x, dir.z)
	root.rotation.y = lerp_angle(root.rotation.y, want, clampf(dt * 3.0, 0, 1))
	var fwd := Vector3(sin(root.rotation.y), 0, cos(root.rotation.y))
	var p := root.position + fwd * speed * dt
	var bob := absf(sin(_t * (6.0 if m.camel else 9.0) + m.phase)) * (0.12 if m.camel else 0.08)
	root.position = Vector3(p.x, _ground(p) + bob, p.z)
	_legs(m, 1.0, dt)
	if m.state in ["charge", "wheel"]:
		m["fire_in"] -= dt
		if m.fire_in <= 0.0:
			m["fire_in"] = randf_range(1.8, 3.2)
			_raider_fires(m)


## The legs at a gallop (k = 1) or standing (k = 0): a camel paces (both legs of a side
## together), a horse gallops (front pair, then hind pair).
func _legs(m: Dictionary, k: float, _dt: float) -> void:
	var legs: Array = m.legs
	var w := 6.0 if m.camel else 9.0
	for i in legs.size():
		var l: Node3D = legs[i]
		var off: float
		if m.camel:
			off = 0.0 if i % 2 == 0 else PI       # FL, BL together; FR, BR together
		else:
			off = 0.0 if i < 2 else PI * 0.6
			off += 0.25 if i % 2 == 1 else 0.0
		l.rotation.x = k * 0.55 * sin(_t * w + float(m.get("phase", 0.0)) + off)


func _raider_fires(m: Dictionary) -> void:
	var gun: Node3D = m.gun
	if gun == null or _defenders.is_empty():
		return
	var target: Dictionary = _defenders[randi() % _defenders.size()]
	var aim := (target.root as Node3D).position + Vector3(randf_range(-2.2, 2.2), 0, randf_range(1.0, 2.5))
	aim.y = _ground(aim)   # wide: into the sand round them
	m["aim"] = aim
	_volley(gun, aim, 2, true)


## The player points at a raider: the old man and the man nearest fire on him.
func _fire_on(m: Dictionary) -> void:
	if m.state not in ["charge", "wheel"]:
		return
	m["state"] = "hit"
	var mark: Vector3 = (m.root as Node3D).position + Vector3(0, 2.2, 0)
	var shooters := _defenders.duplicate()
	shooters.sort_custom(func(a, b): return (a.root as Node3D).position.distance_to(mark) < (b.root as Node3D).position.distance_to(mark))
	var who := [_defenders[0]]
	for s in shooters:
		if s != _defenders[0]:
			who.append(s)
			break
	for s in who:
		s["aim"] = mark
		_volley(s.gun, mark, 3, false)
	get_tree().create_timer(0.35).timeout.connect(func(): _unhorse(m))


## Shot from the saddle: he falls back off his mount onto the sand and lies still, then is
## gone in a puff of sand; the mount bolts back over the dunes the way it came.
func _unhorse(m: Dictionary) -> void:
	var root: Node3D = m.root
	var r: Node3D = m.rider
	_down += 1
	if is_instance_valid(root):
		m["state"] = "bolt"
		m["to"] = Vector3(clampf(root.position.x, -7.0, 7.0), 0, RIM_Z + 0.4)
	if r and is_instance_valid(r):
		var xf := r.global_transform
		r.get_parent().remove_child(r)
		add_child(r)
		r.global_transform = xf
		if m.gun:
			(m.gun as Node3D).visible = false
		var back := Vector3(sin(r.rotation.y), 0, cos(r.rotation.y)) * -1.4
		var land := _ground(r.position + back)
		TableKit.sfx(self, "soft_reject", r.position, -6.0)
		var ap := _anim(r)
		if ap:
			ap.pause()   # limp: the ride is over
		var tw := create_tween()
		tw.tween_property(r, "position", Vector3(r.position.x + back.x, land, r.position.z + back.z), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(r, "rotation:x", -1.3, 0.55)
		tw.tween_callback(func():
			TableFx.burst(self, r.position + Vector3(0, 0.2, 0), [Color("e8cf9a"), Color("d2b077")], 0.6, 30)
			TableKit.sfx(self, "brick_drop", r.position, -8.0))
		tw.tween_interval(1.8)
		tw.tween_callback(func():
			TableFx.burst(self, r.position + Vector3(0, 0.3, 0), [Color("e8cf9a"), Color("d2b077")], 0.8, 40)
			r.queue_free())
	if _down >= RAIDERS.size():
		_win()


func _win() -> void:
	if _won:
		return
	_won = true
	_hint_ring.visible = false
	TableKit.sfx(self, "success", OLD_MAN, -2.0)
	var tw := create_tween()
	tw.tween_interval(1.2)
	for b in 4:   # rifles to the sky for joy
		tw.tween_callback(func():
			for s in _defenders:
				s["aim"] = (s.root as Node3D).position + Vector3(randf_range(-1, 1), 30.0, randf_range(-1, 1))
				_volley(s.gun, s.aim, 3, false))
		tw.tween_interval(0.9)
	tw.tween_interval(1.5)
	tw.tween_callback(func():
		TableKit.sfx(self, "level_complete", OLD_MAN)
		level_won.emit())


# --- shots -----------------------------------------------------------------------------------------

## A few rounds from the gun towards the mark, a tracer each (wide shots end in a puff of sand).
func _volley(gun: Node3D, mark: Vector3, rounds: int, wide: bool) -> void:
	if gun == null:
		return
	var tw := create_tween()
	for r in rounds:
		tw.tween_callback(func():
			if not is_instance_valid(gun) or not gun.visible:
				return
			var muzzle := to_local(gun.global_transform * Vector3(0, 0.6, 0))
			var to := mark + Vector3(randf_range(-0.25, 0.25), randf_range(-0.2, 0.2), randf_range(-0.25, 0.25))
			_tracer(muzzle, to, wide)
			TableKit.sfx(self, "shot", muzzle, -10.0 if wide else -7.0, randf_range(0.92, 1.08)))
		tw.tween_interval(0.12)


func _tracer(from: Vector3, to: Vector3, puff: bool) -> void:
	var flash := TableKit.sphere(self, 0.12, TableKit.lit_mat(Color("ffe08a"), 4.0), from, 6)
	get_tree().create_timer(0.05).timeout.connect(flash.queue_free)
	var dir := (to - from).normalized()
	var t := TableKit.cyl(self, 0.03, 0.03, 0.8, TableKit.lit_mat(TRACER, 4.0), from, 6)
	t.basis = Basis(Quaternion(Vector3.UP, dir))
	var secs := clampf(from.distance_to(to) / 40.0, 0.12, 0.6)
	var tw := create_tween()
	tw.tween_property(t, "position", to, secs)
	tw.tween_callback(func():
		t.queue_free()
		if puff:
			TableFx.burst(self, to + Vector3(0, 0.1, 0), [Color("e8cf9a"), Color("d2b077")], 0.4, 14))


## Every rifle turned to its mark (or held up, ready, when it has none), the magazine down.
func _aim_guns() -> void:
	for m in _defenders + _raiders:
		var g = m.get("gun")
		var mn = m.get("rider")
		if g == null or not is_instance_valid(g) or mn == null or not is_instance_valid(mn) or not (g as Node3D).visible:
			continue
		var gun: Node3D = g
		var man: Node3D = mn
		var hold := gun.get_parent() as Node3D
		var mark: Vector3 = m.get("aim", Vector3.ZERO)
		var fwd := man.global_basis.z.normalized()
		var dir: Vector3
		if mark == Vector3.ZERO:
			dir = (fwd + Vector3.UP * 1.6).normalized()
		else:
			dir = (to_global(mark) - hold.global_position).normalized()
		var side := dir.cross(Vector3.UP)
		if side.length() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		var z := side.cross(dir).normalized()
		gun.global_transform = Transform3D(Basis(side, dir, z).scaled(hold.global_basis.get_scale()), hold.global_position)


# --- the pointer ------------------------------------------------------------------------------------

func aim(origin: Vector3, dir: Vector3) -> void:
	_ray = [origin, dir]


func pointer(held: bool, p) -> void:
	var pressed := held and not _was_held
	_was_held = held
	if not pressed or _won:
		return
	_idle_t = 0.0
	var id := TableKit.ray_pick(self, _ray, hover_boxes())
	if id != "":
		for m in _raiders:
			if str(m.id) == id:
				_fire_on(m)
				return
	# nothing under it: the old man fires a shot where the player points, into the sand
	if p != null and not _defenders.is_empty() and _defenders[0].gun:
		var q: Vector3 = p
		_defenders[0]["aim"] = q
		_volley(_defenders[0].gun, q, 1, true)


## The raiders still in the saddle (moving targets: a generous box round each).
func hover_boxes() -> Dictionary:
	var out := {}
	for m in _raiders:
		if m.state in ["charge", "wheel"] and is_instance_valid(m.root):
			var at: Vector3 = (m.root as Node3D).position
			out[str(m.id)] = AABB(at - Vector3(1.0, 0, 1.0), Vector3(2.0, 3.6, 2.0))
	return out


func _nearest_raider() -> Dictionary:
	var best := {}
	var bz := -INF
	for m in _raiders:
		if m.state in ["charge", "wheel"] and is_instance_valid(m.root) and (m.root as Node3D).position.z > bz:
			bz = (m.root as Node3D).position.z
			best = m
	return best


func _on_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, _ground(p), p.z)


## The height of the sand under a point (the lowest of a few samples round it, so a shrub or a
## rock is never taken for the ground).
func _ground(p: Vector3) -> float:
	if diorama == null:
		return 0.0
	var y := INF
	for o in [Vector2.ZERO, Vector2(0.6, 0), Vector2(-0.6, 0), Vector2(0, 0.6), Vector2(0, -0.6)]:
		y = minf(y, diorama.top_at(p.x + o.x, p.z + o.y))
	return clampf(y, 0.0, 6.0)


func demo() -> void:
	_demo = true
