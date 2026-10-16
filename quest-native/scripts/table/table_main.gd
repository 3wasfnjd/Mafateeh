extends Node3D
## Mafateeh: the tabletop game in mixed reality (the owner's direction: AR only, a small
## diorama on the table, few words, light simple menus in beige / light brown).
##
## Start card: play, the wardrobe, and a row of level numbers to jump to any level. The wardrobe shows the old man himself, turning slowly,
## dressed in what he wears; tap an item to put it on or take it off.
## In play: a scene diorama sits on the table and its level runs on it. Level 1 (scene 1,
## TablePathLevel: draw the cat's way home); once won, level 2 follows on the same spot
## (scene 2, TableStepsLevel: push the mud blocks into a stair), then level 3 (scene 3,
## TableFalconLevel: fly the falcon perch to perch to fetch a key), then level 4 (scene 4,
## TableCampLevel: drive the parked cars aside to get the water truck out); then the card.
##   Trigger: draw (or press a card button). Hold grip and move the hand: carry the diorama.
##   Left stick x: turn it; y: resize it. Right stick: walk the old man (level 2). Tap grip: bring it back in front. Menu: the card.
## Desktop (no headset): click buttons, drag on the sand to draw, WASD walk, right-drag look,
##   Q/E turn the diorama, Esc the card.
## Screenshot args: --screenshot=path [--start=play|wardrobe] [--cam=x,y,z,yaw,pitch]
##   [--level=N] [--k=size] [--turn=deg] [--demo=1] (play: solve the level by itself) [--wait=frames]

const ICONS := "res://assets/ui/icons/"
# palette: light, warm, no green (owner's choice). The card itself is the owner's clay plaque
# (assets/ui/menu_plaque.png: crenellated top, an emblem pressed in the lower left corner).
const PLAQUE := "res://assets/ui/menu_plaque.png"
const PLAQUE_ASPECT := 1024.0 / 541.0
const ACCENT := Color("7a5a3a")      # brown buttons on the clay
const ACCENT_DARK := Color("4f3826") # worn-item ring
const DISC := Color("fbf3e4")

var env: Environment
var sun: DirectionalLight3D
var rig: XRRig
var xr := false
var desk_cam: Camera3D
var card: Node3D
var _buttons: Array = []  # {local, r, action}
var _args := {}
var diorama: Diorama
var level: Node3D           # Table{Path,Steps,Falcon,Camp}Level: setup(d), pointer(held, p), demo(), level_won
var stage := 1              # which level is on the table
var _round := 0             # bumped on every _play, so a stale "level won" timer does nothing
const LAST_LEVEL := 8
const RISE_TIME := 1.1      # a scene sinking into the ground, or rising out of it
var table_k := 1.0
var _drag := {}
var _yaw := 0.0
var _pitch := -0.12
var _mouse_draw := false
var _preview: Node3D        # the old man on the wardrobe card
var _preview_anim: AnimationPlayer
var _card_kind := ""        # "start" | "wardrobe"
var _mr_on := false         # passthrough switched on (only possible once the session runs)
var surfaces: SceneSurfaces # real tables from the headset's room setup (Meta Scene API)
var _moved_by_hand := false # once the player carries the diorama, detected tables no longer move it


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8f8a82")  # stand-in for the room on desktop
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff6ea")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 32, 0)
	sun.light_energy = 0.95
	sun.shadow_enabled = false  # no shadows (owner's choice; also cheaper on Quest)
	add_child(sun)
	rig = XRRig.new()
	rig.name = "XRRig"
	add_child(rig)
	rig.setup(env)
	xr = not _args.has("screenshot") and rig.start()
	if xr:
		# Passthrough can only be switched on once the session runs (before that the runtime
		# reports no alpha-blend mode and the rig would fall back to a black VR void), so
		# _process keeps trying until it takes.
		surfaces = SceneSurfaces.new()
		add_child(surfaces)
		surfaces.attach(rig)
		surfaces.surfaces_changed.connect(func():
			if diorama and not _moved_by_hand:
				_place_table())
	else:
		desk_cam = Camera3D.new()
		desk_cam.fov = 70
		rig.add_child(desk_cam)
		desk_cam.position = Vector3(0, 1.62, 0)
		desk_cam.current = true
	rig.menu_pressed.connect(func(): _show_card("start"))
	rig.trigger_pressed.connect(_on_trigger)
	rig.grip_tapped.connect(_on_grip_tap)
	if _args.has("cam"):
		var c := str(_args.cam).split_floats(",")
		rig.position = Vector3(c[0], 0, c[2])
		desk_cam.position.y = c[1]
		_yaw = deg_to_rad(c[3])
		_pitch = deg_to_rad(c[4])
		desk_cam.rotation = Vector3(_pitch, _yaw, 0)
	match str(_args.get("start", "")):
		"play": _play(int(_args.get("level", "1")))
		"wardrobe": _show_card("wardrobe")
		_: _show_card("start")
	if _args.has("screenshot"):
		_screenshot.call_deferred()


