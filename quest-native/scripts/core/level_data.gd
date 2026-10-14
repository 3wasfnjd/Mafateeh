class_name LevelData
extends RefCounted
## Mafateeh v2: 34 levels in five chapters (the old man gathers the keys to his
## grandfather's house in Diriyah, district by district). Every level is checked by
## tests/solver.gd: solvable, no dead ends (unless "dead_ends_ok"), the gate
## mechanics in "bypass" cannot be skipped, and "par" is the shortest solution.
## Coordinates are board units: one floor tile = 1 unit, x right, z toward the
## player, y up. The playable courtyard spans x -3.65..3.65 and z -3.03..3.05 (a
## level may narrow it with "bounds"); the exit tunnel is behind the back wall at
## x = exit_x(def).
##
## Rules fields: start, walls, doors, keys (gold 0 / silver 1 / copper 2), gems,
## secret (optional gem), levers, crates (scripted "to"/"dir" or free), plates,
## weights, balance, brick, falaj + sluices + waters, falcon, shade, optics (mirrors,
## lamps, receiver, through_portals), portals, circuit, dials, sequence, storeys +
## stairs, moat + bridges, pool_room; win: need_* / goal_gems.
## Art-only fields (never read by puzzle logic):
##   time     "dawn" | "day" | "sunset" | "night"
##   weather  "clear" | "rain"
##   roofs    [x, z, w, d] covered passages (no interactables underneath)
##   title_ar / title_en  short names shown in the level card

const COUNT := 37
const MAIN_COUNT := 34  # levels after this form the bonus chapter (all secret gems)
const EXIT_X := 1.75
const UPPER_HEIGHT := 2.1

# Five districts of Diriyah. Story beats are shown when a chapter starts.
const CHAPTERS := [
	{"ar": "الفناء", "en": "The Courtyard", "from": 1, "to": 7,
		"story_ar": "ضاعت مفاتيح بيت الجد في الدرعية. يبدأ الشايب من فناء بيته.",
		"story_en": "The keys to Grandfather's house in Diriyah are lost. The old man starts in his own courtyard."},
	{"ar": "السوق", "en": "The Souq", "from": 8, "to": 14,
		"story_ar": "في السوق قناديل وموازين وطوب، وكل دكان يخبئ مفتاحًا.",
		"story_en": "The souq has lamps, scales and mud bricks, and every shop hides a key."},
	{"ar": "الواحة", "en": "The Oasis", "from": 15, "to": 21,
		"story_ar": "في الواحة يجري الفلج بين النخيل، ويرافق الشايبَ صقرُه شاهين.",
		"story_en": "In the oasis the falaj runs between the palms, and the falcon Shaheen joins the old man."},
	{"ar": "القصر", "en": "The Palace", "from": 22, "to": 28,
		"story_ar": "طوابق القصر وأقراصه تحفظ أسرار الجد.",
		"story_en": "The palace floors and its dials keep Grandfather's secrets."},
	{"ar": "السطوح", "en": "The Rooftops", "from": 29, "to": 34,
		"story_ar": "فوق السطوح، تحت شمس الدرعية، آخر الأبواب: بيت الجد.",
		"story_en": "Across the rooftops, under the Diriyah sun, the last door: Grandfather's house."},
	{"ar": "ديوان الجد", "en": "Grandfather's Diwan", "from": 35, "to": 37, "bonus": true,
		"story_ar": "الجواهر السرية كلها بين يديك، فانفتح ديوان الجد وفيه آخر أسراره.",
		"story_en": "With every secret gem in hand, Grandfather's diwan opens, and his last secrets with it."},
]

