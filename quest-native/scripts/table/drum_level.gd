class_name TableDrumLevel
extends Node3D
## Level 6 on the table, «إيقاع العرضة» (the ardah's beat). Wordless.
## Scene 6: the palace square. Four drums stand in front of the palace, each with its own
## colour and voice; behind them the old man, and behind him the men waiting for the ardah.
## He beats a phrase on the drums; the player beats it back, drum for drum. Every phrase
## played back right raises a flag on one of the four poles turn the square, and the next
## phrase is a beat longer. A wrong drum: the beat breaks and he plays the phrase again. Tap
## the old man to hear it again. With all four flags up the men dance the ardah.
## Each round the beat quickens a little, and while it is the player's turn the men keep
## the time with a soft stamp.
##
## Lives under Diorama.stage: positions are in the diorama's own metres (Godot axes).

signal level_won

const DRUMS := [  # x, radius, height, body colour, voice
	[-2.7, 0.55, 0.55, Color("b5452f"), 1],
	[-0.9, 0.46, 0.5, Color("d9a63a"), 2],
	[0.9, 0.4, 0.45, Color("3f7f8a"), 3],
	[2.7, 0.34, 0.4, Color("7a4a2e"), 4],
]
const DRUM_Z := 1.4
const OLD_MAN := Vector3(0.0, 0.0, -0.2)
const MEN := [Vector3(-4.2, 0, -3.4), Vector3(-2.1, 0, -3.6), Vector3(2.1, 0, -3.6), Vector3(4.2, 0, -3.4)]
const MEN_DRESS := [{"bisht": "bisht", "head": "ghutra"}, {"thobe": "thobe_grey"}, {"thobe": "thobe_beige"}, {"thobe": "thobe_beige", "head": "ghutra"}]
const POLES := [Vector3(-5.6, 0, -4.4), Vector3(5.2, 0, -4.4), Vector3(-7.0, 0, 4.0), Vector3(7.0, 0, 4.0)]  # clear of the tower
const POLE_H := 4.2
const ROUNDS := [3, 4, 5, 6]
const BEAT := 0.62
const QUICKEN := 0.88         # each round's beat is this much of the last one's
const HINT_AFTER := 15.0

var diorama: Diorama
var phrases: Array = []      # one phrase (drum indices) per turn
var turn := 0                # which phrase (round) is being played
var _heard: Array = []       # what the player has beaten so far this turn
var _drums: Array = []       # {node, skin, glow}
var _flags: Array = []
var _men: Array = []         # {node, anim}
var _boxes := {}
var _listening := false      # the player's turn
var _won := false
var _was_held := false
var _ray := []
var _idle_t := 0.0
var _t := 0.0
var _demo := false
var _started := false
var _stamp := 0.0


func setup(d: Diorama) -> void:
	diorama = d
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	for n in ROUNDS:
		var p: Array = []
		for i in n:
			var k := rng.randi_range(0, 3)
			while not p.is_empty() and k == p[-1]:
				k = rng.randi_range(0, 3)   # no drum twice in a row: easier to follow
			p.append(k)
		phrases.append(p)
	if diorama.shaib:
		diorama.shaib.position = OLD_MAN
		diorama.shaib.rotation.y = 0.0
		diorama.play_shaib("idle", "")
	for i in DRUMS.size():
		_drum(i)
	for i in POLES.size():
		_pole(i)
	for i in MEN.size():
		var m := TableKit.model(self, Diorama.SHAIB, MEN[i], 0.0, Diorama.LIFE_SCALE.shaib)
		if m == null:
			continue
		Wardrobe.apply(m, MEN_DRESS[i])
		var aps := m.find_children("*", "AnimationPlayer", true, false)
		var ap: AnimationPlayer = aps[0] if not aps.is_empty() else null
		if ap:
			for a in ["idle", "ardah"]:
				if ap.has_animation(a):
					ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
			if ap.has_animation("idle"):
				ap.play("idle")
				ap.seek(randf() * 2.0)
		_men.append({"node": m, "anim": ap})
	_boxes["man"] = AABB(OLD_MAN - Vector3(0.5, 0, 0.5), Vector3(1.0, 2.0, 1.0))