# --- cards ------------------------------------------------------------------------------

func _new_card(size: Vector2) -> void:
	if card:
		card.queue_free()
	_buttons.clear()
	_preview = null
	_preview_anim = null
	card = Node3D.new()
	add_child(card)
	_place_card(true)
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	bg.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = load(PLAQUE)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	bg.material_override = m
	card.add_child(bg)


func _show_card(kind: String) -> void:
	_card_kind = kind
	if kind == "wardrobe":
		_wardrobe_card()
		return
	_new_card(Vector2(0.6, 0.6 / PLAQUE_ASPECT))
	_icon_button("play", Vector3(-0.08, 0.05, 0.004), 0.05, _play)
	_icon_button("wardrobe", Vector3(0.08, 0.05, 0.004), 0.05, func(): _show_card("wardrobe"))
	# the levels in two rows of five, ١ at the top right (read right to left): tap one to go
	# straight to it; the one on the table has a dark ring
	for i in LAST_LEVEL:
		var n := i + 1
		var at := Vector3(0.14 - (i % 5) * 0.07, -0.04 - (i / 5) * 0.068, 0.004)
		if diorama and stage == n:
			_disc(at - Vector3(0, 0, 0.001), 0.031, ACCENT_DARK)
		_icon_button("level_%d" % n, at, 0.026, func(): _play(n), 1.9)


func _wardrobe_card() -> void:
	_new_card(Vector2(0.66, 0.66 / PLAQUE_ASPECT))
	# the old man on a small round stand, turning slowly
	var stand := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.075
	cm.bottom_radius = 0.08
	cm.height = 0.012
	stand.mesh = cm
	stand.material_override = _flat(Color("c79b6c"))
	stand.position = Vector3(-0.13, -0.112, 0.05)
	card.add_child(stand)
	var ps := load(Diorama.SHAIB) as PackedScene
	if ps:
		_preview = ps.instantiate()
		card.add_child(_preview)
		_preview.scale = Vector3.ONE * 0.16  # about 20 cm tall on the card
		_preview.position = Vector3(-0.13, -0.106, 0.05)
		var aps := _preview.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			_preview_anim = aps[0]
			if _preview_anim.has_animation("idle"):
				_preview_anim.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
				_preview_anim.play("idle")
		for mi in _preview.find_children("*", "GeometryInstance3D", true, false):
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Wardrobe.apply(_preview, Save.wearing)
	# the items, two rows, then back and play
	var ids := Wardrobe.ITEMS.map(func(it): return it.id)
	for i in ids.size():
		var col := i % 4
		var row := i / 4
		var at := Vector3(0.04 + col * 0.07, 0.065 - row * 0.08, 0.004)
		_item_button(ids[i], at, 0.03)
	_icon_button("back", Vector3(0.08, -0.105, 0.004), 0.03, func(): _show_card("start"))
	_icon_button("play", Vector3(0.21, -0.105, 0.004), 0.03, _play)


func _icon_button(icon: String, at: Vector3, r: float, action: Callable, icon_k := 1.15) -> void:
	_disc(at, r, ACCENT)
	_icon(ICONS + icon + ".png", at + Vector3(0, 0, 0.004), r * icon_k)
	_buttons.append({"local": at, "r": r, "action": action})


func _item_button(id: String, at: Vector3, r: float) -> void:
	var it := Wardrobe.item(id)
	var worn: bool = Save.wearing.get(it.slot, "") == id
	if worn:
		_disc(at - Vector3(0, 0, 0.001), r * 1.18, ACCENT_DARK)
	_disc(at, r, DISC)
	_icon(ICONS + "w_" + id + ".png", at + Vector3(0, 0, 0.004), r * 1.5)
	_buttons.append({"local": at, "r": r, "action": func(): _wear(id)})


