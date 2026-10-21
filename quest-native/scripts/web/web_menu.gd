class_name WebMenu
extends Control
## The menu in the browser, made for a phone's screen (owner, 2026-10-21: «اضبط القائمة بحيث
## تكون مناسبه للجوال»). The same sections and actions as the headset's clay plaque (TableMenu),
## drawn flat in its colours: a sand panel, round brown buttons, the tabs in a row at the top.
## Large touch targets (at least 48 px), the words read right to left in Arabic, and it fits a
## tall phone, a phone on its side and a computer alike. It lives in WebView's screen layer
## (sized in the page's pixels) and table_main listens to the same signals as TableMenu's.

signal play_level(n: int)     # 0: the next level not yet won
signal closed
signal replace_table
signal settings_changed

const SAND := Color("ecd9b8")
const PANEL_EDGE := Color("7a5a3a")
const DISC := TableMenu.DISC
const ACCENT := TableMenu.ACCENT
const ACCENT_DARK := TableMenu.ACCENT_DARK
const PALE := TableMenu.PALE
const FADED := TableMenu.FADED
const GOLD := TableMenu.GOLD
const ICONS := "res://assets/ui/icons/"
const LEVELS := TableMenu.LEVELS

var page := "levels"
var stage := 0                # the level on the table (0: none yet)
var _panel: PanelContainer
var _title: Label
var _tabs: HBoxContainer
var _body: VBoxContainer
var _scroll: ScrollContainer
var _preview_vp: SubViewport
var _preview: Node3D
var _preview_anim: AnimationPlayer
var _spin := 0.0
var _click: AudioStreamPlayer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # nothing under the menu takes a tap
	layout_direction = Control.LAYOUT_DIRECTION_RTL if _arabic() else Control.LAYOUT_DIRECTION_LTR
	var dim := ColorRect.new()
	dim.color = Color(0.18, 0.12, 0.07, 0.35)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = SAND
	sb.border_color = PANEL_EDGE
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(26)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 14
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)
	_tabs = HBoxContainer.new()
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	_tabs.add_theme_constant_override("separation", 6)
	col.add_child(_tabs)
	_title = _label("", 24, ACCENT_DARK)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 14)
	_scroll.add_child(_body)
	_click = AudioStreamPlayer.new()
	_click.stream = load("res://audio/sfx/ui_click.wav")
	_click.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_click.volume_db = -4.0
	add_child(_click)
	resized.connect(_fit)
	open(page)


## The panel's size for the screen: nearly all of a phone's, a column on a computer.
func _fit() -> void:
	var s := size
	var w := minf(s.x - 20.0, 560.0)
	if _low():   # a phone on its side: wide and low
		w = minf(s.x - 20.0, 780.0)
	# as tall as what it holds (up to the screen; more scrolls)
	var need := _body.get_combined_minimum_size().y + _tabs.get_combined_minimum_size().y + 60.0
	if _title.visible:
		need += _title.get_combined_minimum_size().y + 10.0
	var h := minf(s.y - 20.0, maxf(need, 200.0))
	_panel.size = Vector2(w, h)
	_panel.position = (s - _panel.size) * 0.5


## A phone on its side: little height, so the menu packs tighter.
func _low() -> bool:
	var room := (get_parent() as Control).size if get_parent() is Control else size
	return room.x > room.y and room.y < 520.0


func _process(dt: float) -> void:
	if _preview:
		_spin += dt * 0.5
		_preview.rotation.y = _spin


func open(p: String) -> void:
	page = p
	for c in _tabs.get_children():
		c.queue_free()
	for c in _body.get_children():
		c.queue_free()
	_preview = null
	_preview_vp = null
	var tabs: Array = TableMenu.TABS.duplicate()
	if stage > 0:
		tabs.insert(1, ["hint", "hint", "تلميح المرحلة", "A hint for this level"])
		tabs.append(["close", "close", "رجوع للعب", "Back to the game"])
	var title := ""
	for t in tabs:
		var id: String = t[0]
		var on: bool = id == page
		if on:
			title = _say(t[2], t[3])
		_tabs.add_child(_round(t[1], 46, ACCENT if on else DISC, Color.WHITE if on else ACCENT, func(): _tab(id), _say(t[2], t[3])))
	if page == "thanks":
		title = _say("شكراً لأنك جرّبت مفاتيح", "Thank you for playing Mafateeh")
	_title.text = title
	_title.visible = not _low()
	match page:
		"wardrobe": _wardrobe()
		"world": _world()
		"settings": _settings()
		"about": _about()
		"hint": _hint()
		"thanks": _thanks()
		_: _levels()
	_scroll.scroll_vertical = 0
	_fit.call_deferred()