func drum_pos(i: int) -> Vector3:
	return Vector3(DRUMS[i][0], 0, DRUM_Z)


func _drum(i: int) -> void:
	var d: Array = DRUMS[i]
	var n := Node3D.new()
	add_child(n)
	n.position = drum_pos(i)
	var r: float = d[1]
	var h: float = d[2]
	TableKit.cyl(n, r, r * 0.92, h, TableKit.mat(d[3]), Vector3(0, h / 2, 0), 18)
	var skin := TableKit.cyl(n, r * 1.02, r * 1.02, 0.04, TableKit.mat(Color("efe2c4")), Vector3(0, h + 0.02, 0), 18)
	for y in [0.12, h - 0.1]:   # rope rings
		TableKit.cyl(n, r * 1.03, r * 1.03, 0.04, TableKit.mat(Color("e9dcc0")), Vector3(0, y, 0), 18)
	var glow := TableKit.ring(n, r * 1.6, d[3].lightened(0.35), 0.9, 0.12)
	glow.position.y = 0.04
	glow.visible = false
	_drums.append({"node": n, "skin": skin, "glow": glow})
	_boxes[str(i)] = AABB(n.position - Vector3(r + 0.15, 0, r + 0.15), Vector3(2 * r + 0.3, h + 0.5, 2 * r + 0.3))


func _pole(i: int) -> void:
	var at: Vector3 = POLES[i]
	TableKit.cyl(self, 0.05, 0.07, POLE_H, TableKit.mat(Color("6e4a2c")), at + Vector3(0, POLE_H / 2, 0), 8)
	TableKit.sphere(self, 0.1, TableKit.mat(Color("d9b25a"), 0.4), at + Vector3(0, POLE_H + 0.05, 0), 8)
	var flag := Node3D.new()
	add_child(flag)
	flag.position = at + Vector3(0, 0.5, 0)
	TableKit.box(flag, Vector3(1.2, 0.75, 0.03), TableKit.mat(Color("1f6e43")), Vector3(0.62, 0, 0))
	TableKit.box(flag, Vector3(0.8, 0.07, 0.035), TableKit.mat(Color("f2efe6")), Vector3(0.62, -0.18, 0))  # the sword
	flag.scale = Vector3(1, 0.05, 1)   # furled at the foot of the pole
	_flags.append(flag)


# --- the beat ----------------------------------------------------------------------------------

func _beat(i: int, loud := true) -> void:
	var d: Dictionary = _drums[i]
	var skin: Node3D = d.skin
	var tw := create_tween()
	tw.tween_property(skin, "scale", Vector3(1.08, 0.4, 1.08), 0.06)
	tw.tween_property(skin, "scale", Vector3.ONE, 0.16)
	var glow: MeshInstance3D = d.glow
	glow.visible = true
	glow.scale = Vector3.ONE * 0.8
	var tg := create_tween()
	tg.tween_property(glow, "scale", Vector3.ONE * 1.2, 0.3)
	tg.tween_callback(func(): glow.visible = false)
	TableKit.sfx(self, "seq_%d" % DRUMS[i][4], drum_pos(i) + Vector3(0, 0.6, 0), 0.0 if loud else -4.0)


## The old man beats this turn's phrase; then it is the player's turn.
func _play_phrase() -> void:
	if _won:
		return
	_listening = false
	_heard.clear()
	var p: Array = phrases[turn]
	var tw := create_tween()
	for k in p:
		var i: int = k
		tw.tween_callback(func():
			if diorama.shaib:
				TableKit.face(diorama.shaib, drum_pos(i) - OLD_MAN)
				diorama.play_shaib("interact", "idle")
			_beat(i))
		tw.tween_interval(beat())
	tw.tween_callback(func():
		if diorama.shaib:
			diorama.shaib.rotation.y = 0.0
		_listening = true
		_idle_t = 0.0
		if _demo:
			_demo_round())