const LEVELS := {
	# ======================= 1 · الفناء (Courtyard) ========================================
	1: {
		"title_ar": "الفناء الأول", "title_en": "First Courtyard",
		"time": "day", "weather": "clear",
		"start": [-0.76, 1.35], "start_yaw": 1.5708,
		"walls": [[-0.9, -0.7, 3.05, 0.29], [-3.25, 1.15, 1.42, 0.29]],
		"crates": [{"at": [0.36, 1.35], "to": [1.75, 1.35], "dir": [1, 0]}],
		"keys": [[-2.7, -2.0, 0]], "need_keys": 1,
		"secret": [0.36, 1.35],
		"par": 2,
	},
	2: {
		"title_ar": "الممر المقفل", "title_en": "Locked Passage",
		"time": "dawn", "weather": "clear",
		"start": [-2.5, 2.45],
		"walls": [[-3.63, 0.0, 0.86, 0.3], [1.075, 0.0, 5.55, 0.3], [0.0, -2.08, 0.28, 1.85], [0.0, 1.9, 0.28, 1.15]],
		"keys": [[2.5, 2.1, 0]],
		"doors": [[-2.45, 0.0, 1.5, 0.3, "lock", 0]],
		"gems": [[2.7, -1.8, 0]], "goal_gems": 1,
		"secret": [-3.2, -2.6],
		"bypass": [["lock"]],
		"par": 3,
	},
	3: {
		"title_ar": "الجسران المتناوبان", "title_en": "Alternating Bridges",
		"time": "day", "weather": "clear",
		"start": [0.0, 2.6],
		"walls": [[0.0, -2.02, 0.28, 2.76]],
		"moat": true,
		"bridges": [[-2.3, "choice", 0], [2.3, "choice", 1]],
		"levers": [[0.0, 1.5, 0]],
		"gems": [[-2.3, -2.0, 0], [2.3, -2.0, 1]], "goal_gems": 3,
		"secret": [-3.25, 2.65],
		"bypass": [["lever"]],
		"par": 3,
	},
	4: {
		"title_ar": "مفتاحان وبابان", "title_en": "Two Keys, Two Doors",
		"time": "day", "weather": "clear",
		"start": [-2.6, 2.3],
		"walls": [[-3.275, 0.6, 0.75, 0.3], [-0.1, 0.6, 2.8, 0.3], [3.175, 0.6, 0.95, 0.3], [0.0, -1.215, 0.3, 3.63]],
		"doors": [[-2.2, 0.6, 1.4, 0.3, "lock", 0], [2.0, 0.6, 1.4, 0.3, "lock", 1]],
		"keys": [[2.6, 2.2, 0], [-2.4, -2.3, 1]], "need_keys": 3,
		"secret": [-3.25, -0.3],
		"bypass": [["lock"]],
		"par": 4,
	},
	5: {
		"title_ar": "الصلة الخفية", "title_en": "Hidden Connection",
		"time": "night", "weather": "clear",
		"start": [1.4, 2.5],
		"walls": [[-0.6, -1.91, 0.3, 3.08], [-2.3, -0.3, 3.4, 0.3], [0.3, 0.0, 1.8, 0.3], [3.6, 0.0, 0.8, 0.3]],
		"portals": [[-2.5, 1.8, -2.6, -1.6]],
		"keys": [[-1.4, -2.5, 0]],
		"doors": [[2.2, 0.0, 1.8, 0.3, "lock", 0]],
		"gems": [[2.5, -1.7, 0]], "goal_gems": 1,
		"roofs": [[0.3, 1.0, 1.6, 1.4]],
		"secret": [-3.2, -2.65],
		"bypass": [["portal"], ["lock"]],
		"par": 5,
	},
	6: {
		"title_ar": "اسحب الصندوق", "title_en": "Pull the Crate",
		"time": "sunset", "weather": "clear",
		"start": [-1.5, 2.0],
		"walls": [[-1.825, 0.0, 3.65, 0.3], [2.325, 0.0, 2.65, 0.3], [0.5, -1.3, 1.0, 0.3]],
		"crates": [{"at": [0.5, 0.0]}],
		"keys": [[2.5, -2.3, 0]], "need_keys": 1,
		"secret": [-3.2, -2.6],
		"par": 3,
	},
	7: {
		"title_ar": "الدكّة", "title_en": "The Stone Plate",
		"time": "day", "weather": "clear",
		"start": [1.5, 2.2],
		"walls": [[-1.35, -1.0, 4.6, 0.3], [3.1, -1.0, 1.1, 0.3]],
		"crates": [{"at": [-0.5, 1.0]}],
		"plates": [[-2.5, 0.0, 0]],
		"doors": [[1.75, -1.0, 1.6, 0.3, "plate", 0]],
		"gems": [[-2.5, -2.3, 0]], "goal_gems": 1,
		"secret": [3.25, 2.65],
		"par": 4,
	},

	# ======================= 2 · السوق (Souq) =============================================
	8: {
		"title_ar": "درب الضوء", "title_en": "Path of Light",
		"time": "day", "weather": "clear",
		"start": [-0.1, 2.65],
		"walls": [[0.15, 0.0, 2.45, 0.32]],
		"optics": {
			"source": [-3.35, 1.8, 1, 0],
			"mirrors": [[-1.8, 1.8, 1], [-1.8, -1.7, 0], [2.0, -1.7, 0], [-3.1, -1.7, 0]],
			"receiver": [2.0, 1.8],
		},
		"need_light": true,
		"secret": [3.25, -2.65],
		"bypass": [["mirror"]],
		"par": 2,
	},
	9: {
		"title_ar": "المرآة والقنديل", "title_en": "Mirror and Lantern",
		"time": "sunset", "weather": "clear",
		"start": [1.2, 2.5],
		"walls": [[-3.275, 0.0, 0.75, 0.3], [-0.1, 0.0, 2.8, 0.3], [3.175, 0.0, 0.95, 0.3], [0.0, -1.515, 0.3, 3.03]],
		"optics": {"source": [0.0, 2.9, 0, -1], "mirrors": [[0.0, 1.5, 0]], "lamps": [[-2.5, 1.5, 0], [2.5, 1.5, 1]]},
		"doors": [[-2.2, 0.0, 1.4, 0.3, "lamp", 0], [2.0, 0.0, 1.4, 0.3, "lamp", 1]],
		"keys": [[-2.5, -2.3, 0]], "need_keys": 1,
		"secret": [3.25, -2.65],
		"bypass": [["mirror"]],
		"par": 3,
	},
	10: {
		"title_ar": "الوزن يمسك الباب", "title_en": "A Weight Holds the Door",
		"time": "day", "weather": "clear",
		"start": [0.5, 2.0],
		"walls": [[-3.225, -1.0, 0.85, 0.3], [1.225, -1.0, 4.85, 0.3]],
		"weights": [[2.5, 2.3, 2]],
		"plates": [[-2.0, 0.0, 0]],
		"doors": [[-2.0, -1.0, 1.6, 0.3, "plate", 0]],
		"gems": [[-2.5, -2.3, 0]], "goal_gems": 1,
		"secret": [-3.25, 2.65],
		"bypass": [["weight"]],
		"par": 3,
	},
	11: {
		"title_ar": "الوزن الزائد", "title_en": "One Weight Too Many",
		"time": "day", "weather": "clear",
		"start": [0.0, 2.8],
		"walls": [[-1.6, -1.2, 4.8, 0.3], [3.35, -1.2, 1.3, 0.3]],
		"balance": {"at": [0.0, 0.0], "weights": [[-3.0, 1.9, 1], [-1.0, 1.9, 3], [1.0, 1.9, 4], [3.0, 1.9, 9]], "free": true},
		"doors": [[1.7, -1.2, 1.8, 0.3, "balance", 0]],
		"gems": [[-2.6, -2.3, 0]], "goal_gems": 1,
		"secret": [3.25, -2.65],
		"bypass": [["weight"], ["pan"]],
		"par": 7,
	},
	12: {
		"title_ar": "بيت البركة", "title_en": "House of the Pool",
		"time": "day", "weather": "rain",
		"start": [0.0, 2.6],
		"walls": [[-3.65, 0.8, 0.7, 0.3], [0.0, 0.8, 3.8, 0.3], [3.65, 0.8, 0.7, 0.3], [0.0, -1.55, 0.3, 3.9], [1.0, -1.1, 2.0, 0.3]],
		"doors": [[2.6, 0.8, 1.4, 0.3, "lock", 0]],
		"keys": [[-2.05, -2.95, 0]],
		"gems": [[0.95, -2.4, 0]],
		"need_keys": 1, "goal_gems": 1,
		"pool_room": true,
		"roofs": [[2.75, -0.15, 1.8, 1.6]],
		"secret": [3.3, 2.7],
		"bypass": [["brick"], ["brickSocket"], ["lock"]],
		"par": 5,
	},
	13: {
		"title_ar": "طوبة لأمرين", "title_en": "One Brick, Two Jobs",
		"time": "sunset", "weather": "clear",
		"start": [-1.0, 2.6],
		"walls": [[1.7, 1.6, 0.6, 0.3], [3.425, 1.6, 0.45, 0.3], [1.4, 2.325, 0.3, 1.45]],
		"doors": [[2.6, 1.6, 1.2, 0.3, "plate", 0]],
		"brick": {"at": [-2.6, 2.3], "sockets": [[0.0, 0.25]]},
		"plates": [[-1.6, 1.0, 0]],
		"waters": [[0.0, -0.75, 7.3, 1.0, 0, "brickSocket"]],
		"keys": [[2.6, 2.5, 0]], "need_keys": 1,
		"gems": [[-2.5, -2.4, 0]], "goal_gems": 1,
		"secret": [3.25, -2.65],
		"bypass": [["brick"], ["brickSocket"]],
		"par": 6,
	},
	14: {
		"title_ar": "قناديل السوق", "title_en": "Lamps of the Souq",
		"time": "night", "weather": "clear",
		"start": [0.0, 2.65],
		"walls": [[-1.55, -1.0, 4.9, 0.3], [3.32, -1.0, 1.35, 0.3], [0.0, 1.8, 0.3, 1.05]],
		"circuit": {"count": 3, "masks": [3, 6, 4], "positions": [[-2.6, 0.7], [0.0, 0.4], [2.6, 0.7]]},
		"doors": [[1.75, -1.0, 1.6, 0.3, "circuit", 0]],
		"gems": [[-2.7, -2.2, 0]], "goal_gems": 1,
		"need_circuit": true,
		"secret": [3.25, 2.65],
		"bypass": [["circuit"]],
		"par": 3,
	},

	# ======================= 3 · الواحة (Oasis) ===========================================
	15: {
		"title_ar": "أول فلج", "title_en": "The First Falaj",
		"time": "dawn", "weather": "clear",
		"start": [-1.5, 2.6],
		"walls": [],
		"falaj": {"nodes": [[-3.2, 1.6], [-0.5, 1.6], [2.2, 1.6]], "source": 0,
			"channels": [[0, 1, -1], [1, 2, 0]], "pools": [[2, 0]]},
		"sluices": [[0.85, 1.6, 0]],
		"waters": [[0.0, -0.4, 7.3, 1.0, 0]],
		"gems": [[-2.0, -2.3, 0]], "goal_gems": 1,
		"secret": [3.25, -2.65],
		"bypass": [["sluice"]],
		"par": 2,
	},
	16: {
		"title_ar": "الماء يمر بالبركة", "title_en": "Through the Pool",
		"time": "day", "weather": "clear",
		"start": [-2.6, 1.15],
		"walls": [],
		"falaj": {"nodes": [[-3.2, 2.5], [-1.5, 2.5], [0.5, 2.5], [-1.5, 1.5], [2.5, 1.5]], "source": 0,
			"channels": [[0, 1, -1], [1, 2, 0], [1, 3, -2], [3, 4, 1], [2, 4, 2]], "pools": [[2, 0], [4, 1]]},
		"sluices": [[-0.5, 2.5, 0], [0.5, 1.5, 1], [1.5, 2.0, 2]], "sluices_open": [1],
		"waters": [[0.0, 0.2, 7.3, 0.9, 0], [0.0, -1.6, 7.3, 0.9, 1]],
		"gems": [[-2.0, -2.6, 0]], "goal_gems": 1,
		"secret": [3.25, -0.7],
		"bypass": [["sluice"]],
		"par": 2,
	},
	17: {
		"title_ar": "الماء والضوء", "title_en": "Water and Light",
		"time": "day", "weather": "clear",
		"start": [-0.1, 2.7],
		"walls": [[0.0, -2.02, 0.28, 2.76]],
		"moat": true,
		"bridges": [[-2.3, "choice", 0], [2.3, "litChoice", 1]],
		"levers": [[0.0, 1.4, 0]],
		"keys": [[-2.3, -2.0, 0]],
		"gems": [[2.3, -2.0, 0]], "goal_gems": 1, "need_keys": 1,
		"need_light": true,
		"optics": {
			"source": [-3.35, 2.45, 1, 0],
			"mirrors": [[-1.8, 2.45, 0], [-1.8, 1.05, 1], [2.55, 1.05, 0]],
			"receiver": [2.55, 2.65],
		},
		"secret": [-3.25, -2.65],
		"bypass": [["lever"], ["mirror"]],
		"par": 5,
	},
	18: {
		"title_ar": "شاهين", "title_en": "Shaheen",
		"time": "day", "weather": "clear",
		"start": [-1.0, 2.0],
		"walls": [[-3.275, 0.0, 0.75, 0.3], [1.075, 0.0, 5.15, 0.3], [2.6, 1.2, 2.1, 0.3], [1.55, 2.1, 0.3, 1.8]],
		"falcon": {"at": [-2.6, 2.4]},
		"keys": [[2.7, 2.4, 0]],
		"doors": [[-2.2, 0.0, 1.4, 0.3, "lock", 0]],
		"gems": [[-2.5, -2.3, 0]], "goal_gems": 1,
		"secret": [3.25, -2.65],
		"bypass": [["falcon"], ["lock"]],
		"par": 3,
	},
	19: {
		"title_ar": "اختر بحكمة", "title_en": "Choose Wisely",
		"time": "sunset", "weather": "clear",
		"start": [-0.5, 2.0],
		"walls": [[-3.275, 0.0, 0.75, 0.3], [1.075, 0.0, 5.15, 0.3], [0.3, -1.3, 0.3, 2.6]],
		"falcon": {"at": [-2.6, 2.5]},
		"waters": [[2.6, 1.45, 2.2, 0.5, 9], [1.25, 2.25, 0.5, 2.1, 9]],
		"plates": [[2.7, 2.5, 0]],
		"doors": [[-2.2, 0.0, 1.4, 0.3, "plate", 0]],
		"keys": [[2.2, -1.6, 0]], "need_keys": 1,
		"dead_ends_ok": true,  # sending Shaheen for the key is the tempting wrong choice (undo fixes it)
		"secret": [-3.25, -2.65],
		"bypass": [["falcon"]],
		"par": 2,
	},
	20: {
		"title_ar": "رافعة لأمرين", "title_en": "One Lever, Two Things",
		"time": "day", "weather": "clear",
		"start": [0.0, 2.6],
		"walls": [],
		"moat": true,
		"bridges": [[-2.3, "choice", 0]],
		"levers": [[0.0, -1.15, 0]],
		"falaj": {"nodes": [[-3.2, 2.6], [2.6, 2.6]], "source": 0, "channels": [[0, 1, "lever"]], "pools": [[1, 0]]},
		"waters": [[0.0, -2.05, 7.3, 0.8, 0]],
		"keys": [[2.6, 1.6, 0]], "need_keys": 1,
		"gems": [[-2.5, -2.75, 0]], "goal_gems": 1,
		"secret": [3.25, -2.75],
		"bypass": [["lever"]],
		"par": 3,
	},
	21: {
		"title_ar": "واحة شاهين", "title_en": "Shaheen's Oasis",
		"time": "sunset", "weather": "clear",
		"start": [-0.6, 2.4],
		"walls": [[-3.275, 0.3, 0.75, 0.3], [1.075, 0.3, 5.15, 0.3], [-3.325, 1.6, 0.65, 0.3], [-1.45, 2.325, 0.3, 1.45]],
		"falcon": {"at": [0.3, 2.65]},
		"crates": [{"at": [0.5, 1.15]}],
		"plates": [[2.6, 2.4, 0], [-0.5, 1.15, 1]],
		"waters": [[2.6, 1.45, 2.2, 0.5, 9], [1.25, 2.25, 0.5, 2.1, 9], [0.0, -2.2, 7.3, 0.8, 0]],
		"doors": [[-2.2, 0.3, 1.4, 0.3, "plate", 0], [-2.3, 1.6, 1.4, 0.3, "plate", 1]],
		"falaj": {"nodes": [[-3.2, -0.9], [2.6, -0.9]], "source": 0, "channels": [[0, 1, 0]], "pools": [[1, 0]]},
		"sluices": [[-0.6, -0.9, 0]],
		"gems": [[-2.5, -2.75, 0], [-2.6, 2.5, 1]], "goal_gems": 3,
		"secret": [3.25, -0.4],
		"bypass": [["falcon"], ["sluice"]],
		"par": 5,
	},

	# ======================= 4 · القصر (Palace) ==========================================
	22: {
		"title_ar": "الأقراص المترابطة", "title_en": "Linked Dials",
		"time": "dawn", "weather": "clear",
		"start": [0.0, 2.7],
		"walls": [[-1.6, -0.85, 4.8, 0.3], [3.35, -0.85, 1.3, 0.3]],
		"dials": {
			"positions": [[-2.5, 1.15], [0.0, 2.0], [2.5, 1.15]],
			"links": [[1, 1, 0], [0, 1, 1], [1, 0, 1]],
			"target": [2, 1, 3],
		},
		"doors": [[1.7, -0.85, 1.8, 0.3, "dials", 0]],
		"keys": [[-2.7, -2.1, 0]], "need_keys": 1,
		"need_dials": true,
		"secret": [3.25, 2.65],
		"bypass": [["dial"]],
		"par": 4,
	},
	23: {
		"title_ar": "الدور العلوي", "title_en": "Upper Floor",
		"time": "day", "weather": "clear",
		"storeys": true,
		"start": [0.0, 2.8],
		"walls": [],
		"stairs": [[-2.9, "plate", 0]],
		"weights": [[2.6, 2.4, 2]],
		"plates": [[-1.4, 2.2, 0]],
		"keys": [[2.7, -1.9, 0]], "need_keys": 1,
		"secret": [-2.7, -2.6],
		"bypass": [["weight"]],
		"par": 3,
	},
	24: {
		"title_ar": "أقراص بين الطابقين", "title_en": "Dials Across Floors",
		"time": "sunset", "weather": "clear",
		"storeys": true,
		"start": [0.0, 2.8],
		"walls": [],
		"stairs": [[-2.9, "always", 0]],
		"dials": {
			"positions": [[-1.2, 2.2], [1.2, 2.2], [0.6, -1.8]],
			"links": [[1, 0, 1], [1, 1, 0], [0, 1, 1]],
			"target": [2, 3, 1],
		},
		"need_dials": true,
		"secret": [3.0, -2.6],
		"bypass": [["dial"]],
		"par": 3,
	},
	25: {
		"title_ar": "أوزان السطح", "title_en": "Weights on the Terrace",
		"time": "day", "weather": "rain",
		"storeys": true,
		"start": [0.0, 2.8],
		"walls": [],
		"stairs": [[-2.9, "always", 0]],
		"balance": {"at": [1.1, -1.9], "weights": [[-1.3, 2.1, 1], [1.3, 2.1, 2], [-1.2, -2.3, 3], [2.6, 2.5, 5]], "free": true},
		"need_balance": true,
		"secret": [3.1, -2.6],
		"bypass": [["weight"]],
		"par": 6,
	},
	26: {
		"title_ar": "الحمل عبر الممر", "title_en": "Carry Through the Passage",
		"time": "night", "weather": "clear",
		"storeys": true,
		"start": [0.0, 2.8],
		"walls": [],
		"stairs": [],
		"portals": [[2.6, 2.3, 2.6, -2.0]],
		"balance": {"at": [-1.0, -1.9], "weights": [[-2.5, 2.4, 2], [-0.6, 2.4, 2]]},
		"need_balance": true,
		"secret": [-3.0, -2.6],
		"bypass": [["portal"]],
		"par": 7,
	},
	27: {
		"title_ar": "الدرجان", "title_en": "Two Stairways",
		"time": "dawn", "weather": "clear",
		"storeys": true,
		"start": [0.0, 2.8],
		"walls": [[0.0, -2.2, 0.3, 2.3]],
		"stairs": [[-2.9, "choice", 0], [2.9, "keyChoice", 1]],
		"levers": [[0.0, 2.1, 0]],
		"keys": [[-1.6, -1.8, 0]],
		"dials": {"positions": [[1.3, -1.75], [2.5, -2.5]], "links": [[1, 1], [1, 0]], "target": [3, 1]},
		"need_keys": 1, "need_dials": true,
		"secret": [-3.0, -2.6],
		"bypass": [["lever"], ["key"]],
		"par": 5,
	},
	28: {
		"title_ar": "الرقم في الأعلى", "title_en": "The Number Upstairs",
		"time": "day", "weather": "clear",
		"storeys": true,
		"start": [0.0, 2.8],
		"walls": [[0.9, -2.6, 0.3, 0.86]],
		"stairs": [[-2.9, "always", 0]],
		"dials": {
			"positions": [[-1.8, 2.2], [0.0, 2.2], [1.8, 2.2]],
			"links": [[1, 1, 0], [0, 1, 0], [0, 1, 1]],
			"target": [3, 1, 2],
			"hide_targets": true, "target_board": [-0.8, -2.85],
		},
		"doors": [[0.9, -1.55, 0.3, 1.2, "dials", 0]],
		"gems": [[2.7, -2.4, 0]], "goal_gems": 1,
		"secret": [-3.0, -2.6],
		"bypass": [["dial"]],
		"par": 6,
	},

	# ======================= 5 · السطوح (Rooftops) =======================================
	29: {
		"title_ar": "ظل النخلة", "title_en": "Palm Shade",
		"time": "day", "weather": "clear",
		"start": [0.0, 2.6],
		"walls": [[-2.5, -1.0, 0.1, 0.64], [-1.5, -1.0, 0.1, 0.64], [-0.5, -1.0, 0.1, 0.64], [0.5, -1.0, 0.1, 0.64],
			[1.5, -1.0, 0.1, 0.64], [2.5, -1.0, 0.1, 0.64]],
		"shade": {
			"palms": [[-3.6, 1.5], [3.6, 1.5]],
			"paths": [
				[[0.6, -1.5], [1.6, -1.5], [2.6, -1.5], [3.6, -1.5], [4.6, -1.5], [5.6, -1.5], [6.6, -1.5]],
				[[-0.6, -3.5], [-1.6, -3.5], [-2.6, -3.5], [-3.6, -3.5], [-4.6, -3.5], [-5.6, -3.5], [-6.6, -3.5]]],
			"hot": [[-3.0, 0.0, 1.0, 1.0], [-2.0, 0.0, 1.0, 1.0], [-1.0, 0.0, 1.0, 1.0], [0.0, 0.0, 1.0, 1.0],
				[1.0, 0.0, 1.0, 1.0], [2.0, 0.0, 1.0, 1.0], [3.0, 0.0, 1.0, 1.0],
				[-3.0, -2.0, 1.0, 1.0], [-2.0, -2.0, 1.0, 1.0], [-1.0, -2.0, 1.0, 1.0], [0.0, -2.0, 1.0, 1.0],
				[1.0, -2.0, 1.0, 1.0], [2.0, -2.0, 1.0, 1.0], [3.0, -2.0, 1.0, 1.0]],
			"sundial": [2.6, 2.0],
		},
		"gems": [[-2.5, -2.82, 0]], "goal_gems": 1,
		"secret": [-3.25, 2.65],
		"bypass": [["sundial"]],
		"par": 4,
	},
	30: {
		"title_ar": "سطوح بلونين", "title_en": "Two-Colour Rooftops",
		"time": "sunset", "weather": "clear",
		"storeys": true,
		"start": [1.0, 2.6],
		"walls": [[0.0, -2.2, 0.3, 2.3], [-1.0, 1.9, 1.8, 0.3], [-1.9, 2.475, 0.3, 1.15]],
		"stairs": [[-2.9, "always", 0], [2.9, "lock", 1]],
		"doors": [[-0.1, 2.5, 0.3, 1.0, "lock", 0]],
		"keys": [[-1.6, -1.8, 0], [-1.0, 2.6, 1]], "need_keys": 3,
		"gems": [[2.6, -2.5, 0]], "goal_gems": 1,
		"secret": [-3.1, -2.6],
		"bypass": [["lock"]],
		"par": 5,
	},
	31: {
		"title_ar": "صهريج الدرج", "title_en": "The Stair Cistern",
		"time": "day", "weather": "clear",
		"storeys": true,
		"start": [0.3, 2.8],
		"walls": [[0.95, 2.575, 0.3, 0.95], [-0.4, -2.75, 0.3, 0.6]],
		"stairs": [[-2.9, "pool", 0]],
		"falaj": {"nodes": [[-0.5, 2.7], [-0.5, 1.6], [-2.2, 1.6], [2.4, 2.55]], "source": 0,
			"channels": [[0, 1, -1], [1, 2, 0], [1, 3, -2]], "pools": [[2, 0], [3, 1]]},
		"sluices": [[-1.35, 1.6, 0]],
		"waters": [[2.3, 1.55, 2.7, 0.5, 1]],
		"keys": [[2.6, -1.9, 0], [3.1, 2.75, 1]],
		"doors": [[-0.4, -1.75, 0.3, 1.4, "lock", 1]],
		"need_keys": 3,
		"secret": [-2.9, -2.6],
		"bypass": [["sluice"]],
		"par": 4,
	},
	32: {
		"title_ar": "الصندوق والظل", "title_en": "The Crate and the Shade",
		"time": "day", "weather": "clear",
		"start": [2.0, 2.5],
		"walls": [[-1.0, -1.75, 0.3, 0.6], [-2.325, -1.3, 2.65, 0.3]],
		"crates": [{"at": [0.5, 1.0]}],
		"plates": [[0.5, -2.0, 0]],
		"doors": [[-1.0, -2.55, 0.3, 1.0, "plate", 0]],
		"shade": {
			"palms": [[-3.4, 2.6]],
			"path": [[0.9, -3.1], [1.9, -3.1], [2.9, -3.1], [3.9, -3.1], [3.9, -3.1], [4.9, -3.1], [5.9, -3.1], [6.9, -3.1]],
			"hot": [[-3.25, -0.5, 0.8, 1.0], [-2.5, -0.5, 1.0, 1.0], [-1.5, -0.5, 1.0, 1.0], [-0.5, -0.5, 1.0, 1.0],
				[0.5, -0.5, 1.0, 1.0], [1.5, -0.5, 1.0, 1.0], [2.5, -0.5, 1.0, 1.0], [3.25, -0.5, 0.8, 1.0]],
			"sundial": [2.6, 1.6],
		},
		"gems": [[-2.5, -2.5, 0]], "goal_gems": 1,
		"secret": [3.25, 2.7],
		"par": 5,
	},
	33: {
		"title_ar": "مرايا الليل", "title_en": "Night Mirrors",
		"time": "night", "weather": "clear",
		"start": [-1.0, 2.0],
		"walls": [[0.0, 0.0, 7.3, 0.3]],
		"portals": [[1.0, 1.2, -2.0, -1.0]],
		"optics": {
			"source": [-3.35, 2.5, 1, 0],
			"mirrors": [[1.0, 2.5, 1], [-2.0, -2.2, 1]],
			"lamps": [[-1.5, 2.5, 0], [0.5, -2.2, 1]],
			"receiver": [2.5, -2.2],
			"through_portals": true,
		},
		"need_light": true, "need_lamps": 3,
		"secret": [3.25, 2.7],
		"bypass": [["mirror"]],
		"par": 3,
	},
	34: {
		"title_ar": "بيت الجد", "title_en": "Grandfather's House",
		"time": "sunset", "weather": "clear",
		"storeys": true,
		"start": [0.0, 2.95],
		"walls": [[0.0, -2.2, 0.3, 2.3]],
		"stairs": [[-2.9, "always", 0], [2.9, "lock", 1]],
		"dials": {
			"positions": [[-1.1, 2.5], [1.1, 2.5], [2.6, -2.5]],
			"links": [[1, 1, 0], [0, 1, 1], [0, 0, 1]],
			"target": [1, 2, 2],
		},
		"keys": [[-1.4, -1.4, 1]],
		"gems": [[1.4, -1.6, 0]], "goal_gems": 1,
		"need_keys": 2, "need_dials": true,
		"secret": [-3.0, -2.6],
		"bypass": [["dial"], ["lock"]],
		"finale": true,
		"par": 6,
	},
	# ======================= ★ ديوان الجد (Bonus: all secret gems) =======================
	35: {
		"title_ar": "شاهين والفلج", "title_en": "Shaheen and the Falaj",
		"time": "dawn", "weather": "clear",
		"start": [-1.0, 2.0],
		"walls": [[-3.275, 0.0, 0.75, 0.3], [1.075, 0.0, 5.15, 0.3], [2.6, 1.2, 2.1, 0.3], [1.55, 2.1, 0.3, 1.8]],
		"falcon": {"at": [-2.6, 2.4]},
		"keys": [[2.7, 2.4, 1]],
		"doors": [[-2.2, 0.0, 1.4, 0.3, "lock", 1]],
		"falaj": {"nodes": [[-3.2, -0.9], [2.6, -0.9]], "source": 0, "channels": [[0, 1, 0]], "pools": [[1, 0]]},
		"sluices": [[-0.6, -0.9, 0]],
		"waters": [[0.0, -2.2, 7.3, 0.8, 0]],
		"gems": [[-2.5, -2.75, 0]], "goal_gems": 1,
		"secret": [3.25, -0.45],
		"bypass": [["falcon"], ["lock"], ["sluice"]],
		"par": 4,
	},
	36: {
		"title_ar": "ميزان الديوان", "title_en": "The Diwan Scales",
		"time": "night", "weather": "clear",
		"storeys": true,
		"start": [0.0, 2.8],
		"walls": [],
		"stairs": [[-2.9, "dials", 0]],
		"dials": {"positions": [[-1.2, 2.2], [1.2, 2.2]], "links": [[1, 1], [0, 1]], "target": [2, 3]},
		"balance": {"at": [1.1, -1.9], "weights": [[-2.4, 2.6, 2], [2.4, 2.6, 2], [-1.3, -2.3, 1], [2.6, -2.5, 3]]},
		"need_balance": true,
		"secret": [-3.0, -2.6],
		"bypass": [["dial"]],
		"par": 11,
	},
	37: {
		"title_ar": "سرّ الجد", "title_en": "Grandfather's Secret",
		"time": "sunset", "weather": "clear",
		"start": [-1.0, 2.5],
		"walls": [[0.6, -2.325, 0.3, 1.45], [-1.5, 0.0, 4.0, 0.3]],
		"crates": [{"at": [0.5, 1.0]}],
		"falcon": {"at": [-2.6, 2.6]},
		"plates": [[-1.5, -2.0, 0], [2.5, 1.0, 1]],
		"doors": [[2.2, -1.75, 2.9, 0.3, "plate", 0], [2.2, -2.45, 2.9, 0.3, "plate", 1]],
		"gems": [[3.1, -3.0, 0]], "goal_gems": 1,
		"secret": [-3.25, 1.4],
		"bypass": [["falcon"], ["crate"]],
		"finale": true,
		"par": 4,
	},
}


static func get_level(n: int) -> Dictionary:
	return LEVELS.get(n, {})


static func is_bonus(n: int) -> bool:
	return n > MAIN_COUNT


static func chapter_of(n: int) -> int:
	for i in CHAPTERS.size():
		if n >= int(CHAPTERS[i].from) and n <= int(CHAPTERS[i].to):
			return i
	return 0


## Stars for finishing in `moves` actions: 3 at or under par (the solver's shortest
## solution), 2 within a small margin, otherwise 1.
static func stars(def: Dictionary, moves: int) -> int:
	var p: int = def.get("par", 0)
	if p <= 0:
		return 3
	if moves <= p:
		return 3
	if moves <= p + maxi(2, ceili(p * 0.3)):
		return 2
	return 1


static func exit_x(def: Dictionary) -> float:
	return def.get("exit_x", EXIT_X)


static func surface_y(def: Dictionary, _x: float, z: float) -> float:
	if def.get("storeys", false):
		return UPPER_HEIGHT * clampf((0.95 - z) / 1.9, 0.0, 1.0)
	return 0.0


static func exit_y(def: Dictionary) -> float:
	return UPPER_HEIGHT if def.get("storeys", false) else 0.0