func _wear(id: String) -> void:
	var it := Wardrobe.item(id)
	if it.is_empty():
		return
	# the wardrobe is open in this version: everything can be tried on
	if Save.wearing.get(it.slot, "") == id:
		Save.wearing.erase(it.slot)
	else:
		Save.wearing[it.slot] = id
	Save.save()
	if diorama:
		diorama.dress()
	var keep := card.global_transform
	_wardrobe_card()
	card.global_transform = keep
	if _preview_anim and _preview_anim.has_animation("excited"):
		_preview_anim.play("excited", 0.2)
		_preview_anim.queue("idle")


func _disc(at: Vector3, r: float, c: Color) -> void:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.004
	cm.radial_segments = 40
	disc.mesh = cm
	disc.rotation.x = PI / 2
	disc.material_override = _flat(c)
	disc.position = at
	card.add_child(disc)


func _icon(path: String, at: Vector3, size: float) -> void:
	var ic := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	ic.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = load(path)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	ic.material_override = m
	ic.position = at
	card.add_child(ic)


static func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _card_hit(origin: Vector3, dir: Vector3) -> Dictionary:
	if card == null:
		return {}
	var plane := Plane(card.global_basis.z, card.global_position)
	var p = plane.intersects_ray(origin, dir)
	if p == null:
		return {}
	for b in _buttons:
		if (p as Vector3).distance_to(card.to_global(b.local)) < b.r:
			return b
	return {}


func _place_card(instant: bool) -> void:
	var head := _head()
	var fwd := -head.basis.z
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var target := head.origin + fwd * 0.75 + Vector3(0, -0.06, 0)
	if head.origin.length() < 0.01:
		target = Vector3(0, 1.56, -0.75)
	card.global_position = target if instant else card.global_position.lerp(target, 0.05)
	var look := head.origin if head.origin.length() > 0.01 else Vector3(0, 1.62, 0)
	card.look_at(look, Vector3.UP, true)


func _on_trigger(_hand: String, origin: Vector3, dir: Vector3) -> void:
	var b := _card_hit(origin, dir)
	if not b.is_empty():
		b.action.call()


# --- play ---------------------------------------------------------------------------------

func _play(n := 1, rising := false) -> void:
	if card:
		card.queue_free()
		card = null
	_card_kind = ""
	var keep := Transform3D()
	var keep_spot := diorama != null and n > 1   # the next level goes where the last one was
	if diorama:
		keep = diorama.global_transform
		diorama.queue_free()
	stage = n
	_round += 1
	diorama = Diorama.new()
	diorama.pacing_cat = false     # the level's cat is the one being played
	diorama.birds_outside = false  # keep the ground the player works on clear
	add_child(diorama)
	diorama.setup(n)
	_apply_mood(str(diorama.layout.get("mood", "day")))
	match n:
		2: level = TableStepsLevel.new()
		3: level = TableFalconLevel.new()
		4: level = TableCampLevel.new()
		5: level = TableLanternLevel.new()
		6: level = TableDrumLevel.new()
		7: level = TableStarsLevel.new()
		8: level = TableBarterLevel.new()
		_: level = TablePathLevel.new()
	diorama.stage.add_child(level)
	level.setup(diorama)
	level.level_won.connect(_on_level_won)
	if keep_spot:
		diorama.global_transform = keep
	else:
		table_k = 1.0
		_place_table()
	if rising:  # the new scene grows up out of the ground
		diorama.set_rise(0.0)
		create_tween().tween_method(diorama.set_rise, 0.0, 1.0, RISE_TIME).set_delay(0.15)


func _on_level_won() -> void:
	var won := stage
	var r := _round
	get_tree().create_timer(4.0).timeout.connect(func():
		if r != _round or diorama == null:
			return  # the player already started again
		if won >= LAST_LEVEL:
			_show_card("start")
			return
		# the old scene sinks into the ground, which stays; the next one rises out of it
		var tw := create_tween()
		tw.tween_method(diorama.set_rise, 1.0, 0.0, RISE_TIME)
		tw.tween_callback(func():
			if r == _round:
				_play(won + 1, true)))


