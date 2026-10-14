class_name SettingsMenu
extends Node3D
## The game's floating panel: start screen, pause menu, level list, hints and
## settings. Styled after Diriyah: dark mud-brown board, gold frame and a row of
## Najdi crenellations along the top, with an icon on every action (a Najdi door
## for levels, a lantern for hints, a watchtower for "about", a palm for VR).
## Nothing is shown during play except a short level card and brief notices.
##
## Pages: start (studio name + mixed reality / VR choice), main, levels (cards with
## a picture of every level; reached ones replayable), hint, settings in four tabs
## (sound, controls, display, atmosphere), reset confirmation, about, privacy.
## Developer tools (all levels, time/weather overrides) appear only when enabled:
## project setting mafateeh/dev/level_select, or tapping the title on the about
## page seven times.

const ROW := 0.05
const HEADER := 0.064
const PIXEL := 0.00044
const GRID_COLS := 7
const SETTINGS_TABS := ["audio", "controls", "display", "atmosphere"]
const ICON_DIR := "res://assets/ui/icons/"
const THUMB_DIR := "res://assets/ui/levels/"
const GOLD := Color(0.86, 0.68, 0.36)
const CREAM := Color("fff4e0")

var main: Node
var panel: Node3D
var buttons: Array = []  # {rect, action, mesh, base, hover}
var width := 0.42
var _open := false
var _page := "main"
var _font: FontFile
var _btn_mat: StandardMaterial3D
var _btn_hover: StandardMaterial3D
var _bg_mat: StandardMaterial3D
var _band_mat: StandardMaterial3D
var _gold_mat: StandardMaterial3D
var _styles := {}
var _tex_mats := {}
var _toast: Label3D
var _toast_t := 0.0
var _card: Label3D
var _card_t := 0.0
var _title_taps := 0
var _info: Label3D
var _info_default := ""
var _sting: AudioStreamPlayer


