class_name TableMenu
extends Node3D
## The table game's one menu, on the owner's clay plaque (after Dahrooj Quest's menu: one
## quiet panel, a rail of section tabs on one side, the section on the other, the name of
## whatever the pointer is on shown above it). Read right to left: the rail is on the right.
##   levels    the ten levels with their stars and gems, the totals, play / carry on
##   wardrobe  the old man turning on his stand, and all his clothes to try on
##   world     weather by itself, drifting dust, day and night going round, set the scene down
##             elsewhere (the room's tables come from the headset's own room scan, by themselves)
##   settings  music, effects and surroundings volume; which hand walks; vibration; the
##             language (Arabic or English; at first the headset's own). One player only.
##   about     who made it, and whose work it uses
##   thanks    (after the last level) thank you, the studio's site (opens it; and a QR code), play again
##   close     back to the game (only while a level is on the table)
## The owner of this node (table_main) places it, feeds it the pointer (hover / press) and
## listens to its signals.

signal play_level(n: int)     # 0: the next level not yet won
signal closed
signal replace_table
signal settings_changed

const W := 0.62
const H := W * 541.0 / 1024.0
const PLAQUE := "res://assets/ui/menu_plaque.png"
const ICONS := "res://assets/ui/icons/"
const ACCENT := Color("7a5a3a")
const ACCENT_DARK := Color("4f3826")
const DISC := Color("fbf3e4")
const PALE := Color("ead7b8")
const FADED := Color("b39270")
const GOLD := Color("e3a83a")
const GEM := Color("8fd0e8")
const RAIL_X := 0.262
const CX := -0.035            # middle of the section area
const LABEL_Y := 0.118
const LEVELS := 11
const SITE := "https://abodengames.com"   # the studio's games
const LOGO := "res://assets/brand/aboden_logo.png"   # the studio's logo (white on transparency)
const TABS := [["levels", "levels", "المراحل", "Levels"], ["wardrobe", "wardrobe", "خزانة الشايب", "Wardrobe"],
	["world", "atmosphere", "الأجواء", "Atmosphere"], ["settings", "settings", "الإعدادات", "Settings"],
	["about", "about", "عن اللعبة", "About"]]

var page := "levels"
var stage := 0                # the level on the table (0: none yet)
var _buttons: Array = []      # {at, r, action, label}
var _hot := -1
var _hover_ring: MeshInstance3D
var _label: Label3D
var _content: Node3D
var _preview: Node3D
var _preview_anim: AnimationPlayer
var _spin := 0.0
static var _font: Font


func _ready() -> void:
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(W, H)
	bg.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = load(PLAQUE)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	bg.material_override = m
	add_child(bg)
	# the rail: a lighter band behind the tabs, rounded at both ends
	var rail := Node3D.new()
	add_child(rail)
	_quad(rail, Vector2(0.05, 0.23), PALE, Vector3(RAIL_X, -0.005, 0.001))
	for y in [0.11, -0.12]:
		_disc(rail, Vector3(RAIL_X, y, 0.001), 0.025, PALE)
	_hover_ring = _disc(self, Vector3.ZERO, 1.0, ACCENT_DARK)
	_hover_ring.visible = false
	_label = text("", Vector3(CX, LABEL_Y, 0.006), 46)
	add_child(_label)
	open(page)


func open(p: String) -> void:
	page = p
	if _content:
		_content.queue_free()
	_content = Node3D.new()
	add_child(_content)
	_buttons.clear()
	_hot = -1
	_hover_ring.visible = false
	_label.text = ""
	_preview = null
	var tabs: Array = TABS.duplicate()
	if stage > 0:
		tabs.insert(1, ["hint", "hint", "تلميح المرحلة", "A hint for this level"])
		tabs.append(["close", "close", "رجوع للعب", "Back to the game"])
	var step := 0.23 / maxf(1, tabs.size() - 1)
	for i in tabs.size():
		var t: Array = tabs[i]
		var at := Vector3(RAIL_X, 0.11 - i * step, 0.004)
		var on: bool = t[0] == page
		var id: String = t[0]
		_button(at, minf(0.019, step * 0.45), t[1], ACCENT if on else DISC, Color.WHITE if on else ACCENT,
			_say(t[2], t[3]), func(): _tab(id), 1.4)
	match page:
		"wardrobe": _wardrobe()
		"world": _world()
		"settings": _settings()
		"about": _about()
		"hint": _hint()
		"thanks": _thanks()
		_: _levels()


