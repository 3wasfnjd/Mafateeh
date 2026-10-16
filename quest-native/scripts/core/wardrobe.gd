class_name Wardrobe
extends RefCounted
## The old man's wardrobe («خزانة الملابس»). Items unlock with stars earned and
## secret gems found; one item per slot is worn at a time. Pure data + rules; the
## look is applied by HeroView.apply_wardrobe() and the choice saved in Save.

const MAX_STARS := LevelData.COUNT * 3

const ITEMS := [
	{"id": "ghutra", "slot": "head", "ar": "غترة بيضاء", "en": "White ghutra", "stars": 12},
	{"id": "agal_gold", "slot": "agal", "ar": "عقال مقصّب", "en": "Gold-threaded agal", "secrets": 8},
	{"id": "thobe_beige", "slot": "thobe", "ar": "ثوب بيج", "en": "Beige thobe", "stars": 24},
	{"id": "misbaha", "slot": "misbaha", "ar": "مسبحة", "en": "Prayer beads", "stars": 36},
	{"id": "glasses", "slot": "glasses", "ar": "نظارة القراءة", "en": "Reading glasses", "stars": 50},
	{"id": "thobe_grey", "slot": "thobe", "ar": "ثوب شتوي رمادي", "en": "Grey winter thobe", "stars": 66},
	{"id": "bisht", "slot": "bisht", "ar": "البشت", "en": "The bisht", "secrets": 20},
]

const THOBE_TINTS := {"thobe_beige": Color("e9dcc2"), "thobe_grey": Color("a3a39e")}


static func item(id: String) -> Dictionary:
	for it in ITEMS:
		if it.id == id:
			return it
	return {}


static func is_unlocked(it: Dictionary, stars: int, secrets: int) -> bool:
	return stars >= int(it.get("stars", 0)) and secrets >= int(it.get("secrets", 0))


## Short requirement text for a locked item.
static func requirement(it: Dictionary, arabic: bool) -> String:
	if it.has("secrets"):
		return ("%d جوهرة سرية" if arabic else "%d secret gems") % int(it.secrets)
	return ("%d نجمة" if arabic else "%d stars") % int(it.stars)


## Dress any instance of the old man's model from a wearing dict (slot -> item id): shows the
## bisht, glasses or beads, swaps the shemagh for a white ghutra, the agal for a
## gold-threaded one, and tints the thobe. Used by the game, the menu preview and HeroView.
static func apply(model: Node, w: Dictionary) -> void:
	if model == null:
		return
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var n := String(mi.name)
		if n.begins_with("Bisht"):
			mi.visible = w.get("bisht", "") == "bisht"
		elif n.begins_with("Glasses"):
			mi.visible = w.get("glasses", "") == "glasses"
		elif n.begins_with("Misbaha"):
			mi.visible = w.get("misbaha", "") == "misbaha"
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if base == null:
				continue
			var mat_name := base.resource_name
			var over: StandardMaterial3D = null
			if mat_name.begins_with("shemagh") and w.get("head", "") == "ghutra":
				over = base.duplicate()
				over.albedo_texture = load("res://assets/character/wardrobe/%s.png" % ("ghutra_border" if mat_name == "shemagh_border" else "ghutra"))
				over.normal_enabled = false
			elif mat_name == "agal" and w.get("agal", "") == "agal_gold":
				over = base.duplicate()
				over.albedo_texture = load("res://assets/character/wardrobe/agal_gold.png")
				over.metallic = 0.35
			elif mat_name.begins_with("thobe") and THOBE_TINTS.has(w.get("thobe", "")):
				over = base.duplicate()
				over.albedo_color = THOBE_TINTS[w.thobe]
			mi.set_surface_override_material(i, over)
