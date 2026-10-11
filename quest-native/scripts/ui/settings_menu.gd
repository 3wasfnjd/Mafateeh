class_name SettingsMenu
extends Node3D
## Compact settings panel, opened with the left controller's menu button.
## Nothing is shown during play except a short level card and a brief board
## placement notice.
##
## Pages: main (continue, restart, previous/next level, level list, settings,
## about), levels (every reached level, playable again), settings in three tabs
## (sound, controls, display), reset confirmation, about. Developer tools
## (all levels, time/weather overrides) appear only when enabled: project
## setting mafateeh/dev/level_select, or tapping the title on the about page
## seven times.

const WIDTH := 0.36
const ROW := 0.046
const PIXEL := 0.00042
const GRID_COLS := 7
const SETTINGS_TABS := ["audio", "controls", "display"]

var main: Node
var panel: Node3D
var buttons: Array = []  # {rect: Rect2, action: Callable, mesh: MeshInstance3D, base: Material, hover: String}
var _open := false
var _page := "main"
var _font: FontFile
var _btn_mat: StandardMaterial3D
var _btn_hover: StandardMaterial3D
var _bg_mat: StandardMaterial3D
var _styles := {}
var _toast: Label3D
var _toast_t := 0.0
var _card: Label3D
var _card_t := 0.0
var _title_taps := 0
var _info: Label3D
var _info_default := ""


func setup(m: Node) -> void:
	main = m
	_font = load("res://assets/fonts/cairo-arabic-700-normal.woff2") as FontFile
	if _font:
		var latin := load("res://assets/fonts/cairo-latin-700-normal.woff2") as FontFile
		if latin:
			_font.fallbacks = [latin]
	_bg_mat = _flat(Color(0.16, 0.11, 0.08, 0.94))
	_bg_mat.render_priority = -1  # translucent backdrop sorts behind the (translucent) text
	_btn_mat = _flat(Color(0.42, 0.28, 0.17, 1.0))
	_btn_hover = _flat(Color(0.72, 0.5, 0.26, 1.0))
	_styles = {
		"done": _flat(Color(0.33, 0.4, 0.2, 1.0)),
		"current": _flat(Color(0.78, 0.56, 0.24, 1.0)),
		"locked": _flat(Color(0.22, 0.16, 0.12, 1.0)),
		"tab_on": _flat(Color(0.6, 0.42, 0.22, 1.0)),
		"danger": _flat(Color(0.52, 0.17, 0.12, 1.0)),
	}
	panel = Node3D.new()
	panel.visible = false
	add_child(panel)
	_toast = _label("", 0.0006)
	_toast.visible = false
	add_child(_toast)
	_card = _label("", 0.0009)
	_card.visible = false
	main.board.add_child(_card)
	_card.pixel_size = 0.012
	main.game.level_loaded.connect(_show_card)
	main.game.level_loaded.connect(func(_n): if _open: _rebuild())


