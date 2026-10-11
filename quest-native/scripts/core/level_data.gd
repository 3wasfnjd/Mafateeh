class_name LevelData
extends RefCounted
## All 21 levels. Puzzle values (positions, links, masks, sequences, targets and
## win conditions) are ported verbatim from the web reference (src/game.js).
## Coordinates are board units: one floor tile = 1 unit, x right, z toward the
## player, y up. The playable courtyard spans x -3.65..3.65 and z -3.03..3.05;
## the exit tunnel is at x = EXIT_X behind the back wall.
##
## Art-only fields (never read by puzzle logic):
##   time     "dawn" | "day" | "sunset" | "night"
##   weather  "clear" | "rain"
##   roofs    [x, z, w, d] covered passages (no interactables underneath)
##   title_ar / title_en  short names shown in the level card

const COUNT := 21
const EXIT_X := 1.75
const UPPER_HEIGHT := 2.1

const LEVELS := {
	1: {
		"title_ar": "الفناء الأول", "title_en": "First Courtyard",
		"time": "day", "weather": "clear",
		"start": [-0.76, 1.35], "start_yaw": 1.5708,
		"walls": [[-0.9, -0.7, 3.05, 0.29], [-3.25, 1.15, 1.42, 0.29]],
		"crates": [{"at": [0.36, 1.35], "to": [1.75, 1.35], "dir": [1, 0]}],
		"keys": [[-2.7, -2.0, 0]], "need_keys": 1,
	},
	2: {
		"title_ar": "فناءان", "title_en": "Two Courtyards",
		"time": "day", "weather": "clear",
		"start": [-1.65, 2.4], "start_yaw": 3.1416,
		"walls": [[0.0, -0.3, 0.29, 3.05]],
		"crates": [
			{"at": [-1.65, 0.7], "to": [-1.65, -1.7], "dir": [0, -1]},
			{"at": [1.75, 0.7], "to": [1.75, -1.7], "dir": [0, -1]},
		],
		"sequence": {"pads": [[-2.7, -2.35], [2.8, 2.6], [-2.8, 2.6]], "order": [1, 0, 2, 1]},
		"need_sequence": true,
	},
	3: {
		"title_ar": "الممر المقفل", "title_en": "Locked Passage",
		"time": "dawn", "weather": "clear",
		"start": [-2.5, 2.45],
		"walls": [[-3.63, 0.0, 0.86, 0.3], [1.075, 0.0, 5.55, 0.3], [0.0, -2.08, 0.28, 1.85], [0.0, 1.9, 0.28, 1.15]],
		"keys": [[2.5, 2.1, 0]],
		"doors": [[-2.45, 0.0, 1.5, 0.3, "lock", 0]],
		"gems": [[2.7, -1.8, 0]], "goal_gems": 1,
	},
	4: {
		"title_ar": "الجسران المتناوبان", "title_en": "Alternating Bridges",
		"time": "day", "weather": "clear",
		"start": [0.0, 2.6],
		"walls": [[0.0, -2.02, 0.28, 2.76]],
		"moat": true,
		"bridges": [[-2.3, "choice", 0], [2.3, "choice", 1]],
		"levers": [[0.0, 1.5, 0]],
		"gems": [[-2.3, -2.0, 0], [2.3, -2.0, 1]], "goal_gems": 3,
	},
	5: {
		"title_ar": "قناديل الفناء", "title_en": "Courtyard Lamps",
		"time": "sunset", "weather": "clear",
		"start": [0.0, 2.65],
		"walls": [[-1.55, -1.0, 4.9, 0.3], [3.32, -1.0, 1.35, 0.3], [0.0, 1.8, 0.3, 1.05]],
		"circuit": {"count": 3, "masks": [3, 5, 1], "positions": [[-2.6, 0.7], [0.0, 0.4], [2.6, 0.7]]},
		"doors": [[1.75, -1.0, 1.6, 0.3, "circuit", 0]],
		"gems": [[-2.7, -2.2, 0]], "goal_gems": 1,
		"need_circuit": true,
	},
	6: {
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
	},
	7: {
		"title_ar": "النقش المتسلسل", "title_en": "Carved Sequence",
		"time": "dawn", "weather": "rain",
		"start": [0.0, 2.6],
		"walls": [[0.0, 0.0, 5.15, 0.32]],
		"sequence": {"pads": [[-2.6, 1.8], [2.6, 1.8], [-2.6, -1.7], [2.6, -1.7]], "order": [2, 0, 3, 1, 2]},
		"need_sequence": true,
	},
	8: {
		"title_ar": "الصلة الخفية", "title_en": "Hidden Connection",
		"time": "night", "weather": "clear",
		"start": [1.4, 2.5],
		"walls": [[-0.6, -1.91, 0.3, 3.08], [-2.3, -0.3, 3.4, 0.3], [0.3, 0.0, 1.8, 0.3], [3.6, 0.0, 0.8, 0.3]],
		"portals": [[-2.5, 1.8, -2.6, -1.6]],
		"keys": [[-1.4, -2.5, 0]],
		"doors": [[2.2, 0.0, 1.8, 0.3, "lock", 0]],
		"gems": [[2.5, -1.7, 0]], "goal_gems": 1,
		"roofs": [[0.3, 1.0, 1.6, 1.4]],
	},
	9: {
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
	},
	10: {
		"title_ar": "بوابة الفناء", "title_en": "Courtyard Gate",
		"time": "sunset", "weather": "rain",
		"start": [0.0, 2.95],
		"walls": [[0.0, -2.02, 0.28, 2.76]],
		"moat": true,
		"bridges": [[-2.3, "circuit", 0], [2.3, "final", 0]],
		"keys": [[-2.3, -2.0, 0]],
		"gems": [[2.3, -2.0, 0]], "goal_gems": 1,
		"need_circuit": true, "need_sequence": true, "need_keys": 1,
		"circuit": {"count": 4, "masks": [3, 5, 9, 14], "positions": [[-3.0, 1.1], [-1.0, 1.1], [1.0, 1.1], [3.0, 1.1]]},
		"sequence": {"pads": [[-2.65, 2.5], [0.0, 2.5], [2.65, 2.5]], "order": [2, 0, 1, 2, 1]},
	},
	11: {
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
	},
	12: {
		"title_ar": "الميزان", "title_en": "The Balance",
		"time": "day", "weather": "clear",
		"start": [0.0, 2.8],
		"walls": [[-1.6, -1.2, 4.8, 0.3], [3.35, -1.2, 1.3, 0.3]],
		"balance": {"at": [0.0, 0.0], "weights": [[-3.0, 1.9, 1], [-1.0, 1.9, 2], [1.0, 1.9, 3], [3.0, 1.9, 4]]},
		"doors": [[1.7, -1.2, 1.8, 0.3, "balance", 0]],
		"gems": [[-2.6, -2.3, 0]], "goal_gems": 1,
		"need_balance": true,
	},
	13: {
		"title_ar": "الدور العلوي", "title_en": "Upper Floor",
		"time": "day", "weather": "clear",
		"storeys": true,
		"start": [0.0, 2.8],
		"walls": [],
		"stairs": [[-2.9, "circuit", 0]],
		"circuit": {"count": 4, "masks": [3, 5, 9, 14], "positions": [[-3.0, 2.25], [-1.0, 2.25], [1.0, 2.25], [3.0, 2.25]]},
		"keys": [[2.7, -1.9, 0]], "need_keys": 1,
		"need_circuit": true,
	},
	14: {
		"title_ar": "أقراص بين الطابقين", "title_en": "Dials Across Floors",
		"time": "sunset", "weather": "clear",
		"storeys": true,
		"start": [0.0, 2.8],
		"walls": [],
		"stairs": [[-2.9, "always", 0]],
		"dials": {
			"positions": [[-1.2, 2.2], [1.2, 2.2], [0.6, -1.8]],
			"links": [[1, 1, 0], [0, 1, 1], [1, 0, 1]],
			"target": [3, 2, 1],
		},
		"need_dials": true,
	},
	15: {
		"title_ar": "أوزان السطح", "title_en": "Weights on the Terrace",
		"time": "day", "weather": "rain",
		"storeys": true,
		"start": [0.0, 2.8],
		"walls": [],
		"stairs": [[-2.9, "always", 0]],
		"balance": {"at": [1.1, -1.9], "weights": [[-1.3, 2.1, 1], [1.3, 2.1, 2], [-1.2, -2.3, 3]]},
		"need_balance": true,
	},
	16: {
		"title_ar": "درج الضوء", "title_en": "Stairway of Light",
		"time": "night", "weather": "clear",
		"storeys": true,
		"start": [0.0, 2.9],
		"walls": [],
		"stairs": [[-2.9, "light", 0]],
		"optics": {
			"source": [-3.5, 2.65, 1, 0],
			"mirrors": [[-1.7, 2.65, 1], [-1.7, 1.45, 1], [1.6, 1.45, 0]],
			"receiver": [1.6, 2.65],
		},
		"sequence": {"pads": [[-1.8, -2.0], [0.4, -2.0], [2.6, -2.0]], "order": [2, 0, 1, 2, 1]},
		"need_light": true, "need_sequence": true,
	},
	17: {
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
	},
	18: {
		"title_ar": "الحجرات المتصلة", "title_en": "Connected Chambers",
		"time": "night", "weather": "rain",
		"storeys": true,
		"start": [0.0, 2.95],
		"walls": [[0.0, -2.2, 0.3, 2.3]],
		"stairs": [],
		"portals": [[-2.9, 1.8, -2.9, -1.8], [2.9, 1.8, 2.9, -1.8]],
		"sequence": {"pads": [[-0.9, 2.5], [0.9, 2.5], [-1.8, -2.1], [1.8, -2.1]], "order": [2, 0, 3, 1, 2, 3]},
		"keys": [[-0.9, -1.4, 0]],
		"need_keys": 1, "need_sequence": true,
	},
	19: {
		"title_ar": "القناديل والميزان", "title_en": "Lamps and Balance",
		"time": "sunset", "weather": "clear",
		"storeys": true,
		"start": [0.0, 2.95],
		"walls": [],
		"stairs": [[-2.9, "circuit", 0]],
		"circuit": {"count": 4, "masks": [3, 5, 9, 14], "positions": [[-3.0, 2.5], [-1.0, 2.5], [1.0, 2.5], [3.0, 2.5]]},
		"balance": {"at": [0.6, -1.9], "weights": [[-2.0, 1.5, 1], [0.0, 1.5, 2], [2.0, 1.5, 2], [-1.6, -2.3, 3], [2.8, -2.3, 4]]},
		"need_circuit": true, "need_balance": true,
	},
	20: {
		"title_ar": "البيت الكبير", "title_en": "The Great House",
		"time": "sunset", "weather": "clear",
		"storeys": true,
		"start": [0.0, 2.95],
		"walls": [[0.0, -2.2, 0.3, 2.3]],
		"stairs": [[-2.9, "choice", 0], [2.9, "keyChoice", 1]],
		"levers": [[0.0, 1.5, 0]],
		"dials": {
			"positions": [[-1.1, 2.5], [1.1, 2.5], [2.8, -2.5]],
			"links": [[1, 1, 0], [0, 1, 1], [1, 0, 1]],
			"target": [1, 3, 2],
		},
		"sequence": {"pads": [[-2.1, 1.6], [2.1, 1.6], [-1.4, -2.4], [1.4, -2.4]], "order": [2, 0, 3, 1, 2, 3]},
		"keys": [[-1.4, -1.4, 0]],
		"gems": [[1.4, -1.4, 0]], "goal_gems": 1,
		"need_keys": 1, "need_dials": true, "need_sequence": true,
	},
	21: {
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
	},
}


static func get_level(n: int) -> Dictionary:
	return LEVELS.get(n, {})


static func surface_y(def: Dictionary, _x: float, z: float) -> float:
	if def.get("storeys", false):
		return UPPER_HEIGHT * clampf((0.95 - z) / 1.9, 0.0, 1.0)
	return 0.0


static func exit_y(def: Dictionary) -> float:
	return UPPER_HEIGHT if def.get("storeys", false) else 0.0
