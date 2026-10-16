class_name TableStepsLevel
extends Node3D
## Level 2 on the table, «درج من طين» (steps of mud). Wordless.
## Scene 2: a lane between a tall house and its low annex. The cat has climbed onto the annex
## roof and can't get down. Three mud blocks, tall, middle and short, lie in the lane. The
## player walks the old man (right stick, or tap the ground) and he pushes the blocks the way
## the crates were pushed in the earlier game: walk into a block's side and it slides one tile
## that way; tap a block he is standing against and he pulls it one tile back towards himself.
## Stood against the annex wall as a stair, tallest under the cat, the cat steps down them to
## him and he dances. Three blocks against the wall in the wrong order shake, and he shakes
## his head.
##
## Lives under Diorama.stage: positions are in the diorama's own metres (Godot axes).

signal level_won

const SFX := "res://audio/sfx/"
const MUD := "res://assets/world/kit/wall_kit_mud_tile.jpg"
const ROOF_Y := 2.8                          # annex roof top (tools/blender/build_scene2.py: ANNEX_H)
const PERCH := Vector3(2.9, ROOF_Y, -1.75)   # the cat, at the roof's front edge, near its right end
# the blocks move on a grid of TILE squares; cell (0, 0) is against the annex wall
const TILE := 0.7
const ORIGIN := Vector3(1.5, 0, -0.88)
const STAIR := [Vector2i(2, 0), Vector2i(1, 0), Vector2i(0, 0)]   # tallest (under the cat) .. shortest
const BLOCK_W := 0.66
# the blocks: height and starting cell (not in stair order)
const BLOCKS := [[1.4, Vector2i(3, 3)], [0.7, Vector2i(-4, 4)], [2.1, Vector2i(-1, 5)]]
const OLD_MAN := Vector3(-1.4, 0, 5.4)
const SPEED := 1.4             # the old man's pace (model metres per second)
const BODY_R := 0.25           # his size against walls
const BLOCK_REACH := 0.45      # how far in front of him his hands are, against blocks
const STAND := BLOCK_W / 2 + BLOCK_REACH + 0.04   # his centre from a block's centre while pushing
const PUSH_TIME := 0.9         # one tile
const PICK_R := 0.8            # ground-point fallback when the ray misses a block
const HINT_AFTER := 20.0
# where he can walk (x0, z0, w, d): the paved lane, less the house's front
const LANE := Rect2(-7.6, -1.25, 13.6, 8.25)
const HOUSE := Rect2(-7.6, -1.25, 7.4, 1.85)   # up to x -0.2, z 0.6

var diorama: Diorama
var cat: Node3D
var blocks: Array = []   # {node, h, cell: Vector2i}
var _was_held := false
var _ray := []           # last world ray from aim(): [origin, dir]
var _move := Vector2.ZERO  # stick, already turned into diorama x/z
var _goal = null         # tap-to-walk target (Vector3), or null
var _goal_block := {}
var _push := {}          # {block, from, dir, pull, t, man_from}
var _anim := ""
var _won := false
var _locked := false     # a wrong stair is being shown
var _idle_t := 0.0
var _t := 0.0
var _hint: MeshInstance3D
var _marks: Array = []   # faint squares on the ground where the stair goes
var _demo: Array = []    # pushes still to make in demo(): [block, dir]


func setup(d: Diorama) -> void:
	diorama = d
	cat = CreatureSlot.spawn(self, "cat")
	cat.scale = Vector3.ONE * Diorama.LIFE_SCALE.cat
	cat.position = PERCH
	CreatureSlot.play(cat, "sit")
	if diorama.shaib:
		diorama.shaib.position = OLD_MAN
		_face(diorama.shaib, PERCH - OLD_MAN)
		_play("idle")
	var mud := StandardMaterial3D.new()
	mud.albedo_texture = load(MUD) if ResourceLoader.exists(MUD) else null
	mud.albedo_color = Color("d9a777") if mud.albedo_texture else Color("b98a5c")  # a shade darker than the walls, so they read as loose
	mud.uv1_triplanar = true
	mud.uv1_scale = Vector3.ONE * 0.6
	mud.roughness = 1.0
	for b in BLOCKS:
		var h: float = b[0]
		var bm := BoxMesh.new()
		bm.size = Vector3(BLOCK_W, h, BLOCK_W)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = mud
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var n := Node3D.new()   # origin on the ground, at the block's foot
		add_child(n)
		n.add_child(mi)
		mi.position.y = h / 2
		n.position = cell_pos(b[1])
		blocks.append({"node": n, "h": h, "cell": b[1]})
	for c in STAIR:
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(BLOCK_W, BLOCK_W) * 1.05
		q.mesh = pm
		q.material_override = _glow_mat(Color("fff0d0"), 0.22)
		add_child(q)
		q.position = cell_pos(c) + Vector3(0, 0.03, 0)
		_marks.append(q)
	_hint = _ring(0.75, Color("e6b85a"))
	_hint.visible = false


