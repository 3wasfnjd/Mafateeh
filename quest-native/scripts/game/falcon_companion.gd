class_name FalconCompanion
extends Node3D
## Shaheen «شاهين», the old man's falcon. From the Oasis chapter on he rides on the
## hero's shoulder (the "Perch" bone). When the player sends him (PuzzleState
## send_falcon) he flies to the plate and stays there, or fetches the key and comes
## back; recalling him or undoing brings him home. Pure presentation: it only reads
## the puzzle state.

const FROM_LEVEL := 15
const FLY_TIME := 1.1

var game: Game
var bird: Node3D
var _mode := "shoulder"  # shoulder | out | sitting | back
var _t := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _clock := 0.0


func setup(g: Game) -> void:
	game = g
	bird = FalconView.make(self)
	bird.scale = Vector3.ONE * 0.95


func active() -> bool:
	return game.state != null and (game.level >= FROM_LEVEL or game.state.def.has("falcon"))


func reset() -> void:
	_mode = "shoulder"
	visible = active()


func _shoulder() -> Transform3D:
	var h: HeroView = game.hero
	if h.skeleton:
		var i := h.skeleton.find_bone("Perch")
		if i >= 0:
			return h.skeleton.global_transform * h.skeleton.get_bone_global_pose(i)
	return h.global_transform.translated_local(Vector3(0.12, 0.9, 0))


func _target_pos() -> Vector3:
	var s: PuzzleState = game.state
	for o in s.objects:
		if o.type == "plate" and o.id == s.falcon_plate:
			return game.to_global(Vector3(o.x, LevelData.surface_y(s.def, o.x, o.z) + 0.12, o.z))
	# the key he fetched: the last key taken that the hero could not have reached
	for o in s.objects:
		if o.type == "key" and not s.is_visible(o):
			return game.to_global(Vector3(o.x, LevelData.surface_y(s.def, o.x, o.z) + 0.5, o.z))
	return _shoulder().origin


func _process(dt: float) -> void:
	if game == null or game.state == null:
		return
	visible = active() and game.hero.visible
	if not visible:
		return
	_clock += dt
	var s: PuzzleState = game.state
	var home := _shoulder()
	match _mode:
		"shoulder":
			global_transform = Transform3D(home.basis.orthonormalized(), home.origin)
			FalconView.flap(bird, _clock, 0.0)
			if s.falcon_used:
				_mode = "out"
				_t = 0.0
				_from = home.origin
				_to = _target_pos()
		"out", "back":
			_t += dt
			var k := clampf(_t / FLY_TIME, 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			var dest := _to if _mode == "out" else home.origin
			var p := _from.lerp(dest, e)
			p.y += sin(k * PI) * 0.6 * game.global_transform.basis.get_scale().y
			var fwd := dest - _from
			fwd.y = 0.0
			if fwd.length() > 0.001:
				global_transform = Transform3D(Basis.looking_at(-fwd.normalized(), Vector3.UP).scaled(Vector3.ONE * game.global_transform.basis.get_scale().x), p)
			else:
				global_position = p
			FalconView.flap(bird, _clock, 1.0)
			if k >= 1.0:
				if _mode == "back":
					_mode = "shoulder"
				elif s.falcon_plate >= 0:
					_mode = "sitting"
				else:
					_mode = "back"  # brought the key: fly home
					_t = 0.0
					_from = global_position
		"sitting":
			FalconView.flap(bird, _clock, 0.0)
			if s.falcon_plate < 0:  # recalled (or undone)
				_mode = "back"
				_t = 0.0
				_from = global_position
	if not s.falcon_used and _mode in ["out", "sitting"]:
		_mode = "back"
		_t = 0.0
		_from = global_position
