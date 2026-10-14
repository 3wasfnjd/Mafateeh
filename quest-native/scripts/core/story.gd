class_name Story
extends RefCounted
## Story scenes told as short pages on the Najdi menu panel (SettingsMenu "story"
## page). Pure text data: edit the pages here, nothing else needs to change.
##   studio    — the Aboden Games (عبودين قيمز) story; shown once before the prologue
##               and from Credits → «قصتنا». Empty = skipped and the button hidden.
##   prologue  — before the first level (once; replay from Credits)
##   epilogue  — after the last main level (Grandfather's house opens)
##   bonus_end — after the bonus chapter
## A page: {"ar": ..., "en": ..., "image": optional res:// path (wide picture)}.

const TITLES := {
	"studio": ["عبودين قيمز", "Aboden Games"],
	"prologue": ["مفاتيح", "Mafateeh"],
	"epilogue": ["بيت الجد", "Grandfather's House"],
	"bonus_end": ["ديوان الجد", "Grandfather's Diwan"],
}

# TODO(story): the studio's own story goes here, written by the studio.
const STUDIO := []

const PROLOGUE := [
	{"ar": "في الدرعية، بين النخيل وبيوت الطين، ضاعت مفاتيح بيت الجد.",
		"en": "In Diriyah, among the palms and mud-brick houses, the keys to Grandfather's house were lost."},
	{"ar": "تفرّقت المفاتيح بين الفناء والسوق والواحة والقصر والسطوح.",
		"en": "They are scattered across the courtyard, the souq, the oasis, the palace and the rooftops."},
	{"ar": "الشايب يعرف دروبها كلها، ومعه عصاه… وفي الواحة يلحقه صقره شاهين.",
		"en": "The old man knows every lane, cane in hand… and in the oasis his falcon Shaheen joins him."},
	{"ar": "ساعده يفتح الأبواب، ويجمع المفاتيح، ويرجع إلى بيت الجد.",
		"en": "Help him open the doors, gather the keys and return to Grandfather's house."},
]

const EPILOGUE := [
	{"ar": "رجعت المفاتيح كلها، وانفتح باب بيت الجد من جديد.",
		"en": "Every key is back, and Grandfather's door opens once more."},
	{"ar": "وفي البيت سرّ أخير: من يجمع الجواهر السرية كلها، ينفتح له ديوان الجد.",
		"en": "One secret remains: whoever finds every secret gem will see Grandfather's diwan open."},
]

const BONUS_END := [
	{"ar": "انفتح ديوان الجد، وصارت أسراره كلها بين يديك.",
		"en": "Grandfather's diwan is open, and all its secrets are yours."},
	{"ar": "شكرًا لأنك لعبت مفاتيح.",
		"en": "Thank you for playing Mafateeh."},
]


static func pages(scene: String) -> Array:
	match scene:
		"studio": return STUDIO
		"prologue": return PROLOGUE
		"epilogue": return EPILOGUE
		"bonus_end": return BONUS_END
	return []


static func has(scene: String) -> bool:
	return not pages(scene).is_empty()


static func title(scene: String, arabic: bool) -> String:
	var t: Array = TITLES.get(scene, ["", ""])
	return t[0] if arabic else t[1]
