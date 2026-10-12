class_name LevelHints
extends RefCounted
## One hint per level (Arabic, English), shown on request from the menu. Each one
## names the idea of the puzzle and the order of steps without solving every move.
## Kept in line with the solver's solutions (tests/run_tests.gd prints them).

const HINTS := {
	1: ["ادفع الصندوق إلى البلاطة المرسوم عليها مثلث ليفتح لك الطريق، ثم خذ المفتاح واتجه للبوابة.",
		"Push the crate onto the plate with the triangle to clear the way, then take the key and head for the gate."],
	2: ["ادفع الصندوقين إلى بلاطتيهما، ثم المس النقوش على الأرض بنفس ترتيب اللوحة فوق البوابة.",
		"Push both crates onto their plates, then touch the floor symbols in the order shown above the gate."],
	3: ["المفتاح يفتح الباب المقفل. خذه، وافتح الباب، واجمع الجوهرة خلفه.",
		"The key opens the locked door. Take it, open the door and collect the gem behind it."],
	4: ["الرافعة تبدّل بين الجسرين. اجمع الجوهرة القريبة، ثم بدّل الجسر واجمع الثانية.",
		"The lever swaps the two bridges. Collect the near gem, switch the bridge, then collect the other."],
	5: ["كل مفتاح يضيء أكثر من قنديل. جرّب الثلاثة مرة واحدة لكل منها، وراقب القناديل فوق البوابة.",
		"Each switch lights more than one lamp. Try each of the three once and watch the lamps above the gate."],
	6: ["دوّر المرايا حتى يصل شعاع الضوء إلى البلورة؛ لا يلزم تدويرها كلها.",
		"Turn the mirrors until the beam reaches the crystal; not all of them need turning."],
	7: ["المس النقوش على الأرض بنفس ترتيب اللوحة فوق البوابة، واحدًا بعد الآخر.",
		"Touch the floor symbols in the order shown above the gate, one after another."],
	8: ["الممر المضيء ينقلك بين الفناءين. خذ المفتاح من الجهة الأخرى، وارجع به إلى الباب المقفل.",
		"The glowing passage takes you between the courtyards. Fetch the key from the far side and bring it back to the locked door."],
	9: ["خذ المفتاح أولًا، ثم حرّك الرافعة، ثم وجّه الضوء بالمرآتين ليظهر الجسر نحو الجوهرة.",
		"Take the key first, then pull the lever, then aim the light with the two mirrors to raise the bridge to the gem."],
	10: ["أضئ القناديل أولًا لتفتح الباب، ثم خذ المفتاح، ثم المس النقوش بترتيب اللوحة فوق البوابة.",
		"Light the lamps first to open the door, then take the key, then touch the symbols in the order above the gate."],
	11: ["كل قرص يحرّك جاره معه. أدِر القرص الأوسط مرة، ثم الأيمن مرتين.",
		"Each dial turns a neighbour too. Turn the middle dial once, then the right dial twice."],
	12: ["الأوزان 1 و2 و3 و4: ضع في كل كفة ما مجموعه 5. الرقم فوق كل كفة يساعدك.",
		"Weights 1, 2, 3 and 4: put a total of 5 in each pan. The number above each pan helps."],
	13: ["شغّل المفاتيح الثلاثة لتُفتح بوابة الدرج، ثم اصعد وخذ المفتاح.",
		"Use the three switches to open the stair gate, then climb up for the key."],
	14: ["أدِر القرص الأيسر الأمامي مرتين، ثم القرص الخلفي مرة واحدة.",
		"Turn the front-left dial twice, then the back dial once."],
	15: ["الأوزان 1 و2 و3: ضع 3 في كل كفة (1+2 مقابل 3). الوزن 3 في الخلف.",
		"Weights 1, 2 and 3: put 3 in each pan (1+2 against 3). The 3 is at the back."],
	16: ["دوّر المرايا الثلاث ليصل الضوء إلى البلورة فيُفتح الدرج، ثم المس النقوش في الأعلى بترتيب اللوحة.",
		"Turn the three mirrors so the light reaches the crystal and opens the stairs, then touch the symbols upstairs in the order shown."],
	17: ["الرافعة تختار الدرج المفتوح. خذ المفتاح، ثم بدّل الرافعة واصعد. أدِر القرص الأول مرة، ثم الثاني مرتين.",
		"The lever picks which stair is open. Take the key, switch the lever and climb. Turn the first dial once, then the second twice."],
	18: ["الممرات المضيئة تربط الطابقين. المس كل نقش في دوره حسب اللوحة، وتنقّل بالممرات بينها.",
		"The glowing passages link the floors. Touch each symbol in turn as shown, using the passages to move between them."],
	19: ["أضئ القناديل الأربعة لتفتح الدرج. ثم الأوزان 1 و2 و2 و3 و4: ضع 6 في كل كفة، مثل 1+2+3 مقابل 2+4.",
		"Light all four lamps to open the stairs. Then weights 1, 2, 2, 3 and 4: put 6 in each pan, such as 1+2+3 against 2+4."],
	20: ["البيت الكبير: الرافعة تبدّل الطريق بين جهتي الطابق العلوي. خذ المفتاح، والمس النقوش بترتيب اللوحة متنقلًا بالرافعة، ثم اضبط الأقراص.",
		"The Great House: the lever switches the way between the two sides upstairs. Take the key, touch the symbols in order using the lever to cross, then set the dials."],
	21: ["احمل الطوبة وضعها في قاعدتها لتعبر الماء، ثم خذ المفتاح وافتح الباب واجمع الجوهرة.",
		"Carry the brick to its socket to cross the water, then take the key, open the door and collect the gem."],
}


static func text(level: int) -> String:
	var h: Array = HINTS.get(level, ["", ""])
	return h[0] if Save.arabic() else h[1]