func _tab(id: String) -> void:
	if id == "close":
		closed.emit()
		return
	open(id)


# --- sections ---------------------------------------------------------------------------------

func _levels() -> void:
	var save := _save()
	var en := not _arabic()
	for i in LEVELS:
		var n := i + 1
		# read right to left in Arabic (١ at the top right), left to right in English; six a row
		var x := -0.152 + (i % 6) * 0.064 if en else 0.172 - (i % 6) * 0.064
		var at := Vector3(x, 0.066 - (i / 6) * 0.094, 0.004)
		if stage == n:
			_disc(_content, at - Vector3(0, 0, 0.001), 0.031, ACCENT_DARK)
		var stars: int = save.table_stars.get(n, 0) if save else 0
		var label := _say("المرحلة %s" % _digits(n), "Level %d" % n)
		_button(at, 0.026, "none" if en else "level_%d" % n, ACCENT, Color.WHITE, label, func(): play_level.emit(n), 1.9)
		if en:   # the level icons carry Arabic numerals; in English the number is written
			_content.add_child(text(str(n), at + Vector3(0, 0.001, 0.004), 80, Color.WHITE))
		for k in 3:
			_icon(_content, "star", at + Vector3((1 - k) * 0.016, -0.038, 0.002), 0.015, GOLD if k < stars else Color(FADED, 0.8))
		if save and save.table_gems.get(n, false):
			_icon(_content, "gem", at + Vector3(0.024, 0.022, 0.006), 0.016, GEM)
	# carry on (or back to the level on the table), and the totals
	var y := -0.108
	if stage > 0:
		_button(Vector3(0.165, y, 0.004), 0.022, "play", ACCENT, Color.WHITE, _say("رجوع للعب", "Back to the game"), func(): closed.emit())
	else:
		_button(Vector3(0.165, y, 0.004), 0.022, "play", ACCENT, Color.WHITE, _say("العب", "Play"), func(): play_level.emit(0))
	var tot := 0
	var gems := 0
	if save:
		for k in save.table_stars:
			tot += save.table_stars[k]
		gems = save.table_gems.size()
	_icon(_content, "star", Vector3(0.088, y, 0.004), 0.02, GOLD)
	var side := 0.034 if en else -0.034   # the number after its icon, in reading order
	_content.add_child(text("%s/%s" % [_digits(tot), _digits(LEVELS * 3)], Vector3(0.088 + side, y, 0.004), 46))
	_icon(_content, "gem", Vector3(0.006, y, 0.004), 0.02, GEM)
	_content.add_child(text("%s/%s" % [_digits(gems), _digits(LEVELS)], Vector3(0.006 + side, y, 0.004), 46))


func _wardrobe() -> void:
	var save := _save()
	var stand := TableKit.cyl(_content, 0.062, 0.066, 0.01, _flat(Color("c79b6c")), Vector3(-0.112, -0.11, 0.05), 32)
	stand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ps := load(Diorama.SHAIB) as PackedScene
	if ps:
		_preview = ps.instantiate()
		_content.add_child(_preview)
		_preview.scale = Vector3.ONE * 0.15
		_preview.position = Vector3(-0.112, -0.105, 0.05)
		_preview.rotation.y = _spin
		var aps := _preview.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			_preview_anim = aps[0]
			if _preview_anim.has_animation("idle"):
				_preview_anim.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
				_preview_anim.play("idle")
		for mi in _preview.find_children("*", "GeometryInstance3D", true, false):
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Wardrobe.apply(_preview, save.wearing if save else {})
	for i in Wardrobe.ITEMS.size():
		var it: Dictionary = Wardrobe.ITEMS[i]
		var id: String = it.id
		var at := Vector3(0.17 - (i % 4) * 0.064, 0.055 - (i / 4) * 0.09, 0.004)
		var worn: bool = save != null and save.wearing.get(it.slot, "") == id
		if worn:
			_disc(_content, at - Vector3(0, 0, 0.001), 0.032, ACCENT_DARK)
		# all of it open to try on (the owner's choice: clothes are not prizes)
		_button(at, 0.027, "w_" + id, DISC, Color.WHITE, _say(it.ar, it.en), func(): _wear(id), 1.5)


