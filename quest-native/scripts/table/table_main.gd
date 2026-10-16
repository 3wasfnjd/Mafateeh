extends Node3D
## Mafateeh: the tabletop game in mixed reality (the owner's direction: AR only, a small
## diorama on the table, few words, light simple menus in beige / light brown).
##
## Start card: play, and the wardrobe. The wardrobe shows the old man himself, turning slowly,
## dressed in what he wears; tap an item to put it on or take it off.
## In play: the scene-1 diorama sits on the table and level 1 (TablePathLevel) runs on it.
##   Trigger: draw (or press a card button). Hold grip and move the hand: carry the diorama.
##   Left stick x: turn it; y: resize it. Tap grip: bring it back in front. Menu: the card.
## Desktop (no headset): click buttons, drag on the sand to draw, WASD walk, right-drag look,
##   Q/E turn the diorama, Esc the card.
## Screenshot args: --screenshot=path [--start=play|wardrobe] [--cam=x,y,z,yaw,pitch]
##   [--demo=1] (play: draw a working path and let the cat walk it) [--wait=frames]

const ICONS := "res://assets/ui/icons/"
# palette: light, warm, no green (owner's choice)
const CARD := Color("f4ecdf")
const ACCENT := Color("b08a5e")     # light brown buttons
const ACCENT_DARK := Color("7a5a3a") # worn-item ring, little vents
const DISC := Color("fbf6ee")

var env: Environment
var rig: XRRig
var xr := false
var desk_cam: Camera3D
var card: Node3D
var _buttons: Array = []  # {local, r, action}
var _args := {}
var diorama: Diorama
var level: TablePathLevel
var table_k := 1.0
var _drag := {}
var _yaw := 0.0
var _pitch := -0.12
var _mouse_draw := false
var _preview: Node3D        # the old man on the wardrobe card
var _preview_anim: AnimationPlayer
var _card_kind := ""        # "start" | "wardrobe"


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
	var sun := DirectionalLight3D.new()
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
		rig.set_mode("mr")
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
		"play": _play()
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
	var m := _flat(CARD)
	m.albedo_color.a = 0.97
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg.material_override = m
	card.add_child(bg)
	for i in 3:  # a small row of vent triangles, the only ornament
		var tri := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.022, 0.022, 0.004)
		tri.mesh = pm
		tri.material_override = _flat(ACCENT)
		tri.position = Vector3((i - 1) * 0.032, size.y / 2 - 0.035, 0.003)
		card.add_child(tri)


func _show_card(kind: String) -> void:
	_card_kind = kind
	if kind == "wardrobe":
		_wardrobe_card()
		return
	_new_card(Vector2(0.46, 0.26))
	_icon_button("play", Vector3(-0.1, -0.012, 0.004), 0.07, _play)
	_icon_button("wardrobe", Vector3(0.1, -0.012, 0.004), 0.07, func(): _show_card("wardrobe"))


func _wardrobe_card() -> void:
	_new_card(Vector2(0.62, 0.40))
	# the old man on a small round stand, turning slowly
	var stand := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.075
	cm.bottom_radius = 0.08
	cm.height = 0.012
	stand.mesh = cm
	stand.material_override = _flat(Color("e3d3bb"))
	stand.position = Vector3(-0.17, -0.15, 0.06)
	card.add_child(stand)
	var ps := load(Diorama.SHAIB) as PackedScene
	if ps:
		_preview = ps.instantiate()
		card.add_child(_preview)
		_preview.scale = Vector3.ONE * 0.17  # 1.7 m -> about 29 cm
		_preview.position = Vector3(-0.17, -0.144, 0.06)
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
		var at := Vector3(0.03 + col * 0.075, 0.08 - row * 0.09, 0.004)
		_item_button(ids[i], at, 0.032)
	_icon_button("back", Vector3(0.07, -0.13, 0.004), 0.032, func(): _show_card("start"))
	_icon_button("play", Vector3(0.20, -0.13, 0.004), 0.032, _play)


func _icon_button(icon: String, at: Vector3, r: float, action: Callable) -> void:
	_disc(at, r, ACCENT)
	_icon(ICONS + icon + ".png", at + Vector3(0, 0, 0.004), r * 1.15)
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

func _play() -> void:
	if card:
		card.queue_free()
		card = null
	_card_kind = ""
	if diorama:
		diorama.queue_free()
	diorama = Diorama.new()
	diorama.pacing_cat = false     # the level's cat is the one on the path
	diorama.birds_outside = false  # keep the sand in front of the gate clear for drawing
	add_child(diorama)
	diorama.setup()
	level = TablePathLevel.new()
	diorama.model.add_child(level)
	level.setup(diorama)
	level.level_won.connect(func(): get_tree().create_timer(5.0).timeout.connect(func(): _show_card("start")))
	table_k = 1.0
	_place_table()


## Puts the diorama in front of the player at about table height, the gate facing them.
func _place_table() -> void:
	var head := _head()
	var fwd := -head.basis.z
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var y := maxf(0.55, head.origin.y - 0.55) if head.origin.y > 0.3 else 0.75
	diorama.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP).scaled(Vector3.ONE * table_k),
		Vector3(head.origin.x, y, head.origin.z) + fwd * 0.7)


func _on_grip_tap(_hand: String) -> void:
	if diorama and card == null:
		_place_table()


func _table_controls(dt: float) -> void:
	var st := rig.stick("left")
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
		diorama.global_position = _drag.pos + (c - _drag.ctrl)
	else:
		_drag = {}


func _head() -> Transform3D:
	if xr:
		return rig.head_transform()
	return desk_cam.global_transform if desk_cam else Transform3D()


func _process(dt: float) -> void:
	if card:
		if xr:
			_place_card(false)
		if _preview:
			_preview.rotation.y += dt * 0.5
	if not xr:
		_desk_move(dt)
	if diorama == null or level == null:
		return
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
				break
	else:
		held = _mouse_draw and card == null
		if held:
			var mp := get_viewport().get_mouse_position()
			hit = diorama.model_point(desk_cam.project_ray_origin(mp), desk_cam.project_ray_normal(mp))
	level.pointer(held, hit)


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
		_place_table()
	if card:
		_place_card(true)
	if level and _args.has("demo"):
		level.demo()
	for i in int(_args.get("wait", "40")):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_args.screenshot)
	get_tree().quit()