func setup(m: Node) -> void:
	main = m
	_font = load("res://assets/fonts/cairo-arabic-700-normal.woff2") as FontFile
	if _font:
		var latin := load("res://assets/fonts/cairo-latin-700-normal.woff2") as FontFile
		if latin:
			_font.fallbacks = [latin]
	_bg_mat = _flat(Color(0.12, 0.085, 0.06, 0.95))
	_bg_mat.render_priority = -2  # translucent backdrop sorts behind everything on it
	_band_mat = _flat(Color(0.2, 0.135, 0.085, 0.97))
	_band_mat.render_priority = -1
	_gold_mat = _flat(GOLD)
	_btn_mat = _flat(Color(0.33, 0.22, 0.14, 1.0))
	_btn_hover = _flat(Color(0.72, 0.52, 0.27, 1.0))
	_styles = {
		"done": _flat(Color(0.3, 0.38, 0.2, 1.0)),
		"current": _flat(Color(0.74, 0.55, 0.26, 1.0)),
		"locked": _flat(Color(0.18, 0.13, 0.1, 1.0)),
		"tab_on": _flat(Color(0.58, 0.41, 0.22, 1.0)),
		"danger": _flat(Color(0.5, 0.17, 0.12, 1.0)),
		"primary": _flat(Color(0.62, 0.43, 0.21, 1.0)),
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
	_sting = AudioStreamPlayer.new()
	_sting.stream = load("res://audio/sfx/intro_sting.wav")
	_sting.volume_db = -3.0
	add_child(_sting)
	main.game.level_loaded.connect(_show_card)
	main.game.level_loaded.connect(func(_n): if _open: _rebuild())


static func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## Unshaded textured material (icons, thumbnails), cached per texture and tint.
func _tex_mat(path: String, tint := Color.WHITE, alpha := true) -> StandardMaterial3D:
	var key := "%s|%s" % [path, tint.to_html()]
	if _tex_mats.has(key):
		return _tex_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = load(path)
	m.albedo_color = tint
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.render_priority = 1
	_tex_mats[key] = m
	return m


func _label(text: String, pixel: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = pixel
	l.font_size = 48
	l.outline_size = 10
	l.outline_modulate = Color(0.08, 0.05, 0.03, 0.9)
	l.modulate = CREAM
	if _font:
		l.font = _font
	l.no_depth_test = false
	l.render_priority = 2
	l.double_sided = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_direction = TextServer.DIRECTION_AUTO
	return l


func _quad(size: Vector2, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	panel.add_child(mi)
	return mi


func is_open() -> bool:
	return _open


func page() -> String:
	return _page


func _place(head: Transform3D, distance: float, drop: float) -> void:
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.01 else Vector3.FORWARD
	panel.global_position = head.origin + fwd * distance + Vector3(0, -drop, 0)
	panel.look_at(head.origin, Vector3.UP, true)


func toggle(head: Transform3D) -> void:
	if _page == "start" and _open:
		return  # the start screen stays until a mode is chosen
	if _open:
		close()
		return
	_open = true
	_page = "main"
	_place(head, 0.5, 0.1)
	_rebuild()
	panel.visible = true
	main.audio.ui("open")
	if main.game.motor:
		main.game.motor.cancel()


## Studio name at launch: «عبودين قيمز / ABODEN GAMES» in plain white, floating
## in front of the player with no frame or background, held long enough to read
## (fade in, hold, fade out), with the oud sting. Then `done` runs.
const SPLASH_IN := 0.7
const SPLASH_HOLD := 3.0
const SPLASH_OUT := 0.7
var splash: Node3D


func play_splash(head: Transform3D, done: Callable) -> void:
	if splash:
		return  # already showing
	splash = Node3D.new()
	splash.name = "StudioSplash"
	add_child(splash)
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.01 else Vector3.FORWARD
	splash.global_position = head.origin + fwd * 1.4
	splash.look_at(head.origin, Vector3.UP, true)
	var ar := _label("عبودين قيمز", 0.0011)
	ar.font_size = 96
	var en := _label("ABODEN GAMES", 0.0011)
	en.font_size = 40
	en.position.y = -0.11
	for l in [ar, en]:
		l.outline_size = 0
		l.modulate = Color(1, 1, 1, 0)
		splash.add_child(l)
	if not Save.muted:
		_sting.play()
	var tw := create_tween()
	tw.tween_property(ar, "modulate:a", 1.0, SPLASH_IN)
	tw.parallel().tween_property(en, "modulate:a", 0.9, SPLASH_IN)
	tw.tween_interval(SPLASH_HOLD)
	tw.tween_property(ar, "modulate:a", 0.0, SPLASH_OUT)
	tw.parallel().tween_property(en, "modulate:a", 0.0, SPLASH_OUT)
	tw.tween_callback(func():
		splash.queue_free()
		splash = null
		done.call())


## Start screen: the studio name, the game title and the choice of mixed or
## virtual reality. Shown once per launch, before the board appears.
func open_start(head: Transform3D, sting := true) -> void:
	var was_open := _open and _page == "start"
	_open = true
	_page = "start"
	_place(head, 0.75, 0.02)
	if not was_open:
		_rebuild()
	panel.visible = true
	if sting and not was_open and not Save.muted:
		_sting.play()


func close() -> void:
	_open = false
	panel.visible = false
	main.audio.ui("close")


func open_page(p: String) -> void:
	_page = p
	_rebuild()


# --- layout ------------------------------------------------------------------------------

func _page_width() -> float:
	match _page:
		"levels": return 0.52
		"start": return 0.58
		"audio", "controls", "display", "atmosphere": return 0.54
	return 0.44


func _rebuild() -> void:
	for c in panel.get_children():
		c.queue_free()
	buttons.clear()
	_info = null
	width = _page_width()
	var rows: Array = []
	match _page:
		"start": rows = _start_rows()
		"levels": rows = _level_rows()
		"hint": rows = _hint_rows()
		"audio", "controls", "display", "atmosphere": rows = _settings_rows()
		"reset": rows = _reset_rows()
		"credits": rows = _credit_rows()
		"privacy": rows = _privacy_rows()
		_: rows = _main_rows()
	var heights: Array = []
	var height := 0.045  # top margin under the crenellations + bottom margin
	for i in rows.size():
		var items: Array = rows[i] if rows[i] is Array else [rows[i]]
		var h := HEADER if i == 0 else ROW
		for it in items:
			h = maxf(h, float(it.get("h", 0.0)))
		heights.append(h)
		height += h
	_frame(height)
	var y := height / 2.0 - 0.03
	for i in rows.size():
		var items: Array = rows[i] if rows[i] is Array else [rows[i]]
		var h: float = heights[i]
		var total := 0.0
		for it in items:
			total += it.get("w", 1.0)
		var x := -width / 2.0
		for it in items:
			var w: float = width * it.get("w", 1.0) / total
			var center := Vector2(x + w / 2.0, y - h / 2.0)
			_item(it, center, Vector2(w, h), i == 0)
			x += w
		y -= h


## Board, gold frame, header band and the crenellated top edge.
func _frame(height: float) -> void:
	var w := width + 0.024
	_quad(Vector2(w, height), _bg_mat, Vector3(0, 0, -0.003))
	_quad(Vector2(w, HEADER + 0.012), _band_mat, Vector3(0, height / 2.0 - 0.012 - HEADER / 2.0, -0.002))
	var t := 0.0025
	_quad(Vector2(w, t), _gold_mat, Vector3(0, height / 2.0, -0.001))
	_quad(Vector2(w, t), _gold_mat, Vector3(0, -height / 2.0, -0.001))
	_quad(Vector2(t, height), _gold_mat, Vector3(-w / 2.0, 0, -0.001))
	_quad(Vector2(t, height), _gold_mat, Vector3(w / 2.0, 0, -0.001))
	_quad(Vector2(w - 0.02, t * 0.6), _gold_mat, Vector3(0, height / 2.0 - 0.018 - HEADER, -0.001))
	# Najdi crenellations standing on the top edge (tiled strip texture).
	var cren := _quad(Vector2(w, 0.022), _cren_mat(w), Vector3(0, height / 2.0 + 0.011, -0.002))
	cren.name = "Crenellations"


func _cren_mat(w: float) -> StandardMaterial3D:
	var m := _tex_mat(ICON_DIR + "crenellation.png", Color(0.2, 0.135, 0.085)).duplicate() as StandardMaterial3D
	m.uv1_scale = Vector3(w / 0.176, 1, 1)  # one 8-tooth strip every 17.6 cm
	m.texture_repeat = true
	m.render_priority = -1
	return m


func _item(it: Dictionary, center: Vector2, size: Vector2, header: bool) -> void:
	var kind: String = it.get("kind", "")
	if kind == "card":
		_card_item(it, center, size)
		return
	if kind == "image":
		var tex: Texture2D = load(it.path)
		var ih: float = size.y * 0.92
		var iw := ih * float(tex.get_width()) / float(tex.get_height())
		_quad(Vector2(iw, ih), _tex_mat(it.path), Vector3(center.x, center.y, 0.001))
		return
	var styled: bool = it.has("action") or it.has("style")
	if styled:
		var base: Material = _styles.get(it.get("style", ""), _btn_mat)
		var m := _quad(Vector2(size.x - 0.008, size.y - 0.01), base, Vector3(center.x, center.y, 0))
		if it.has("action"):
			buttons.append({"rect": Rect2(center - size / 2.0, size), "action": it.action, "mesh": m,
				"base": base, "hover": it.get("hover", "")})
	var text_center := center.x
	if it.has("icon"):
		var isz := minf(size.y * 0.62, (0.032 if not it.get("big", false) else 0.05) * (0.8 if it.get("small", false) else 1.0))
		var only_icon: bool = it.get("text", "") == ""
		var ix := center.x if only_icon else (center.x + size.x / 2.0 - isz * 0.9 if Save.arabic() else center.x - size.x / 2.0 + isz * 0.9)
		var tint: Color = CREAM if it.get("style", "") != "locked" else Color(1, 0.95, 0.85, 0.4)
		var iq := _quad(Vector2(isz, isz), _tex_mat(ICON_DIR + it.icon + ".png", tint), Vector3(ix, center.y, 0.001))
		if it.icon == "back" and Save.arabic():
			iq.scale.x = -1.0  # "back" points right when reading right to left
		if not only_icon:
			text_center += (-isz * 0.55 if Save.arabic() else isz * 0.55)
	if kind == "body":
		var b := _label(it.text, PIXEL * 0.82)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.width = (size.x - 0.04) / (PIXEL * 0.82)
		b.position = Vector3(center.x, center.y, 0.002)
		panel.add_child(b)
		return
	if it.get("text", "") == "":
		return
	var scale := 1.0
	if header:
		scale = 1.12
	elif it.get("small", false):
		scale = 0.8
	elif it.get("big", false):
		scale = 1.15
	var l := _label(it.text, PIXEL * scale)
	if header:
		l.modulate = Color("ffe4b0")
	if it.get("style", "") == "locked":
		l.modulate = Color(1.0, 0.96, 0.88, 0.45)
	l.position = Vector3(text_center, center.y, 0.002)
	panel.add_child(l)
	if it.get("info", false):
		_info = l
		_info_default = it.text


## A level card: picture of the level, number, and a badge (done / locked).
func _card_item(it: Dictionary, center: Vector2, size: Vector2) -> void:
	var n: int = it.n
	var style: String = it.get("style", "")
	var base: Material = _styles.get(style, _btn_mat)
	var m := _quad(Vector2(size.x - 0.006, size.y - 0.006), base, Vector3(center.x, center.y, 0))
	if it.has("action"):
		buttons.append({"rect": Rect2(center - size / 2.0, size), "action": it.action, "mesh": m,
			"base": base, "hover": it.get("hover", "")})
	var tw := size.x - 0.014
	var th := tw * 9.0 / 16.0
	var path := THUMB_DIR + "level_%02d.jpg" % n
	var locked := style == "locked"
	if ResourceLoader.exists(path):
		var tint := Color(0.35, 0.3, 0.27) if locked else Color.WHITE
		_quad(Vector2(tw, th), _tex_mat(path, tint, false), Vector3(center.x, center.y + size.y / 2.0 - th / 2.0 - 0.006, 0.001))
	var l := _label(str(n), PIXEL * 0.9)
	l.position = Vector3(center.x, center.y - size.y / 2.0 + 0.013, 0.002)
	if locked:
		l.modulate = Color(1, 0.95, 0.85, 0.5)
	panel.add_child(l)
	# Best stars for the level, and a green star when its secret gem was found.
	if Save.stars.has(n) and not locked:
		var sz := 0.014
		for k in 3:
			var lit: bool = k < int(Save.stars[n])
			_quad(Vector2(sz, sz), _tex_mat(ICON_DIR + "star.png", Color("f2c14e") if lit else Color(1, 0.95, 0.85, 0.25)),
				Vector3(center.x + (k - 1) * sz * 1.15 + (size.x * 0.28 if Save.arabic() else -size.x * 0.28), center.y - size.y / 2.0 + 0.013, 0.003))
	if Save.secrets.has(n) and not locked:
		var gz := 0.013
		_quad(Vector2(gz, gz), _tex_mat(ICON_DIR + "star.png", Color("7fe0ad")),
			Vector3(center.x - size.x / 2.0 + gz, center.y + size.y / 2.0 - gz, 0.003))
	var badge := "lock" if locked else ("check" if it.get("done", false) else "")
	if badge != "":
		var bz := 0.018
		_quad(Vector2(bz, bz), _tex_mat(ICON_DIR + badge + ".png", CREAM if badge == "lock" else Color("c9f2a6")),
			Vector3(center.x + size.x / 2.0 - bz, center.y + size.y / 2.0 - bz, 0.003))


static func _pct(v: float) -> String:
	return Save.text("%d٪", "%d%%") % roundi(v * 100)


# --- pages -----------------------------------------------------------------------------

func _start_rows() -> Array:
	return [
		{"kind": "image", "path": "res://assets/brand/aboden_wordmark.png", "h": 0.12},
		{"text": "مفاتيح — Mafateeh", "big": true, "h": 0.06},
		{"text": T("اختر طريقة اللعب", "Choose how to play"), "small": true},
		_dir([{"text": T("الواقع المختلط", "Mixed reality"), "icon": "mr", "big": true, "h": 0.085, "style": "primary",
				"action": func(): main.start_game("mr")},
			{"text": T("الواقع الافتراضي", "Virtual reality"), "icon": "vr", "big": true, "h": 0.085, "style": "primary",
				"action": func(): main.start_game("vr")}]),
		{"text": T("اللعبة على طاولتك في غرفتك، أو في الدرعية بين النخيل", "The board on your own table, or in Diriyah among the palms"), "small": true},
		{"text": T("English", "العربية"), "icon": "language", "small": true, "w": 1.0, "action": _toggle_language},
	]


func _main_rows() -> Array:
	var lvl: int = main.game.target_level()
	var d := LevelData.get_level(lvl)
	var prev := _neighbour(lvl, -1)
	var next := _neighbour(lvl, 1)
	var g: Game = main.game
	var moves_line := T("الحركات %d", "Moves %d") % g.moves
	if g.par() > 0:
		moves_line += T("  ·  المثالي %d", "  ·  best %d") % g.par()
	var rows: Array = [
		{"text": T("المرحلة %d — %s", "Level %d — %s") % [lvl, _title(d)]},
		{"text": moves_line, "small": true},
		{"text": T("متابعة", "Resume"), "icon": "play", "style": "primary", "action": close},
		_dir([{"text": T("تراجع خطوة", "Undo step"), "icon": "back", "style": "" if g.can_undo() else "locked",
				"action": func(): if g.undo(): _rebuild()},
			{"text": T("إعادة المرحلة", "Restart level"), "icon": "restart", "action": func(): close(); main.game.restart()},
			{"text": T("تلميح", "Hint"), "icon": "hint", "action": func(): open_page("hint")}]),
		# Reading order: previous first (on the right in Arabic, on the left in English).
		_dir([_nav_item(T("السابقة", "Previous"), prev, "next" if Save.arabic() else "prev"),
			{"text": T("المراحل", "Levels"), "icon": "levels", "w": 1.3, "action": func(): open_page("levels")},
			_nav_item(T("التالية", "Next"), next, "prev" if Save.arabic() else "next")]),
		_dir([{"text": T("الإعدادات", "Settings"), "icon": "settings", "action": func(): open_page("audio")},
			{"text": T("حول اللعبة", "About"), "icon": "about", "action": func(): open_page("credits")}]),
	]
	if Save.dev_tools_available():
		var sky: SkyWeather = main.sky
		rows.append({"text": T("— أدوات المطوّر —", "— Developer tools —"), "small": true})
		rows.append([{"text": T("الوقت: ", "Time: ") + _time_name(sky.time_name), "action": func(): sky.cycle_time(); Save.dev_time = sky.time_name; _rebuild()},
			{"text": T("الطقس: ", "Weather: ") + (T("مطر", "rain") if sky.raining else T("صافٍ", "clear")), "action": func(): sky.toggle_rain(); Save.dev_weather = "rain" if sky.raining else "clear"; _rebuild()}])
	return rows


func _nav_item(text: String, target: int, icon: String) -> Dictionary:
	if target < 1:
		return {"text": text, "icon": icon, "w": 0.9, "style": "locked", "small": true}
	return {"text": text, "icon": icon, "w": 0.9, "small": true, "action": func(): play_level(target)}


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


## Hints come in three steps: the idea, the first move, then the whole way. Each
## step is revealed only when asked for, so the player keeps as much as they want.
func _hint_rows() -> Array:
	var lvl: int = main.game.target_level()
	var g: Game = main.game
	var tier := clampi(g.hint_tier, 1, LevelHints.TIERS)
	var names := [T("الفكرة", "The idea"), T("الخطوة الأولى", "First step"), T("الحل كاملًا", "Full solution")]
	var rows: Array = [{"text": T("تلميح — المرحلة %d", "Hint — level %d") % lvl}]
	for i in range(1, tier + 1):
		rows.append({"text": "%d · %s" % [i, names[i - 1]], "small": true})
		rows.append({"kind": "body", "text": LevelHints.text(lvl, i), "h": 0.1})
	var foot: Array = [{"text": T("رجوع", "Back"), "icon": "back", "action": func(): open_page("main")}]
	if tier < LevelHints.TIERS:
		foot.append({"text": names[tier], "icon": "hint", "action": func(): g.hint_tier = tier + 1; _rebuild()})
	foot.append({"text": T("متابعة", "Resume"), "icon": "play", "style": "primary", "action": close})
	rows.append(_dir(foot))
	return rows


func _level_rows() -> Array:
	var cur: int = main.game.target_level()
	var done := 0
	for n in range(1, LevelData.COUNT + 1):
		if Save.is_completed(n):
			done += 1
	var rows: Array = [
		{"text": T("المراحل  ·  أنجزت %d من %d", "Levels  ·  %d of %d complete") % [done, LevelData.COUNT], "icon": "levels"},
		{"text": _level_info(cur), "small": true, "info": true},
	]
	var n := 1
	while n <= LevelData.COUNT:
		var row: Array = []
		for c in GRID_COLS:
			if n <= LevelData.COUNT:
				row.append(_level_cell(n, cur))
			n += 1
		rows.append(_dir(row))  # level 1 starts on the right in Arabic, on the left in English
	rows.append({"text": T("رجوع", "Back"), "icon": "back", "action": func(): open_page("main")})
	return rows


func _level_cell(n: int, cur: int) -> Dictionary:
	var it := {"kind": "card", "n": n, "text": str(n), "h": 0.07, "done": Save.is_completed(n), "hover": _level_info(n)}
	if not Save.can_play(n):
		it["style"] = "locked"
		return it
	if n == cur:
		it["style"] = "current"
	elif Save.is_completed(n):
		it["style"] = "done"
	it["action"] = func(): close(); play_level(n)
	return it


static func _level_info(n: int) -> String:
	var d := LevelData.get_level(n)
	var state := T("مكتملة", "complete") if Save.is_completed(n) else (T("مقفلة", "locked") if not Save.can_play(n) else T("لم تكتمل بعد", "not complete yet"))
	if Save.stars.has(n):
		state += T("  ·  %d من 3 نجوم", "  ·  %d of 3 stars") % int(Save.stars[n])
	return "%d — %s  ·  %s" % [n, _title(d), state]


func _tabs() -> Array:
	var names := {"audio": T("الصوت", "Sound"), "controls": T("التحكم", "Controls"),
		"display": T("العرض", "Display"), "atmosphere": T("الأجواء", "Atmosphere")}
	var icons := {"audio": "sound", "controls": "controls", "display": "display", "atmosphere": "atmosphere"}
	var row: Array = []
	for t in SETTINGS_TABS:
		var it := {"text": names[t], "icon": icons[t], "small": true, "action": func(): open_page(t)}
		if t == _page:
			it["style"] = "tab_on"
		row.append(it)
	return _dir(row)


func _stepper(text: String, minus: Callable, plus: Callable) -> Array:
	return [{"text": "−", "w": 0.5, "action": minus}, {"text": text, "w": 1.8}, {"text": "+", "w": 0.5, "action": plus}]


func _settings_rows() -> Array:
	var rows: Array = [{"text": T("الإعدادات", "Settings"), "icon": "settings"}, _tabs()]
	match _page:
		"audio":
			rows.append(_stepper(T("الصوت العام ", "Master ") + _pct(Save.master_volume), func(): _volume("master", -0.1), func(): _volume("master", 0.1)))
			rows.append(_stepper(T("المؤثرات ", "Effects ") + _pct(Save.sfx_volume), func(): _volume("sfx", -0.1), func(): _volume("sfx", 0.1)))
			rows.append(_stepper(T("الأجواء والمطر ", "Ambience and rain ") + _pct(Save.ambience_volume), func(): _volume("ambience", -0.1), func(): _volume("ambience", 0.1)))
			rows.append({"text": T("إلغاء الكتم", "Unmute") if Save.muted else T("كتم الصوت", "Mute"), "icon": "sound", "action": func(): Save.muted = not Save.muted; _changed()})
		"controls":
			rows.append({"text": T("التدوير: ", "Turning: ") + (T("متدرّج 30°", "30° steps") if Save.turn_mode == "snap" else T("سلس", "smooth")),
				"action": func(): Save.turn_mode = "smooth" if Save.turn_mode == "snap" else "snap"; _changed()})
			rows.append({"text": T("سرعة التدوير: ", "Turn speed: ") + [T("بطيئة", "slow"), T("عادية", "normal"), T("سريعة", "fast")][Save.turn_speed],
				"action": func(): Save.turn_speed = (Save.turn_speed + 1) % 3; _changed()})
			rows.append({"text": T("يد الحركة: ", "Movement hand: ") + (T("اليسرى", "left") if Save.left_handed else T("اليمنى", "right")),
				"action": func(): Save.left_handed = not Save.left_handed; _changed()})
			rows.append({"text": T("الاهتزاز: ", "Vibration: ") + (T("يعمل", "on") if Save.haptics else T("متوقف", "off")),
				"action": func(): Save.haptics = not Save.haptics; _changed(); main.pulse_ui()})
			rows.append({"text": T("إظهار إرشادات التحكم", "Show controller hints"), "icon": "controls", "action": func(): close(); main.show_controller_hints()})
		"display":
			rows.append({"text": T("الوضع: ", "Mode: ") + (T("الواقع المختلط", "mixed reality") if Save.mode == "mr" else T("الواقع الافتراضي", "virtual reality")),
				"icon": "mr" if Save.mode == "mr" else "vr", "action": func(): main.set_mode("vr" if Save.mode == "mr" else "mr"); _rebuild()})
			rows.append(_dir([{"text": T("إعادة تموضع اللوحة", "Re-place board"), "icon": "board", "small": true, "action": func(): close(); main._on_grip_tap("menu")},
				{"text": T("حجم اللوحة الافتراضي", "Default board size"), "small": true, "action": func(): main.reset_board_size()}]))
			rows.append(_dir([{"text": T("اللغة: العربية", "Language: English"), "icon": "language", "action": _toggle_language},
				{"text": T("الجودة: ", "Graphics: ") + (T("عالية", "high") if Save.quality == "high" else T("متوازنة", "balanced")), "icon": "quality",
					"action": func(): Save.quality = "balanced" if Save.quality == "high" else "high"; _changed(); main.apply_quality()}]))
			rows.append({"text": T("مسح التقدم…", "Reset progress…"), "icon": "reset", "style": "danger", "action": func(): open_page("reset")})
		"atmosphere":
			rows.append({"text": T("دورة اليوم: ", "Day cycle: ") + (T("تلقائية", "automatic") if Save.day_cycle else T("ثابتة حسب المرحلة", "fixed per level")),
				"icon": "atmosphere", "action": func(): Save.day_cycle = not Save.day_cycle; _changed(); main.apply_sky()})
			var wnames := {"cycle": T("أمطار متقطعة تلقائية", "passing showers"), "level": T("حسب المرحلة", "per level"), "clear": T("صافٍ دائمًا", "always clear")}
			rows.append({"text": T("الطقس: ", "Weather: ") + wnames[Save.weather_pref],
				"action": _cycle_weather})
			rows.append({"text": T("الغبار الخفيف: ", "Light dust: ") + (T("يعمل", "on") if Save.dust else T("متوقف", "off")),
				"action": func(): Save.dust = not Save.dust; _changed()})
			rows.append({"text": T("الأجواء بصرية فقط ولا تغيّر حل أي لغز", "Atmosphere is visual only and never changes a solution"), "small": true})
	rows.append({"text": T("رجوع", "Back"), "icon": "back", "action": func(): open_page("main")})
	return rows


func _cycle_weather() -> void:
	var order := ["cycle", "level", "clear"]
	Save.weather_pref = order[(order.find(Save.weather_pref) + 1) % order.size()]
	_changed()
	main.apply_sky()


func _reset_rows() -> Array:
	return [
		{"text": T("مسح كل التقدم؟", "Reset all progress?"), "icon": "reset"},
		{"text": T("تعود إلى المرحلة 1 وتُقفل المراحل الأخرى", "You return to level 1 and the other levels lock"), "small": true},
		_dir([{"text": T("إلغاء", "Cancel"), "action": func(): open_page("display")}, {"text": T("مسح", "Reset"), "style": "danger", "action": _reset_progress}]),
	]


func _reset_progress() -> void:
	Save.reset_progress()
	close()
	main.game.go_to_level(1)
	toast(T("تم مسح التقدم", "Progress reset"))


func _credit_rows() -> Array:
	return [
		{"text": "مفاتيح — Mafateeh", "icon": "about", "action": _title_tap},
		{"text": T("عبودين قيمز — Aboden Games", "Aboden Games — عبودين قيمز"), "small": true},
		{"text": T("ترخيص MIT · © Aboden Games", "MIT license · © Aboden Games"), "small": true},
		{"text": "Godot Engine (MIT) · OpenXR Vendors (MIT)", "small": true},
		{"text": "Godot Meta Toolkit (MIT) · Meta Platform SDK", "small": true},
		{"text": "OpenXR Loader (Apache-2.0) · Meta OpenXR SDK", "small": true},
		{"text": "Cairo font (SIL OFL 1.1)", "small": true},
		{"text": T("الأصوات والنماذج أصلية ضمن المشروع", "Sounds and models are original to the project"), "small": true},
		_dir([{"text": T("رجوع", "Back"), "icon": "back", "action": func(): open_page("main")},
			{"text": T("سياسة الخصوصية", "Privacy policy"), "icon": "privacy", "action": func(): open_page("privacy")}]),
	]


## Short in-game version of PRIVACY.md (the full text is linked from the store page).
func _privacy_rows() -> Array:
	return [
		{"text": T("سياسة الخصوصية", "Privacy policy"), "icon": "privacy"},
		{"text": T("لا تجمع اللعبة أي بيانات شخصية", "The game collects no personal data"), "small": true},
		{"text": T("لا إعلانات ولا تحليلات ولا حسابات", "No ads, no analytics, no accounts"), "small": true},
		{"text": T("اللعبة نفسها لا تتصل بالإنترنت", "The game itself does not go online"), "small": true},
		{"text": T("التقدّم والإعدادات محفوظة على النظارة فقط", "Progress and settings stay on this headset"), "small": true},
		{"text": T("بيانات المساحة للّعب فقط ولا تُحفظ ولا تُرسل", "Space data is used to play, never stored or sent"), "small": true},
		{"text": T("تحقّق ملكية النسخة من المتجر تديره Meta", "Store ownership check is handled by Meta"), "small": true},
		{"text": T("النص الكامل: github.com/3wasfnjd/Mafateeh", "Full text: github.com/3wasfnjd/Mafateeh"), "small": true},
		{"text": T("رجوع", "Back"), "icon": "back", "action": func(): open_page("credits")},
	]


static func _time_name(t: String) -> String:
	return {"dawn": T("فجر", "dawn"), "day": T("نهار", "day"), "sunset": T("غروب", "sunset"), "night": T("ليل", "night")}.get(t, t)


static func T(ar: String, en: String) -> String:
	return Save.text(ar, en)


static func _title(d: Dictionary) -> String:
	return d.title_ar if Save.arabic() else d.title_en


## Rows are laid out left to right; Arabic reads right to left.
static func _dir(row: Array) -> Array:
	var r := row.duplicate()
	if Save.arabic():
		r.reverse()
	return r


func _toggle_language() -> void:
	Save.language = "en" if Save.arabic() else "ar"
	Save.save()
	_rebuild()
	if main.game.level > 0:
		_show_card(main.game.level)
	main.refresh_language()


func _title_tap() -> void:
	_title_taps += 1
	if _title_taps >= 7:
		_title_taps = 0
		Save.dev_enabled = not Save.dev_enabled
		Save.save()
		toast(T("أدوات المطوّر: ", "Developer tools: ") + (T("مفعّلة", "on") if Save.dev_enabled else T("معطّلة", "off")))


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
	var hit := {"point": panel.global_transform * p, "interactive": false, "local": Vector2(p.x, p.y)}
	for b in buttons:
		if b.rect.has_point(Vector2(p.x, p.y)):
			hit.interactive = true
			hit["button"] = b
	if absf(p.x) > (width + 0.024) / 2.0 and not hit.interactive:
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
			toast(T("وُضعت اللوحة على طاولة مكتشفة", "Board placed on a detected table"))
		"detected_floor":
			toast(T("وُضعت اللوحة على الأرضية المكتشفة", "Board placed on the detected floor"))
		"manual":
			toast(T("وضع يدوي — اضغط المقبض مطولًا لتحريك اللوحة", "Manual placement — hold the grip to move the board"))
		_:
			if main.xr and main.rig.mode == "mr":
				toast(T("وضع يدوي — اضغط المقبض مطولًا لتحريك اللوحة", "Manual placement — hold the grip to move the board"))


func _show_card(n: int) -> void:
	var d := LevelData.get_level(n)
	_card.text = "%d  ·  %s" % [n, _title(d)]
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