static func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _label(text: String, pixel: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = pixel
	l.font_size = 48
	l.outline_size = 10
	l.outline_modulate = Color(0.1, 0.06, 0.03, 0.9)
	l.modulate = Color("fff4e0")
	if _font:
		l.font = _font
	l.no_depth_test = false
	l.render_priority = 1
	l.double_sided = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_direction = TextServer.DIRECTION_AUTO
	return l


func is_open() -> bool:
	return _open


func page() -> String:
	return _page


func toggle(head: Transform3D) -> void:
	if _open:
		close()
		return
	_open = true
	_page = "main"
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.01 else Vector3.FORWARD
	panel.global_position = head.origin + fwd * 0.5 + Vector3(0, -0.12, 0)
	panel.look_at(head.origin, Vector3.UP, true)
	_rebuild()
	panel.visible = true
	main.audio.ui("open")
	if main.game.motor:
		main.game.motor.cancel()


func close() -> void:
	_open = false
	panel.visible = false
	main.audio.ui("close")


func open_page(p: String) -> void:
	_page = p
	_rebuild()


# --- layout ------------------------------------------------------------------------------

func _rebuild() -> void:
	for c in panel.get_children():
		c.queue_free()
	buttons.clear()
	_info = null
	var rows: Array = []
	match _page:
		"levels": rows = _level_rows()
		"audio", "controls", "display": rows = _settings_rows()
		"reset": rows = _reset_rows()
		"credits": rows = _credit_rows()
		_: rows = _main_rows()
	var height := rows.size() * ROW + 0.03
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(WIDTH + 0.02, height)
	bg.mesh = q
	bg.material_override = _bg_mat
	bg.position = Vector3(0, 0, -0.002)
	panel.add_child(bg)
	var y := height / 2.0 - 0.015 - ROW / 2.0
	for row in rows:
		var items: Array = row if row is Array else [row]
		var total := 0.0
		for it in items:
			total += it.get("w", 1.0)
		var x := -WIDTH / 2.0
		for it in items:
			var w: float = WIDTH * it.get("w", 1.0) / total
			var center := Vector2(x + w / 2.0, y)
			if it.has("action") or it.has("style"):
				var m := MeshInstance3D.new()
				var bq := QuadMesh.new()
				bq.size = Vector2(w - 0.006, ROW - 0.008)
				m.mesh = bq
				var base: Material = _styles.get(it.get("style", ""), _btn_mat)
				m.material_override = base
				m.position = Vector3(center.x, center.y, 0)
				panel.add_child(m)
				if it.has("action"):
					buttons.append({"rect": Rect2(center - Vector2(w, ROW) / 2.0, Vector2(w, ROW)),
						"action": it.action, "mesh": m, "base": base, "hover": it.get("hover", "")})
			var l := _label(it.text, PIXEL * (0.8 if it.get("small", false) else 1.0))
			if it.get("style", "") == "locked":
				l.modulate = Color(1.0, 0.96, 0.88, 0.45)
			l.position = Vector3(center.x, center.y, 0.002)
			panel.add_child(l)
			if it.get("info", false):
				_info = l
				_info_default = it.text
			x += w
		y -= ROW


static func _pct(v: float) -> String:
	return "%d٪" % roundi(v * 100)


func _main_rows() -> Array:
	var lvl: int = main.game.target_level()
	var d := LevelData.get_level(lvl)
	var prev := _neighbour(lvl, -1)
	var next := _neighbour(lvl, 1)
	var rows: Array = [
		{"text": "مفاتيح  ·  المرحلة %d — %s" % [lvl, d.title_ar]},
		{"text": "متابعة", "action": close},
		{"text": "إعادة المرحلة", "action": func(): close(); main.game.restart()},
		# Right to left: the previous level sits on the right, the next on the left.
		[_nav_item("التالية", next), {"text": "المراحل", "w": 1.3, "action": func(): open_page("levels")},
			_nav_item("السابقة", prev)],
		{"text": "الإعدادات", "action": func(): open_page("audio")},
		{"text": "حول اللعبة والتراخيص", "action": func(): open_page("credits")},
	]
	if Save.dev_tools_available():
		var sky: SkyWeather = main.sky
		rows.append({"text": "— أدوات المطوّر —", "small": true})
		rows.append([{"text": "الوقت: " + _time_ar(sky.time_name), "action": func(): sky.cycle_time(); Save.dev_time = sky.time_name; _rebuild()},
			{"text": "الطقس: " + ("مطر" if sky.raining else "صافٍ"), "action": func(): sky.toggle_rain(); Save.dev_weather = "rain" if sky.raining else "clear"; _rebuild()}])
	return rows


func _nav_item(text: String, target: int) -> Dictionary:
	if target < 1:
		return {"text": text, "w": 0.9, "style": "locked", "small": true}
	return {"text": text, "w": 0.9, "small": true, "action": func(): play_level(target)}


## Nearest playable level in a direction (-1 / +1), or 0.
func _neighbour(from: int, step: int) -> int:
	var n := from + step
	return n if Save.can_play(n) else 0


func play_level(n: int) -> void:
	if not Save.can_play(n):
		return
	Save.set_current(n)
	if n != main.game.target_level():
		main.game.go_to_level(n)


func _level_rows() -> Array:
	var cur: int = main.game.target_level()
	var done := 0
	for n in range(1, LevelData.COUNT + 1):
		if Save.is_completed(n):
			done += 1
	var rows: Array = [
		{"text": "المراحل  ·  أنجزت %d من %d" % [done, LevelData.COUNT]},
		{"text": _level_info(cur), "small": true, "info": true},
	]
	var n := 1
	while n <= LevelData.COUNT:
		var row: Array = []
		for c in GRID_COLS:
			if n > LevelData.COUNT:
				row.append({"text": ""})
			else:
				row.append(_level_cell(n, cur))
			n += 1
		row.reverse()  # level 1 starts at the right, like Arabic text
		rows.append(row)
	rows.append({"text": "رجوع", "action": func(): open_page("main")})
	return rows


func _level_cell(n: int, cur: int) -> Dictionary:
	if not Save.can_play(n):
		return {"text": str(n), "style": "locked"}
	var style := "current" if n == cur else ("done" if Save.is_completed(n) else "")
	var it := {"text": str(n), "hover": _level_info(n), "action": func(): close(); play_level(n)}
	if style != "":
		it["style"] = style
	return it


static func _level_info(n: int) -> String:
	var d := LevelData.get_level(n)
	var state := "مكتملة" if Save.is_completed(n) else ("مقفلة" if not Save.can_play(n) else "لم تكتمل بعد")
	return "%d — %s  ·  %s" % [n, d.title_ar, state]


func _tabs() -> Array:
	var names := {"audio": "الصوت", "controls": "التحكم", "display": "العرض"}
	var row: Array = []
	for t in SETTINGS_TABS:
		var it := {"text": names[t], "action": func(): open_page(t)}
		if t == _page:
			it["style"] = "tab_on"
		row.append(it)
	row.reverse()
	return row


func _stepper(text: String, minus: Callable, plus: Callable) -> Array:
	return [{"text": "−", "w": 0.5, "action": minus}, {"text": text, "w": 1.8}, {"text": "+", "w": 0.5, "action": plus}]


func _settings_rows() -> Array:
	var rows: Array = [{"text": "الإعدادات"}, _tabs()]
	match _page:
		"audio":
			rows.append(_stepper("الصوت العام " + _pct(Save.master_volume), func(): _volume("master", -0.1), func(): _volume("master", 0.1)))
			rows.append(_stepper("المؤثرات " + _pct(Save.sfx_volume), func(): _volume("sfx", -0.1), func(): _volume("sfx", 0.1)))
			rows.append(_stepper("الأجواء والمطر " + _pct(Save.ambience_volume), func(): _volume("ambience", -0.1), func(): _volume("ambience", 0.1)))
			rows.append({"text": "إلغاء الكتم" if Save.muted else "كتم الصوت", "action": func(): Save.muted = not Save.muted; _changed()})
		"controls":
			rows.append({"text": "التدوير: " + ("متدرّج 30°" if Save.turn_mode == "snap" else "سلس"),
				"action": func(): Save.turn_mode = "smooth" if Save.turn_mode == "snap" else "snap"; _changed()})
			rows.append({"text": "سرعة التدوير: " + ["بطيئة", "عادية", "سريعة"][Save.turn_speed],
				"action": func(): Save.turn_speed = (Save.turn_speed + 1) % 3; _changed()})
			rows.append({"text": "يد الحركة: " + ("اليسرى" if Save.left_handed else "اليمنى"),
				"action": func(): Save.left_handed = not Save.left_handed; _changed()})
			rows.append({"text": "الاهتزاز: " + ("يعمل" if Save.haptics else "متوقف"),
				"action": func(): Save.haptics = not Save.haptics; _changed(); main.pulse_ui()})
			rows.append({"text": "إظهار إرشادات التحكم", "action": func(): close(); main.show_controller_hints()})
		"display":
			rows.append({"text": "الوضع: " + ("الواقع المختلط" if Save.mode == "mr" else "الواقع الافتراضي"),
				"action": func(): main.set_mode("vr" if Save.mode == "mr" else "mr"); _rebuild()})
			rows.append({"text": "الطقس: " + ("صافٍ دائمًا" if Save.weather_pref == "clear" else "حسب المرحلة"),
				"action": func(): Save.weather_pref = "auto" if Save.weather_pref == "clear" else "clear"; _changed(); main.apply_sky()})
			rows.append([{"text": "حجم اللوحة الافتراضي", "small": true, "action": func(): main.reset_board_size()},
				{"text": "إعادة تموضع اللوحة", "small": true, "action": func(): close(); main._on_grip_tap("menu")}])
			rows.append({"text": "شعار البداية: " + ("يظهر" if Save.show_intro else "لا يظهر"),
				"action": func(): Save.show_intro = not Save.show_intro; _changed()})
			rows.append({"text": "مسح التقدم…", "style": "danger", "action": func(): open_page("reset")})
	rows.append({"text": "رجوع", "action": func(): open_page("main")})
	return rows


func _reset_rows() -> Array:
	return [
		{"text": "مسح كل التقدم؟"},
		{"text": "تعود إلى المرحلة 1 وتُقفل المراحل الأخرى", "small": true},
		[{"text": "مسح", "style": "danger", "action": _reset_progress}, {"text": "إلغاء", "action": func(): open_page("display")}],
	]


func _reset_progress() -> void:
	Save.reset_progress()
	close()
	main.game.go_to_level(1)
	toast("تم مسح التقدم")


func _credit_rows() -> Array:
	return [
		{"text": "مفاتيح — Mafateeh", "action": _title_tap},
		{"text": "عبودين قيمز — Aboden Games", "small": true},
		{"text": "ترخيص MIT · © Aboden Games", "small": true},
		{"text": "Godot Engine (MIT) · OpenXR Vendors (MIT)", "small": true},
		{"text": "Godot Meta Toolkit (MIT) · Meta Platform SDK", "small": true},
		{"text": "OpenXR Loader (Apache-2.0) · Meta OpenXR SDK", "small": true},
		{"text": "Cairo font (SIL OFL 1.1)", "small": true},
		{"text": "الأصوات والنماذج أصلية ضمن المشروع", "small": true},
		{"text": "التفاصيل الكاملة في ملفات التراخيص", "small": true},
		{"text": "رجوع", "action": func(): open_page("main")},
	]


static func _time_ar(t: String) -> String:
	return {"dawn": "فجر", "day": "نهار", "sunset": "غروب", "night": "ليل"}.get(t, t)


func _title_tap() -> void:
	_title_taps += 1
	if _title_taps >= 7:
		_title_taps = 0
		Save.dev_enabled = not Save.dev_enabled
		Save.save()
		toast("أدوات المطوّر: " + ("مفعّلة" if Save.dev_enabled else "معطّلة"))


func _changed() -> void:
	Save.save()
	main.audio.apply_volume()
	_rebuild()


func _volume(which: String, delta: float) -> void:
	var v: float = {"master": Save.master_volume, "sfx": Save.sfx_volume, "ambience": Save.ambience_volume}[which]
	v = clampf(snappedf(v + delta, 0.1), 0.0, 1.0)
	match which:
		"master": Save.master_volume = v
		"sfx": Save.sfx_volume = v
		"ambience": Save.ambience_volume = v
	_changed()


# --- pointer -----------------------------------------------------------------------------

func _hit(o: Vector3, d: Vector3) -> Dictionary:
	if not _open:
		return {}
	var inv := panel.global_transform.affine_inverse()
	var lo := inv * o
	var ld := inv.basis * d
	if absf(ld.z) < 1e-6:
		return {}
	var t := -lo.z / ld.z
	if t < 0.0:
		return {}
	var p := lo + ld * t
	var size := Vector2(WIDTH + 0.02, 1.0)
	var hit := {"point": panel.global_transform * p, "interactive": false, "local": Vector2(p.x, p.y)}
	for b in buttons:
		if b.rect.has_point(Vector2(p.x, p.y)):
			hit.interactive = true
			hit["button"] = b
	if absf(p.x) > size.x / 2.0 and not hit.interactive:
		return {}
	return hit


func ray_hit(o: Vector3, d: Vector3):
	var h := _hit(o, d)
	_apply_hover(h.get("button"))
	return null if h.is_empty() else h


func _apply_hover(hovered) -> void:
	for b in buttons:
		b.mesh.material_override = _btn_hover if hovered == b else b.base
	if _info:
		var text: String = hovered.hover if hovered != null and hovered.hover != "" else _info_default
		_info.text = text


func handle_ray(o: Vector3, d: Vector3) -> bool:
	if not _open:
		return false
	var h := _hit(o, d)
	if h.has("button"):
		main.audio.ui("click")
		h.button.action.call()
	return true  # while open, the panel owns the trigger


## Test/automation helper: press the first button whose label contains text.
func press(text: String) -> bool:
	for c in panel.get_children():
		if c is Label3D and c.text.contains(text):
			for b in buttons:
				if b.rect.has_point(Vector2(c.position.x, c.position.y)):
					b.action.call()
					return true
	return false


func toast(text: String, seconds := 4.0) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_t = seconds
	if main.xr:
		var head: Transform3D = main.rig.head_transform()
		var fwd := -head.basis.z
		fwd.y = 0
		fwd = fwd.normalized() if fwd.length_squared() > 0.01 else Vector3.FORWARD
		_toast.global_position = head.origin + fwd * 0.7 + Vector3(0, -0.22, 0)
		_toast.look_at(head.origin, Vector3.UP, true)


func notify_placement(source: String) -> void:
	match source:
		"detected_table":
			toast("وُضعت اللوحة على طاولة مكتشفة")
		"detected_floor":
			toast("وُضعت اللوحة على الأرضية المكتشفة")
		"manual":
			toast("وضع يدوي — اضغط المقبض مطولًا لتحريك اللوحة")
		_:
			if main.xr and main.rig.mode == "mr":
				toast("وضع يدوي — اضغط المقبض مطولًا لتحريك اللوحة")


func _show_card(n: int) -> void:
	var d := LevelData.get_level(n)
	_card.text = "%d  ·  %s" % [n, d.title_ar]
	_card.position = Vector3(-0.5, LevelData.exit_y(d) + 2.6, -3.3)
	_card.visible = true
	_card_t = 3.0


func show_credits() -> void:
	var head: Transform3D = main.rig.head_transform() if main.xr else Transform3D()
	if not _open:
		toggle(head)
	open_page("credits")


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
		_toast.visible = _toast_t > 0.0
	if _card_t > 0.0:
		_card_t -= delta
		_card.modulate.a = clampf(_card_t, 0.0, 1.0)
		_card.outline_modulate.a = _card.modulate.a * 0.9
		_card.visible = _card_t > 0.0