func _world() -> void:
	var save := _save()
	var auto_on: bool = save == null or save.weather_pref != "clear"
	var dust_on: bool = save == null or save.dust
	var cycle_on: bool = save == null or save.day_cycle
	var y := 0.025
	var flip_auto := func(): save.weather_pref = "clear" if auto_on else "cycle"
	var flip_dust := func(): save.dust = not dust_on
	var flip_cycle := func(): save.day_cycle = not cycle_on
	_toggle(Vector3(0.16, y, 0.004), "rain", auto_on, _say("الطقس تلقائي: مطر وعجاج", "Weather by itself: rain and blown sand"), flip_auto, 0.032)
	_toggle(Vector3(0.075, y, 0.004), "dust", dust_on, _say("الغبار", "Drifting dust"), flip_dust, 0.032)
	_toggle(Vector3(-0.01, y, 0.004), "daynight", cycle_on, _say("الليل والنهار يتبدلون", "Day and night go round"), flip_cycle, 0.032)
	_button(Vector3(-0.095, y, 0.004), 0.032, "board", ACCENT, Color.WHITE, _say("ثبّت المشهد في مكان ثاني", "Set the scene down somewhere else"),
		func(): replace_table.emit())


func _settings() -> void:
	var save := _save()
	if save == null:
		return
	var rows := [["music", "music_volume", "الموسيقى", "Music"], ["sound", "sfx_volume", "المؤثرات", "Effects"],
		["wind", "ambience_volume", "أصوات المكان", "Surroundings"]]
	for r in rows.size():
		var y := 0.07 - r * 0.045
		var key: String = rows[r][1]
		var label := _say(rows[r][2], rows[r][3])
		_icon(_content, rows[r][0], Vector3(0.175, y, 0.004), 0.026, ACCENT_DARK)
		var v := int(round(float(save.get(key)) * 5.0))
		_button(Vector3(0.13, y, 0.004), 0.015, "plus", ACCENT, Color.WHITE, label, func():
			save.set(key, minf(1.0, (v + 1) / 5.0))
			_changed())
		for k in 5:
			_disc(_content, Vector3(0.1 - k * 0.026, y, 0.004), 0.008, ACCENT if k < v else PALE)
		_button(Vector3(-0.03, y, 0.004), 0.015, "minus", ACCENT, Color.WHITE, label, func():
			save.set(key, maxf(0.0, (v - 1) / 5.0))
			_changed())
	var y2 := -0.085
	var left: bool = save.left_handed
	_button(Vector3(0.15, y2, 0.004), 0.024, "hand_left" if left else "hand_right", ACCENT, Color.WHITE,
		_say("المشي باليد اليسرى", "Walk with the left hand") if left else _say("المشي باليد اليمنى", "Walk with the right hand"),
		func():
			save.left_handed = not left
			_changed())
	var buzz := func(): save.haptics = not save.haptics
	_toggle(Vector3(0.085, y2, 0.004), "haptics", save.haptics, _say("الاهتزاز", "Vibration"), buzz, 0.024)
	var english: bool = not save.arabic()
	_button(Vector3(0.02, y2, 0.004), 0.024, "language", ACCENT, Color.WHITE, "العربية" if english else "English",
		func():
			save.language = "ar" if english else "en"
			_changed())