static func cell_pos(c: Vector2i) -> Vector3:
	return ORIGIN + Vector3(c.x * TILE, 0, c.y * TILE)


## A block may stand in a cell on the lane, clear of the house front.
static func cell_ok(c: Vector2i) -> bool:
	var p := cell_pos(c)
	var half := BLOCK_W / 2
	var r := Rect2(p.x - half, p.z - half, BLOCK_W, BLOCK_W)
	return LANE.encloses(r) and not HOUSE.intersects(r)


func _block_at(c: Vector2i) -> Dictionary:
	for b in blocks:
		if b.cell == c:
			return b
	return {}


# --- input -----------------------------------------------------------------------------------

## World-space ray of the pointing hand (or mouse), every frame before pointer().
func aim(origin: Vector3, dir: Vector3) -> void:
	_ray = [origin, dir]


## The movement stick, every frame, as a direction on the diorama ground (x, z), length 0..1.
func move(v: Vector2) -> void:
	_move = v


## held = trigger down; p = point on the diorama ground (model metres) or null.
## Tap a block: pull it if he stands against it, else walk round to it. Tap the ground: walk.
func pointer(held: bool, p) -> void:
	var pressed := held and not _was_held
	_was_held = held
	if not pressed or _won or _locked or not _push.is_empty():
		return
	_idle_t = 0.0
	var b := _pick(p)
	var man := _man()
	if not b.is_empty():
		var side := _side_against(b)
		if side != Vector2i.ZERO:
			_start_push(b, side, true)
			return
		# walk to the nearest free side, facing the block
		var best = null
		var best_d := INF
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var at: Vector3 = b.node.position + Vector3(d.x, 0, d.y) * STAND
			if not _walkable(at, b):
				continue
			var dd := man.distance_to(at)
			if dd < best_d:
				best_d = dd
				best = at
		if best != null:
			_goal = best
			_goal_block = b
			_sfx("tap", b.node.position, -8.0)
		else:
			_sfx("soft_reject", b.node.position, -8.0)
		return
	if p != null and _walkable(p):
		_goal = p
		_goal_block = {}
		_sfx("tap", p, -10.0)


## The side (grid direction from the block to him) he is standing against, or ZERO.
func _side_against(b: Dictionary) -> Vector2i:
	var rel: Vector3 = _man() - b.node.position
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var ax := Vector3(d.x, 0, d.y)
		var along := rel.dot(ax)
		var across := (rel - ax * along).length()
		if absf(along - STAND) < 0.3 and across < 0.3:
			return d
	return Vector2i.ZERO


## The block under the ray (its box, a little enlarged), else the one nearest the ground point.
func _pick(p) -> Dictionary:
	if _ray.size() == 2:
		var o := to_local(_ray[0])
		var d := to_local(_ray[0] + _ray[1]) - o
		var best := {}
		var best_t := INF
		for b in blocks:
			var n: Node3D = b.node
			var box := AABB(n.position - Vector3(BLOCK_W / 2, 0, BLOCK_W / 2), Vector3(BLOCK_W, b.h, BLOCK_W)).grow(0.18)
			var hit = box.intersects_ray(o, d)
			if hit != null and o.distance_to(hit) < best_t:
				best_t = o.distance_to(hit)
				best = b
		if not best.is_empty():
			return best
	if p == null:
		return {}
	var q: Vector3 = p
	var best2 := {}
	var best_d := PICK_R
	for b in blocks:
		var dd := Vector2(b.node.position.x - q.x, b.node.position.z - q.z).length()
		if dd < best_d:
			best_d = dd
			best2 = b
	return best2


# --- the old man -----------------------------------------------------------------------------

func _man() -> Vector3:
	return diorama.shaib.position if diorama.shaib else OLD_MAN


## He may stand at p: on the lane, off the house front, not inside a block (except `ignore`).
func _walkable(p: Vector3, ignore := {}) -> bool:
	var q := Vector2(p.x, p.z)
	if not LANE.grow(-BODY_R).has_point(q) or HOUSE.grow(BODY_R).has_point(q):
		return false
	var keep := BLOCK_W / 2 + BLOCK_REACH - 0.02
	for b in blocks:
		if b == ignore:
			continue
		var c: Vector3 = b.node.position
		if absf(p.x - c.x) < keep and absf(p.z - c.z) < keep:
			return false
	return true