func _tab(id: String) -> void:
	if id == "close":
		closed.emit()
		return
	open(id)


# --- sections ---------------------------------------------------------------------------------

func _levels() -> void:
	var save := _save()
	var grid := GridContainer.new()
	var room := (get_parent() as Control).size if get_parent() is Control else size
	grid.columns = 6 if room.x > room.y and room.x > 640.0 else 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	_body.add_child(_centred(grid))
	for i in LEVELS:
		var n := i + 1
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		var b := _round("", 52 if _low() else 62, ACCENT, Color.WHITE, func(): play_level.emit(n), _say("المرحلة %s" % _digits(n), "Level %d" % n))
		b.text = _digits(n)
		b.add_theme_font_size_override("font_size", 28)
		if stage == n:   # the level on the table: ringed dark
			var st := (b.get_theme_stylebox("normal") as StyleBoxFlat).duplicate() as StyleBoxFlat
			st.border_color = ACCENT_DARK
			st.set_border_width_all(4)
			b.add_theme_stylebox_override("normal", st)
		var holder := Control.new()
		holder.custom_minimum_size = b.custom_minimum_size
		holder.add_child(b)
		if save and save.table_gems.get(n, false):   # its hidden key found
			var key := _icon_rect("key", 22, TableMenu.GEM)
			holder.add_child(key)
			key.position = Vector2(b.custom_minimum_size.x - 16, -4)
		cell.add_child(_centred(holder))
		var stars := HBoxContainer.new()
		stars.alignment = BoxContainer.ALIGNMENT_CENTER
		stars.add_theme_constant_override("separation", 1)
		var got: int = save.table_stars.get(n, 0) if save else 0
		for k in 3:
			stars.add_child(_icon_rect("star", 16, GOLD if k < got else Color(FADED, 0.7)))
		cell.add_child(stars)
		grid.add_child(cell)
	# the totals, and play (or back to the level on the table)
	var tot := 0
	var gems := 0
	if save:
		for k in save.table_stars:
			tot += save.table_stars[k]
		gems = save.table_gems.size()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.add_child(_icon_rect("star", 26, GOLD))
	row.add_child(_label("%s/%s" % [_digits(tot), _digits(LEVELS * 3)], 22, ACCENT_DARK))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(18, 1)
	row.add_child(gap)
	row.add_child(_icon_rect("key", 28, TableMenu.GEM))
	row.add_child(_label("%s/%s" % [_digits(gems), _digits(LEVELS)], 22, ACCENT_DARK))
	var go := _wide("play", _say("رجوع للعب", "Back to the game"), func(): closed.emit()) if stage > 0 \
		else _wide("play", _say("العب", "Play"), func(): play_level.emit(0))
	if _low():   # on its side: the totals and the button on one line
		var gap2 := Control.new()
		gap2.custom_minimum_size = Vector2(24, 1)
		row.add_child(gap2)
		row.add_child(go)
		_body.add_child(row)
	else:
		_body.add_child(row)
		_body.add_child(_centred(go))