## After the last level: thank you for playing, and where to find the studio's other games:
## the site on a band that opens it in the headset's browser, and as a QR code for a phone.
func _thanks() -> void:
	var cx := 0.075
	_content.add_child(text(_say("شكراً لأنك جرّبت مفاتيح", "Thank you for playing Mafateeh"), Vector3(cx, 0.08, 0.004), 56))
	_content.add_child(text(_say("نتمنى إن الرحلة مع الشايب عجبتك", "We hope you enjoyed the journey with the old man"), Vector3(cx, 0.045, 0.004), 32))
	_content.add_child(text(_say("اكتشف ألعاب جديدة من استوديو عبودين قيمز", "Discover more games from Aboden Games"), Vector3(cx, 0.012, 0.004), 32))
	var at := Vector3(cx, -0.03, 0.004)
	_quad(_content, Vector2(0.15, 0.032), ACCENT, at - Vector3(0, 0, 0.001))
	for x in [-0.075, 0.075]:
		_disc(_content, at + Vector3(x, 0, -0.001), 0.016, ACCENT)
	_content.add_child(text("abodengames.com", at + Vector3(0, 0, 0.003), 44, Color.WHITE))
	# press it and the headset's browser opens the site (the owner wants players to go there)
	_buttons.append({"at": at, "r": 0.075, "action": func(): OS.shell_open(SITE), "label": _say("افتح موقع الاستوديو", "Open the studio's site"), "no_ring": true})
	_button(Vector3(cx, -0.098, 0.004), 0.02, "restart", ACCENT, Color.WHITE, _say("العب من جديد", "Play again"), func(): play_level.emit(1))
	# the QR code, on a cream card, with a word under it
	var qx := -0.16
	_quad(_content, Vector2(0.118, 0.118), DISC, Vector3(qx, 0.012, 0.002))
	var qr := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.104, 0.104)
	qr.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = load("res://assets/ui/site_qr.png")
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC   # clean at any distance
	qr.material_override = m
	qr.position = Vector3(qx, 0.012, 0.004)
	_content.add_child(qr)
	_content.add_child(text(_say("صوّر الرمز بجوالك", "Scan it with your phone"), Vector3(qx, -0.062, 0.004), 30))


## One hint for each level's puzzle, in words (the levels themselves stay wordless).
const HINTS := {
	1: ["اضغط الزناد على القط وارسم دربه للشايب: لف حول الشوك وادخل من البوابة.", "Hold the trigger on the cat and draw its way to the old man: round the thorns, in through the gate."],
	2: ["ادفع الحجارة بالشايب وسوّ منها درج للقط: الأطول جنب الجدار ثم الأقصر فالأقصر.", "Push the blocks with the old man into a stair for the cat: the tallest by the wall, then shorter ones."],
	3: ["أرسل الصقر من وكر لوكر قريب منه لين يوصل المفتاح، وبعدين رجّعه للشايب.", "Send the falcon from perch to a near perch until it reaches the key, then bring it back to the old man."],
	4: ["كل سيارة تمشي على خطها بس: فضّ الطريق قدام الوايت لين يطلع.", "Each car moves only along its own line: clear the way in front of the water truck so it can get out."],
	5: ["كل فانوس ينقلب هو واللي جنبه: ولّع الفوانيس الثمانية كلها.", "Each lantern flips itself and the one beside it: light all eight."],
	6: ["اسمع إيقاع الشايب على الطبول وأعده بنفس الترتيب. اضغط الشايب يعيده لك.", "Listen to the old man's beat and play it back drum for drum. Tap him to hear it again."],
	7: ["كل حلقة تدور هي واللي برا منها: خل النجوم الساطعة على خط واحد صوب الرجم.", "Each ring turns with the one outside it: line the bright stars up towards the cairn."],
	8: ["بادل من تاجر لتاجر لين توصل للدلة، وانتبه لتاجرين يلفونك بحلقة ما توصل لشي.", "Trade from merchant to merchant to reach the coffee pot; two of them only trade in a circle."],
	9: ["دوّر قطع السواقي لين يوصل الماي من الحوض للنخلات الثلاث.", "Turn the channel pieces until the water runs from the basin to all three palms."],
	10: ["أشّر على الغازي اللي على الجمل أو الخيل واضغط الزناد: يرمونه ربع الشايب ويطيح من ظهر ذلوله. طيّحهم كلهم.", "Point at a raider on his camel or horse and pull the trigger: the old man's men fire and knock him from the saddle. Unhorse them all."],
	11: ["حط التذكارات في الصندوق بترتيب المراحل: من الأولى للتاسعة.", "Put the keepsakes in the chest in the order of the levels, from the first to the ninth."],
}