func _step_man(dt: float) -> void:
	var sh := diorama.shaib
	if sh == null:
		return
	var dir := Vector3.ZERO
	var strength := 0.0
	if _move.length() > 0.05:
		_goal = null   # the stick takes over from a tap
		_goal_block = {}
		dir = Vector3(_move.x, 0, _move.y).normalized()
		strength = minf(_move.length(), 1.0)
	elif _goal != null:
		var to: Vector3 = _goal - sh.position
		to.y = 0.0
		if to.length() < 0.05:
			_arrive()
			return
		dir = to.normalized()
		strength = minf(1.0, to.length() / 0.15)
	if strength <= 0.0:
		_play("idle")
		return
	_idle_t = 0.0
	# walking into a block's face: push it one tile along that axis
	var axis := Vector2i(int(signf(dir.x)), 0) if absf(dir.x) > absf(dir.z) else Vector2i(0, int(signf(dir.z)))
	var ax := Vector3(axis.x, 0, axis.y)
	if _goal == null and dir.dot(ax) > 0.8:
		for b in blocks:
			var rel: Vector3 = b.node.position - sh.position
			var along := rel.dot(ax)
			var across := (rel - ax * along).length()
			if along > BLOCK_W / 2 + BLOCK_REACH - 0.15 and along < STAND + 0.2 and across < 0.32:
				_start_push(b, axis, false)
				return
	var step := dir * SPEED * strength * dt
	if _walkable(sh.position + step):
		sh.position += step
	else:
		# slide along whatever is in the way
		var moved := false
		for s in [Vector3(step.x, 0, 0), Vector3(0, 0, step.z)]:
			if s.length() > 0.0001 and _walkable(sh.position + s):
				sh.position += s
				moved = true
				break
		if not moved and _goal != null:
			_arrive()   # can't get there in a straight line
			return
	sh.rotation.y = lerp_angle(sh.rotation.y, atan2(dir.x, dir.z), clampf(dt * 12.0, 0.0, 1.0))
	_play("walk")


func _arrive() -> void:
	_goal = null
	var b := _goal_block
	_goal_block = {}
	if not b.is_empty():
		_face(diorama.shaib, b.node.position - _man())
	_play("idle")


## Moves block b one tile along dir: pushed (he walks behind it) or pulled (dir points at him;
## he steps back). False, with a soft "no", when the way is blocked.
func _start_push(b: Dictionary, dir: Vector2i, pull: bool) -> bool:
	var to: Vector2i = b.cell + dir
	var d3 := Vector3(dir.x, 0, dir.y)
	var blocked := not cell_ok(to) or not _block_at(to).is_empty()
	var stand: Vector3 = b.node.position + (d3 * STAND if pull else -d3 * STAND)
	if pull:
		blocked = blocked or not _walkable(stand + d3 * TILE, b)
	if blocked:
		if _t - float(b.get("rejected", -9.0)) > 0.6:
			b.rejected = _t
			_sfx("soft_reject", b.node.position, -6.0)
		return false
	diorama.shaib.position = stand
	_face(diorama.shaib, b.node.position - stand)
	_play("push")
	_sfx("crate_scrape", b.node.position, -4.0)
	_push = {"block": b, "from": b.node.position, "dir": dir, "t": 0.0, "man_from": stand}
	_goal = null
	return true


func _step_push(dt: float) -> void:
	_push.t += dt / PUSH_TIME
	var k := smoothstep(0.0, 1.0, minf(_push.t, 1.0))
	var off := Vector3(_push.dir.x, 0, _push.dir.y) * TILE * k
	var b: Dictionary = _push.block
	b.node.position = _push.from + off
	diorama.shaib.position = _push.man_from + off
	if _push.t < 1.0:
		return
	b.cell += _push.dir
	b.node.position = cell_pos(b.cell)
	_push = {}
	_sfx("brick_place", b.node.position, -6.0)
	_play("idle")
	_check()


# --- the stair -------------------------------------------------------------------------------

## A stair (tallest under the cat) lets the cat down. Three blocks against the wall in the
## wrong order shake, and he shakes his head.
func _check() -> void:
	var placed: Array = []
	for c in STAIR:
		placed.append(_block_at(c))
	if placed.any(func(x): return x.is_empty()):
		return
	if placed[0].h > placed[1].h and placed[1].h > placed[2].h:
		_win()
		return
	_locked = true
	_sfx("soft_reject", cell_pos(STAIR[1]))
	for s in placed:
		var n: Node3D = s.node
		var x0: float = n.position.x
		var tw := create_tween()
		for k in 4:
			tw.tween_property(n, "position:x", x0 + (0.08 if k % 2 == 0 else -0.08), 0.06)
		tw.tween_property(n, "position:x", x0, 0.06)
	if diorama.shaib:
		_face(diorama.shaib, PERCH - _man())
	_anim = "reject"
	diorama.play_shaib("reject", "idle")
	get_tree().create_timer(1.0).timeout.connect(func():
		_locked = false
		_anim = "idle")