## Light for the level's time of day: "day", "evening" (low warm sun) or "night" (dim and
## blue, so lamps and fires carry the scene). Only the diorama is lit; the room is passthrough.
func _apply_mood(mood: String) -> void:
	var looks := {
		"day": [Vector3(-48, 32, 0), Color("ffffff"), 0.95, Color("fff6ea"), 0.55],
		"evening": [Vector3(-16, 60, 0), Color("ffb36b"), 0.75, Color("f2c9a0"), 0.42],
		"night": [Vector3(-40, -30, 0), Color("9fb4e0"), 0.38, Color("7f8fb8"), 0.45],
	}
	var l: Array = looks.get(mood, looks.day)
	var tw := create_tween().set_parallel()
	tw.tween_property(sun, "rotation_degrees", l[0], 0.8)
	tw.tween_property(sun, "light_color", l[1], 0.8)
	tw.tween_property(sun, "light_energy", l[2], 0.8)
	tw.tween_property(env, "ambient_light_color", l[3], 0.8)
	tw.tween_property(env, "ambient_light_energy", l[4], 0.8)


## Puts the diorama in front of the player at about table height, the gate facing them.
func _place_table() -> void:
	var head := _head()
	var fwd := -head.basis.z
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var table := _nearest_table(head, fwd)
	if not table.is_empty():
		# on the real table: centred on its top, sized to fit it (the island is 0.66 m across at 1x)
		var fit: float = minf(table.size.x, table.size.y) * 0.95 / 0.66
		table_k = clampf(minf(table_k, fit), 0.4, 3.0)
		var c: Vector3 = table.center
		var to := Vector3(head.origin.x - c.x, 0, head.origin.z - c.z)
		var face := -to.normalized() if to.length() > 0.05 else fwd
		diorama.global_transform = Transform3D(Basis.looking_at(face, Vector3.UP).scaled(Vector3.ONE * table_k), c + Vector3(0, 0.005, 0))
		return
	var y := maxf(0.55, head.origin.y - 0.55) if head.origin.y > 0.3 else 0.75
	diorama.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP).scaled(Vector3.ONE * table_k),
		Vector3(head.origin.x, y, head.origin.z) + fwd * 0.7)


## The detected table closest in front of the player (within 3 m), or {}.
func _nearest_table(head: Transform3D, fwd: Vector3) -> Dictionary:
	if surfaces == null:
		return {}
	var best := {}
	var best_score := INF
	for s in surfaces.surfaces():
		if s.label != "table":
			continue
		var to: Vector3 = s.center - head.origin
		var flat := Vector3(to.x, 0, to.z)
		var d := flat.length()
		if d > 3.0 or d < 0.15:
			continue
		var score := d - flat.normalized().dot(fwd)
		if score < best_score:
			best_score = score
			best = s
	return best


func _on_grip_tap(_hand: String) -> void:
	if diorama and card == null:
		_moved_by_hand = false
		_place_table()


func _table_controls(dt: float) -> void:
	var save := get_node_or_null("/root/Save")
	var st := rig.stick("right" if save and save.left_handed else "left")  # the other stick walks the old man
	if absf(st.x) > 0.25:
		diorama.rotate_y(-st.x * 1.4 * dt)
	if absf(st.y) > 0.25:
		var nk := clampf(table_k * exp(st.y * 0.9 * dt), 0.4, 3.0)
		var t := diorama.global_transform
		diorama.global_transform = Transform3D(t.basis.scaled(Vector3.ONE * (nk / table_k)), t.origin)
		table_k = nk
	var dh := rig.dragging_hand()
	if dh != "":
		var c: Vector3 = rig.hands[dh].grip.global_position
		if _drag.get("hand", "") != dh:
			_drag = {"hand": dh, "ctrl": c, "pos": diorama.global_position}
			_moved_by_hand = true
		diorama.global_position = _drag.pos + (c - _drag.ctrl)
	else:
		_drag = {}


func _head() -> Transform3D:
	if xr:
		return rig.head_transform()
	return desk_cam.global_transform if desk_cam else Transform3D()


func _ensure_passthrough() -> void:
	var xi := rig.xr_interface
	if xi == null:
		return
	if xi.get_supported_environment_blend_modes().has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND):
		rig.passthrough_supported = true
		_mr_on = rig.set_mode("mr") == "mr"