func _wardrobe() -> void:
	var save := _save()
	# the old man turning on his stand, in his own little view
	var box := SubViewportContainer.new()
	box.stretch = true
	box.custom_minimum_size = Vector2(170, 200)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_vp = SubViewport.new()
	_preview_vp.own_world_3d = true
	_preview_vp.transparent_bg = true
	_preview_vp.msaa_3d = Viewport.MSAA_4X
	box.add_child(_preview_vp)
	var cam := Camera3D.new()
	cam.fov = 26
	cam.position = Vector3(0, 0.3, 0.95)
	cam.rotation_degrees = Vector3(-4, 0, 0)
	_preview_vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	_preview_vp.add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff6ea")
	env.ambient_light_energy = 0.7
	we.environment = env
	_preview_vp.add_child(we)
	var ps := load(Diorama.SHAIB) as PackedScene
	if ps:
		_preview = ps.instantiate()
		_preview_vp.add_child(_preview)
		_preview.scale = Vector3.ONE * 0.36
		_preview.rotation.y = _spin
		var aps := _preview.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			_preview_anim = aps[0]
			if _preview_anim.has_animation("idle"):
				_preview_anim.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
				_preview_anim.play("idle")
		Wardrobe.apply(_preview, save.wearing if save else {})
	_body.add_child(_centred(box))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for it in Wardrobe.ITEMS:
		var id: String = it.id
		var worn: bool = save != null and save.wearing.get(it.slot, "") == id
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		var b := _round("w_" + id, 62, DISC, Color.WHITE, func(): _wear(id), _say(it.ar, it.en), 0.86)
		if worn:
			var st := (b.get_theme_stylebox("normal") as StyleBoxFlat).duplicate() as StyleBoxFlat
			st.border_color = ACCENT_DARK
			st.set_border_width_all(4)
			b.add_theme_stylebox_override("normal", st)
		cell.add_child(_centred(b))
		var l := _label(_say(it.ar, it.en), 13, ACCENT_DARK)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(76, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cell.add_child(l)
		grid.add_child(cell)
	_body.add_child(_centred(grid))


func _world() -> void:
	var save := _save()
	if save == null:
		return
	var auto_on: bool = save.weather_pref != "clear"
	_body.add_child(_toggle_row("rain", _say("الطقس تلقائي: مطر وعجاج", "Weather by itself: rain and blown sand"), auto_on,
		func(): save.weather_pref = "clear" if auto_on else "cycle"))
	_body.add_child(_toggle_row("dust", _say("الغبار", "Drifting dust"), save.dust, func(): save.dust = not save.dust))
	_body.add_child(_toggle_row("daynight", _say("الليل والنهار يتبدلون", "Day and night go round"), save.day_cycle,
		func(): save.day_cycle = not save.day_cycle))
	_body.add_child(_centred(_wide("board", _say("رجّع المنظر مثل أول", "Back to the first view"), func(): replace_table.emit())))


func _settings() -> void:
	var save := _save()
	if save == null:
		return
	for r in [["music", "music_volume", "الموسيقى", "Music"], ["sound", "sfx_volume", "المؤثرات", "Effects"],
			["wind", "ambience_volume", "أصوات المكان", "Surroundings"]]:
		var key: String = r[1]
		var v := int(round(float(save.get(key)) * 5.0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_icon_rect(r[0], 30, ACCENT_DARK))
		var l := _label(_say(r[2], r[3]), 18, ACCENT_DARK)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(_round("minus", 48, ACCENT, Color.WHITE, func():
			save.set(key, maxf(0.0, (v - 1) / 5.0))
			_changed(), _say(r[2], r[3])))
		var dots := HBoxContainer.new()
		dots.add_theme_constant_override("separation", 4)
		dots.layout_direction = Control.LAYOUT_DIRECTION_LTR   # the level grows the way + is
		for k in 5:
			var d := Panel.new()
			var ds := StyleBoxFlat.new()
			ds.bg_color = ACCENT if k < v else PALE
			ds.set_corner_radius_all(7)
			d.add_theme_stylebox_override("panel", ds)
			d.custom_minimum_size = Vector2(13, 13)
			d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dots.add_child(d)
		row.add_child(dots)
		row.add_child(_round("plus", 48, ACCENT, Color.WHITE, func():
			save.set(key, minf(1.0, (v + 1) / 5.0))
			_changed(), _say(r[2], r[3])))
		_body.add_child(row)
	var english: bool = not save.arabic()
	_body.add_child(_centred(_wide("language", "العربية" if english else "English", func():
		save.language = "ar" if english else "en"
		_changed())))


func _about() -> void:
	var logo := _icon_rect("", 110, ACCENT_DARK)
	logo.texture = load(TableMenu.LOGO)
	_body.add_child(_centred(logo))
	for l in [
		[_say("مفاتيح", "Mafateeh"), 30],
		[_say("لعبة من عبودين قيمز: المباني والشخصيات من تصميمهم", "Buildings and characters by Aboden Games"), 17],
		[_say("بعض الموديلات من Folio 2025 لـ Bruno Simon (MIT)", "Some models from Folio 2025 by Bruno Simon (MIT)"), 15],
		[_say("المحرك Godot", "Engine: Godot"), 15],
		[_say("لا تتبع: تقدّمك يبقى في متصفحك", "No tracking: your progress stays in this browser"), 15],
	]:
		var t := _label(l[0], l[1], ACCENT_DARK)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(t)


func _hint() -> void:
	_body.add_child(_centred(_icon_rect("hint", 54, ACCENT)))
	var head := _label(_say("المرحلة %s", "Level %s") % _digits(stage), 24, ACCENT_DARK)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(head)
	var h: Array = TableMenu.WEB_HINTS[stage] if TableMenu.WEB_HINTS.has(stage) else TableMenu.HINTS.get(stage, ["", ""])
	var t := _label(_say(h[0], h[1]), 19, ACCENT_DARK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(t)
	_body.add_child(_centred(_wide("play", _say("رجوع للعب", "Back to the game"), func(): closed.emit())))


func _thanks() -> void:
	for l in [[_say("نتمنى إن الرحلة مع الشايب عجبتك", "We hope you enjoyed the journey with the old man"), 19],
			[_say("اكتشف ألعاب جديدة من استوديو عبودين قيمز", "Discover more games from Aboden Games"), 17]]:
		var t := _label(l[0], l[1], ACCENT_DARK)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(t)
	_body.add_child(_centred(_wide("", "abodengames.com", _open_site)))
	_body.add_child(_centred(_wide("restart", _say("العب من جديد", "Play again"), func(): play_level.emit(1))))


func _open_site() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try { window.top.location.href = '%s'; } catch (e) { window.location.href = '%s'; }" % [TableMenu.SITE, TableMenu.SITE])
	else:
		OS.shell_open(TableMenu.SITE)


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


func _changed() -> void:
	var save := _save()
	if save:
		save.save()
	settings_changed.emit()
	layout_direction = Control.LAYOUT_DIRECTION_RTL if _arabic() else Control.LAYOUT_DIRECTION_LTR
	open(page)


# --- building blocks ---------------------------------------------------------------------------

## A round button (an icon, or words set on it after), d pixels across.
func _round(icon: String, d: float, bg: Color, tint: Color, action: Callable, tip := "", icon_k := 0.6) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(d, d)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.add_theme_font_override("font", TableMenu.font())
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	for state in ["normal", "hover", "pressed", "focus"]:
		var st := StyleBoxFlat.new()
		st.bg_color = bg if state == "normal" or state == "focus" else (bg.darkened(0.12) if state == "hover" else bg.darkened(0.22))
		st.set_corner_radius_all(int(d))
		st.anti_aliasing = true
		if state == "focus":
			st.draw_center = false
		b.add_theme_stylebox_override(state, st)
	if icon != "" and ResourceLoader.exists(ICONS + icon + ".png"):
		b.icon = load(ICONS + icon + ".png")
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_constant_override("icon_max_width", int(d * icon_k))
		b.add_theme_color_override("icon_normal_color", tint)
		b.add_theme_color_override("icon_hover_color", tint)
		b.add_theme_color_override("icon_pressed_color", tint)
	b.pressed.connect(func():
		_click.play()
		action.call())
	return b


## A wide brown button with an icon and words.
func _wide(icon: String, words: String, action: Callable) -> Button:
	var b := _round(icon, 52, ACCENT, Color.WHITE, action, words, 0.5)
	b.text = "  " + words + "  "
	b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT   # before the words (mirrored to the right in Arabic)
	b.custom_minimum_size = Vector2(230, 52)
	b.add_theme_constant_override("icon_max_width", 26)
	b.add_theme_font_size_override("font_size", 20)
	return b


func _toggle_row(icon: String, words: String, on: bool, flip: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_icon_rect(icon, 32, ACCENT_DARK))
	var l := _label(words, 18, ACCENT_DARK)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	var b := _round("check" if on else "close", 50, ACCENT if on else DISC, Color.WHITE if on else FADED, func():
		flip.call()
		_changed(), words, 0.5)
	row.add_child(b)
	return row


func _icon_rect(icon: String, d: float, tint: Color) -> TextureRect:
	var r := TextureRect.new()
	if icon != "" and ResourceLoader.exists(ICONS + icon + ".png"):
		r.texture = load(ICONS + icon + ".png")
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(d, d)
	r.self_modulate = tint
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


func _label(s: String, px: int, c: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_override("font", TableMenu.font())
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", c)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _centred(c: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(c)
	return cc


func _save() -> Node:
	return get_node_or_null("/root/Save") if is_inside_tree() else null


func _arabic() -> bool:
	var save := _save()
	return save == null or save.arabic()


func _say(ar: String, en: String) -> String:
	var save := _save()
	return save.text(ar, en) if save else ar


func _digits(n: int) -> String:
	var save := _save()
	var s := str(n)
	if save and not save.arabic():
		return s
	var out := ""
	for ch in s:
		out += "٠١٢٣٤٥٦٧٨٩"[int(ch)]
	return out