func _hint() -> void:
	_icon(_content, "hint", Vector3(CX + 0.01, 0.07, 0.004), 0.04, ACCENT)
	_content.add_child(text(_say("المرحلة %s", "Level %s") % _digits(stage), Vector3(CX + 0.01, 0.03, 0.004), 44))
	var h: Array = HINTS.get(stage, ["", ""])
	var l := text(_say(h[0], h[1]), Vector3(CX + 0.01, -0.025, 0.004), 36)
	l.width = 1200.0   # wrap within the section (the label's own pixels)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(l)


func _about() -> void:
	var lines := [
		[_say("مفاتيح", "Mafateeh"), 0.082, 64],
		[_say("لعبة من عبودين قيمز: المباني والشخصيات من تصميمهم", "Buildings and characters by Aboden Games"), 0.042, 34],
		[_say("بعض الموديلات من Folio 2025 لـ Bruno Simon (MIT)", "Some models from Folio 2025 by Bruno Simon (MIT)"), 0.0, 30],
		[_say("المحرك Godot", "Engine: Godot"), -0.03, 30],
		[_say("لا اتصال بالإنترنت ولا تتبع: كل شي يبقى في نظارتك", "No network, no tracking: everything stays on your headset"), -0.06, 28],
	]
	for l in lines:
		_content.add_child(text(l[0], Vector3(CX + 0.07, l[1], 0.004), l[2]))
	# the studio's logo beside them, in the plaque's dark brown
	var logo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.125, 0.13)
	logo.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = load(LOGO)
	m.albedo_color = ACCENT_DARK
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.render_priority = 2
	logo.material_override = m
	logo.position = Vector3(-0.205, 0.03, 0.004)
	_content.add_child(logo)


# --- the pointer ---------------------------------------------------------------------------------

## Points at the menu: the world point on it ({point, normal, interactive}) or null when the
## ray misses it. The button under it is ringed and named above the section.
func hover(origin: Vector3, dir: Vector3) -> Variant:
	var plane := Plane(global_basis.z.normalized(), global_position)
	var p = plane.intersects_ray(origin, dir)
	if p == null:
		_set_hot(-1)
		return null
	var local := to_local(p)
	if absf(local.x) > W / 2 or absf(local.y) > H / 2:
		_set_hot(-1)
		return null
	var hot := -1
	# a little stickiness at the edge of the button already under the pointer: hand tremor
	# does not flick between neighbours
	if _hot >= 0 and _hot < _buttons.size() and Vector2(local.x, local.y).distance_to(Vector2(_buttons[_hot].at.x, _buttons[_hot].at.y)) < _buttons[_hot].r * 1.3:
		hot = _hot
	else:
		var best := INF
		for i in _buttons.size():
			var b: Dictionary = _buttons[i]
			var d := Vector2(local.x, local.y).distance_to(Vector2(b.at.x, b.at.y))
			if d < b.r * 1.15 and d < best:
				best = d
				hot = i
	_set_hot(hot)
	return {"point": p, "normal": global_basis.z.normalized(), "interactive": hot >= 0}


## The pointer was pressed: works the button under it. False when there was none.
func press() -> bool:
	if _hot < 0 or _hot >= _buttons.size():
		return false
	var a: Callable = _buttons[_hot].action
	TableKit.sfx(self, "ui_click", Vector3.ZERO, -4.0)
	a.call()
	return true


func _set_hot(i: int) -> void:
	if i == _hot:
		return
	_hot = i
	_hover_ring.visible = i >= 0 and not _buttons[i].get("no_ring", false)
	if i >= 0:
		var b: Dictionary = _buttons[i]
		_hover_ring.position = b.at - Vector3(0, 0, 0.002)
		_hover_ring.scale = Vector3.ONE * b.r * 1.22
		_label.text = b.label
	else:
		_label.text = ""


func _process(dt: float) -> void:
	if _preview:
		_spin += dt * 0.5
		_preview.rotation.y = _spin