func _process(dt: float) -> void:
	if xr and not _mr_on:
		_ensure_passthrough()
	if card:
		if xr:
			_place_card(false)
		if _preview:
			_preview.rotation.y += dt * 0.5
	if not xr:
		_desk_move(dt)
	if diorama == null or level == null:
		return
	if level.has_method("move"):
		level.move(_hero_stick() if card == null else Vector2.ZERO)
	var held := false
	var hit = null
	if xr:
		if card == null:
			_table_controls(dt)
		for hand in ["right", "left"]:
			if not rig.tracked(hand):
				continue
			var c: XRController3D = rig.hands[hand].aim
			var down: bool = c.is_button_pressed("trigger_click") or c.get_float("trigger") > 0.6
			var r := rig.ray(hand)
			var p = diorama.model_point(r[0], r[1])
			rig.set_pointer(hand, {"point": diorama.model.to_global(p), "interactive": down} if p != null and card == null else null, true)
			if down and card == null:
				held = true
				hit = p
				if level.has_method("aim"):
					level.aim(r[0], r[1])
				break
	else:
		held = _mouse_draw and card == null
		if held:
			var mp := get_viewport().get_mouse_position()
			hit = diorama.model_point(desk_cam.project_ray_origin(mp), desk_cam.project_ray_normal(mp))
			if level.has_method("aim"):
				level.aim(desk_cam.project_ray_origin(mp), desk_cam.project_ray_normal(mp))
	level.pointer(held, hit)


## The stick that walks the old man (right; left when the player is left-handed), or the
## arrow keys on desktop, turned into a direction on the diorama's ground (its x, z).
func _hero_stick() -> Vector2:
	var st := Vector2.ZERO
	var basis := Basis()
	if xr:
		var save := get_node_or_null("/root/Save")
		st = rig.stick("left" if save and save.left_handed else "right")
		if st.length() < 0.2:
			return Vector2.ZERO
		basis = rig.head_transform().basis
	else:
		st = Vector2(float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)),
			float(Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_DOWN)))
		if st == Vector2.ZERO or desk_cam == null:
			return Vector2.ZERO
		basis = desk_cam.global_basis
	var fwd := -basis.z
	fwd.y = 0
	var right := basis.x
	right.y = 0
	var world := right.normalized() * st.x + fwd.normalized() * st.y
	var local := diorama.model.global_basis.inverse() * world
	var v := Vector2(local.x, local.z)
	return v.normalized() * minf(st.length(), 1.0) if v.length() > 0.0001 else Vector2.ZERO


func _unhandled_input(e: InputEvent) -> void:
	if xr:
		return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and card:
				var b := _card_hit(desk_cam.project_ray_origin(mb.position), desk_cam.project_ray_normal(mb.position))
				if not b.is_empty():
					b.action.call()
					return
			_mouse_draw = mb.pressed
	elif e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_yaw -= (e as InputEventMouseMotion).relative.x * 0.005
		_pitch = clampf(_pitch - (e as InputEventMouseMotion).relative.y * 0.005, -1.4, 1.2)
	elif e is InputEventKey and e.pressed:
		match (e as InputEventKey).physical_keycode:
			KEY_ESCAPE: _show_card("start")
			KEY_Q: if diorama: diorama.rotate_y(0.2)
			KEY_E: if diorama: diorama.rotate_y(-0.2)


func _desk_move(dt: float) -> void:
	if desk_cam == null:
		return
	desk_cam.rotation = Vector3(_pitch, _yaw, 0)
	var v := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if v != Vector2.ZERO:
		var b := Basis(Vector3.UP, _yaw)
		rig.position += (b.x * v.x + b.z * v.y) * 1.0 * dt


# --- screenshots ----------------------------------------------------------------------------

func _screenshot() -> void:
	for i in 20:
		await get_tree().process_frame
	if diorama:
		table_k = float(_args.get("k", "1"))  # --k=N: the diorama N times its usual size
		_place_table()
		diorama.rotate_y(deg_to_rad(float(_args.get("turn", "0"))))  # --turn=deg: see another side
	if card:
		_place_card(true)
	if level and _args.has("demo"):
		level.demo()
	for i in int(_args.get("wait", "40")):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_args.screenshot)
	get_tree().quit()