## This round's beat (seconds between strokes): quicker every round.
func beat() -> float:
	return BEAT * pow(QUICKEN, turn)


func aim(origin: Vector3, dir: Vector3) -> void:
	_ray = [origin, dir]


func pointer(held: bool, p) -> void:
	var pressed := held and not _was_held
	_was_held = held
	if not pressed or _won:
		return
	var id := TableKit.ray_pick(self, _ray, _boxes)
	if id == "" and p != null:
		var q: Vector3 = p
		for i in DRUMS.size():
			if Vector2(drum_pos(i).x - q.x, drum_pos(i).z - q.z).length() < 0.8:
				id = str(i)
	if id == "man":
		if _listening:
			_play_phrase()
		return
	if id == "" or not _listening:
		return
	_hit(int(id))


func _hit(i: int) -> void:
	_idle_t = 0.0
	_beat(i)
	_heard.append(i)
	var p: Array = phrases[turn]
	var k := _heard.size() - 1
	if p[k] != i:
		_listening = false
		TableKit.sfx(self, "soft_reject", drum_pos(i), -2.0)
		diorama.play_shaib("reject", "idle")
		get_tree().create_timer(1.4).timeout.connect(_play_phrase)
		return
	if _heard.size() < p.size():
		return
	_listening = false
	_raise(turn)
	turn += 1
	if turn >= ROUNDS.size():
		get_tree().create_timer(1.0).timeout.connect(_win)
	else:
		get_tree().create_timer(1.8).timeout.connect(_play_phrase)


func _raise(i: int) -> void:
	var flag: Node3D = _flags[i]
	TableKit.sfx(self, "unlock", flag.position, -4.0)
	var tw := create_tween().set_parallel()
	tw.tween_property(flag, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK)
	tw.tween_property(flag, "position:y", POLE_H - 0.5, 1.4).set_trans(Tween.TRANS_SINE)


func _win() -> void:
	_won = true
	TableKit.sfx(self, "success", OLD_MAN, -2.0)
	diorama.play_shaib("ardah", "")
	diorama.scare_birds(OLD_MAN, 6.0)
	for m in _men:
		var ap: AnimationPlayer = m.anim
		if ap and ap.has_animation("ardah"):
			ap.play("ardah", 0.3)
			ap.seek(randf() * 0.4)
	# the drums keep the dance going
	var tw := create_tween().set_loops(6)
	for i in [0, 2, 1, 3]:
		var k: int = i
		tw.tween_callback(func(): _beat(k, false))
		tw.tween_interval(0.5)
	var end := create_tween()
	end.tween_interval(7.0)
	end.tween_callback(func():
		TableKit.sfx(self, "level_complete", OLD_MAN)
		level_won.emit())


func demo() -> void:
	_demo = true
	if _listening:
		_demo_round()


func _demo_round() -> void:
	var p: Array = phrases[turn]
	var tw := create_tween()
	tw.tween_interval(0.4)
	for k in p:
		var i: int = k
		tw.tween_callback(func(): _hit(i))
		tw.tween_interval(0.35)


func _process(dt: float) -> void:
	_t += dt
	if not _started and _t > 1.5:
		_started = true
		_play_phrase()
	if _won or not _listening:
		return
	# the men stamp the time softly while the player beats
	_stamp -= dt
	if _stamp <= 0.0:
		_stamp = beat()
		TableKit.sfx(self, "tap", Vector3(0, 0.2, -3.5), -16.0, 0.6)
	_idle_t += dt
	if _idle_t > HINT_AFTER and _heard.is_empty():
		_play_phrase()   # forgotten it? he plays it again