# --- actions ---------------------------------------------------------------------------------

func _wear(id: String) -> void:
	var save := _save()
	var it := Wardrobe.item(id)
	if save == null or it.is_empty():
		return
	if save.wearing.get(it.slot, "") == id:
		save.wearing.erase(it.slot)
	else:
		save.wearing[it.slot] = id
	save.save()
	settings_changed.emit()
	open("wardrobe")
	if _preview_anim and _preview_anim.has_animation("excited"):
		_preview_anim.play("excited", 0.2)
		_preview_anim.queue("idle")


## A setting changed: saved, applied by the owner, and the section redrawn.
func _changed() -> void:
	var save := _save()
	if save:
		save.save()
	settings_changed.emit()
	var keep := _hot
	open(page)
	_set_hot(keep if keep < _buttons.size() else -1)


# --- building blocks ---------------------------------------------------------------------------

func _button(at: Vector3, r: float, icon: String, disc: Color, tint: Color, label: String, action: Callable, icon_k := 1.15) -> void:
	_disc(_content, at, r, disc)
	_icon(_content, icon, at + Vector3(0, 0, 0.004), r * icon_k, tint)
	_buttons.append({"at": at, "r": r, "action": action, "label": label})


## A switch: a full brown disc when on, a pale one with a faded icon when off.
func _toggle(at: Vector3, icon: String, on: bool, label: String, flip: Callable, r := 0.034) -> void:
	_button(at, r, icon, ACCENT if on else PALE, Color.WHITE if on else FADED, label, func():
		flip.call()
		_changed())


func _disc(parent: Node3D, at: Vector3, r: float, c: Color) -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.003
	cm.radial_segments = 40
	cm.rings = 1
	disc.mesh = cm
	disc.rotation.x = PI / 2
	disc.material_override = _flat(c)
	disc.position = at
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(disc)
	return disc


func _quad(parent: Node3D, size: Vector2, c: Color, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = _flat(c)
	mi.position = at
	parent.add_child(mi)


func _icon(parent: Node3D, icon: String, at: Vector3, size: float, tint := Color.WHITE) -> void:
	var path := ICONS + icon + ".png"
	if not ResourceLoader.exists(path):
		return
	var ic := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	ic.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = load(path)
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	ic.material_override = m
	ic.position = at
	parent.add_child(ic)


## A line of text in the menu's font (Noto Naskh Arabic, bold).
static func text(s: String, at: Vector3, size := 40, c := ACCENT_DARK) -> Label3D:
	var l := Label3D.new()
	l.text = s
	l.font = font()
	l.font_size = int(size * 1.15)   # Naskh's letters sit small: a little larger than the sizes asked
	l.pixel_size = 0.00034
	l.modulate = c
	l.outline_size = 0
	l.position = at
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED   # blended: a cut ate the letters' fine strokes and dots
	l.render_priority = 2
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	l.shaded = false
	l.double_sided = false
	return l


static func font() -> Font:
	if _font == null:
		# Noto Naskh Arabic: a plain, unfussy Naskh (the free counterpart of Sakkal Majalla,
		# which the owner liked but may not be shipped; OFL, no credit owed in the game), bold,
		# with Cairo for the Latin letters and anything else it lacks
		var f := FontVariation.new()
		f.base_font = load("res://assets/fonts/noto-naskh-arabic-variable.ttf")
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
		f.fallbacks = [load("res://assets/fonts/cairo-variable.ttf")]
		_font = f
	return _font


static func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _save() -> Node:
	return get_node_or_null("/root/Save") if is_inside_tree() else null


func _arabic() -> bool:
	var save := _save()
	return save == null or save.arabic()


func _say(ar: String, en: String) -> String:
	var save := _save()
	return save.text(ar, en) if save else ar


## Arabic-Indic digits in Arabic, plain ones in English.
func _digits(n: int) -> String:
	var save := _save()
	var s := str(n)
	if save and not save.arabic():
		return s
	var out := ""
	for ch in s:
		out += "٠١٢٣٤٥٦٧٨٩"[int(ch)]
	return out