func _win() -> void:
	_won = true
	_hint.visible = false
	_sfx("success", PERCH, -2.0)
	for m in _marks:
		m.visible = false
	var man := _man()
	_face(diorama.shaib, PERCH - man)
	_play("idle")
	# the cat comes down: roof edge, each block top, the ground in front of the stair, then to him
	var foot := cell_pos(STAIR[2]) + Vector3(0, 0, TILE)
	var steps: Array = [PERCH + Vector3(0, 0, 0.35)]
	for c in STAIR:
		steps.append(cell_pos(c) + Vector3(0, _block_at(c).h, 0))
	steps.append(foot)
	var goal := man + (foot - man).normalized() * minf(0.55, man.distance_to(foot))
	var tw := create_tween()
	tw.tween_interval(0.3)
	var at: Vector3 = cat.position
	for s in steps:
		var a := at
		var b: Vector3 = s
		tw.tween_callback(func():
			_face(cat, b - a)
			CreatureSlot.play(cat, "walk"))
		tw.tween_method(func(k: float):
			cat.position = a.lerp(b, k) + Vector3(0, sin(k * PI) * 0.35, 0), 0.0, 1.0, 0.38)
		tw.tween_callback(func(): _sfx("tap", b, -10.0))
		tw.tween_interval(0.12)
		at = b
	tw.tween_callback(func():
		_face(cat, goal - cat.position)
		_face(diorama.shaib, goal - man))
	tw.tween_property(cat, "position", goal, maxf(0.2, at.distance_to(goal) / 1.8))
	tw.tween_callback(func():
		_face(cat, man - goal)
		CreatureSlot.play(cat, "sit")
		_anim = "ardah"
		diorama.play_shaib("ardah", "")
		diorama.scare_birds(goal, 5.0))
	tw.tween_interval(4.0)
	tw.tween_callback(func():
		_sfx("level_complete", goal)
		level_won.emit())


## Screenshot/test helper: pushes the blocks into the stair, one tile at a time.
func demo() -> void:
	_demo.clear()
	var order := blocks.duplicate()
	order.sort_custom(func(a, b): return a.h > b.h)
	var cells := {}
	for b in blocks:
		cells[b] = b.cell
	for i in 3:
		var b: Dictionary = order[i]
		var from: Vector2i = cells[b]
		var to: Vector2i = STAIR[i]
		for k in absi(to.x - from.x):
			_demo.append([b, Vector2i(signi(to.x - from.x), 0)])
		for k in absi(to.y - from.y):
			_demo.append([b, Vector2i(0, signi(to.y - from.y))])


func _process(dt: float) -> void:
	_t += dt
	if _won:
		return
	if not _push.is_empty():
		_step_push(dt)
	elif not _demo.is_empty() and not _locked:
		var job: Array = _demo.pop_front()
		_start_push(job[0], job[1], false)
	elif not _locked:
		_step_man(dt)
	_idle_t += dt
	# a wordless nudge: after a while, the block that belongs next glows at its foot
	var want := _next_block() if _idle_t > HINT_AFTER else {}
	_hint.visible = not want.is_empty()
	if _hint.visible:
		var pulse := 1.0 + 0.12 * sin(_t * 4.0)
		_hint.position = (want.node as Node3D).position + Vector3(0, 0.05, 0)
		_hint.scale = Vector3(pulse, 0.2, pulse)
	for i in _marks.size():
		_marks[i].visible = _block_at(STAIR[i]).is_empty()


## The block that belongs in the first stair place not yet right (or the wrong one in it).
func _next_block() -> Dictionary:
	var sorted := blocks.duplicate()
	sorted.sort_custom(func(a, b): return a.h > b.h)
	for i in 3:
		var there := _block_at(STAIR[i])
		if there != sorted[i]:
			return there if not there.is_empty() else sorted[i]
	return {}


func _play(clip: String) -> void:
	if _anim == clip:
		return
	_anim = clip
	diorama.play_shaib(clip, "")


static func _face(n: Node3D, d: Vector3) -> void:
	if n and Vector2(d.x, d.z).length() > 0.001:
		n.rotation.y = atan2(d.x, d.z)


static func _glow_mat(c: Color, alpha := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _ring(r: float, c: Color) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r * 0.84
	t.outer_radius = r
	t.rings = 32
	t.ring_segments = 4
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.material_override = _glow_mat(c, 0.9)
	add_child(mi)
	return mi


func _sfx(name: String, at: Vector3, db := 0.0) -> void:
	TableKit.sfx(self, name, at, db)
