# Mafateeh v2 — level campaign (native Quest)

Five chapters of Diriyah (34 levels) and a bonus chapter that opens once every level's secret gem
is found. All level data lives in `quest-native/scripts/core/level_data.gd`; the three-step hints
(idea, first step, full solution) in `level_hints.gd`.

Every row below is verified by the exhaustive solver (`quest-native/tests/solver.gd`) using the game's
own rules: a solution exists, **every reachable state can still be won** (no irreversible traps; level
19 deliberately allows one tempting wrong choice, which undo fixes), the secret gem is reachable, and the
listed gate mechanics cannot be bypassed. **Par** is the shortest solution's number of interactions
(walking is implicit): finishing at par earns three stars, within max(2, ⌈par × 0.3⌉) two, otherwise one.

### 1 · الفناء — The Courtyard

| # | Name | Mechanics | Time / weather | Par | Gates proven necessary |
|---|---|---|---|---|---|
| 1 | الفناء الأول — First Courtyard | keys, crates | day / clear | 2 | — |
| 2 | الممر المقفل — Locked Passage | keys, doors | dawn / clear | 3 | lock |
| 3 | الجسران المتناوبان — Alternating Bridges | lever, moat + bridges | day / clear | 3 | lever |
| 4 | مفتاحان وبابان — Two Keys, Two Doors | keys, doors | day / clear | 4 | lock |
| 5 | الصلة الخفية — Hidden Connection | keys, doors, passage | night / clear | 5 | portal, lock |
| 6 | اسحب الصندوق — Pull the Crate | keys, crates | sunset / clear | 3 | — |
| 7 | الدكّة — The Stone Plate | doors, crates, plates (dakka) | day / clear | 4 | — |

### 2 · السوق — The Souq

| # | Name | Mechanics | Time / weather | Par | Gates proven necessary |
|---|---|---|---|---|---|
| 8 | درب الضوء — Path of Light | light | day / clear | 2 | mirror |
| 9 | المرآة والقنديل — Mirror and Lantern | keys, doors, light | sunset / clear | 3 | mirror |
| 10 | الوزن يمسك الباب — A Weight Holds the Door | doors, plates (dakka), weights | day / clear | 3 | weight |
| 11 | الوزن الزائد — One Weight Too Many | doors, balance | day / clear | 7 | weight, pan |
| 12 | بيت البركة — House of the Pool | keys, doors, pool room | day / rain | 5 | brick, brickSocket, lock |
| 13 | طوبة لأمرين — One Brick, Two Jobs | keys, doors, plates (dakka), brick, stones/water | sunset / clear | 6 | brick, brickSocket |
| 14 | قناديل السوق — Lamps of the Souq | doors, lamp circuit | night / clear | 3 | circuit |

### 3 · الواحة — The Oasis

| # | Name | Mechanics | Time / weather | Par | Gates proven necessary |
|---|---|---|---|---|---|
| 15 | أول فلج — The First Falaj | falaj, sluice, stones/water | dawn / clear | 2 | sluice |
| 16 | الماء يمر بالبركة — Through the Pool | falaj, sluice, stones/water | day / clear | 2 | sluice |
| 17 | الماء والضوء — Water and Light | keys, lever, light, moat + bridges | day / clear | 5 | lever, mirror |
| 18 | شاهين — Shaheen | keys, doors, falcon Shaheen | day / clear | 3 | falcon, lock |
| 19 | اختر بحكمة — Choose Wisely | keys, doors, plates (dakka), stones/water, falcon Shaheen | sunset / clear | 2 | falcon |
| 20 | رافعة لأمرين — One Lever, Two Things | keys, lever, falaj, stones/water, moat + bridges | day / clear | 3 | lever |
| 21 | واحة شاهين — Shaheen's Oasis | doors, crates, plates (dakka), falaj, sluice, stones/water, falcon Shaheen | sunset / clear | 5 | falcon, sluice |

### 4 · القصر — The Palace

| # | Name | Mechanics | Time / weather | Par | Gates proven necessary |
|---|---|---|---|---|---|
| 22 | الأقراص المترابطة — Linked Dials | keys, doors, dials | dawn / clear | 4 | dial |
| 23 | الدور العلوي — Upper Floor | keys, plates (dakka), weights, two floors | day / clear | 3 | weight |
| 24 | أقراص بين الطابقين — Dials Across Floors | dials, two floors | sunset / clear | 3 | dial |
| 25 | أوزان السطح — Weights on the Terrace | balance, two floors | day / rain | 6 | weight |
| 26 | الحمل عبر الممر — Carry Through the Passage | balance, passage, two floors | night / clear | 7 | portal |
| 27 | الدرجان — Two Stairways | keys, lever, dials, two floors | dawn / clear | 5 | lever, key |
| 28 | الرقم في الأعلى — The Number Upstairs | doors, dials, two floors | day / clear | 6 | dial |

### 5 · السطوح — The Rooftops

| # | Name | Mechanics | Time / weather | Par | Gates proven necessary |
|---|---|---|---|---|---|
| 29 | ظل النخلة — Palm Shade | palm shade + sundial | day / clear | 4 | sundial |
| 30 | سطوح بلونين — Two-Colour Rooftops | keys, doors, two floors | sunset / clear | 5 | lock |
| 31 | صهريج الدرج — The Stair Cistern | keys, doors, falaj, sluice, stones/water, two floors | day / clear | 4 | sluice |
| 32 | الصندوق والظل — The Crate and the Shade | doors, crates, plates (dakka), palm shade + sundial | day / clear | 5 | — |
| 33 | مرايا الليل — Night Mirrors | light, passage | night / clear | 3 | mirror |
| 34 | بيت الجد — Grandfather's House | coloured keys, dials, two floors | sunset / clear | 6 | dial, lock |

### ★ ديوان الجد — Grandfather's Diwan (bonus: all 34 secret gems)

| # | Name | Mechanics | Time / weather | Par | Gates proven necessary |
|---|---|---|---|---|---|
| 35 | شاهين والفلج — Shaheen and the Falaj | coloured keys, doors, falaj, sluice, stones/water, falcon Shaheen | dawn / clear | 4 | falcon, lock, sluice |
| 36 | ميزان الديوان — The Diwan Scales | balance, dials, two floors | night / clear | 11 | dial |
| 37 | سرّ الجد — Grandfather's Secret | doors, crates, plates (dakka), falcon Shaheen | sunset / clear | 5 | falcon, crate |

Time and weather are visual only and never change puzzle state (integration-tested for all
4 × 2 presets). Roofed passages (levels 8 and 21) have no interactable underneath (tested), lift away
when the hero walks under them, and muffle the rain sound indoors.

## Readability without colour alone

Every coloured puzzle element also carries a shape: ring, triangle, diamond or cross (sequence tiles
and the clue tablet, lamps and switch markers, dial links and target marks, key emblems, door plaques
showing what opens them). The clue tablet reads left to right from its arrow and lights up step by step.

## Findings from the port

The solver found **no impossible state, dead end or collision bypass** in the original level data under
the ported rules. Differences from the web version, all deliberate:

1. **Levels 1–2 collision now comes from the same wall data as the visuals.** The web version used
   hand-typed collision rectangles for the two dividers that were 0.02–0.03 units larger than the drawn
   walls; collision and geometry now match exactly.
2. **Every action re-checks for trapping, not only the ones the web version listed.** Any interaction
   that would close a door, bridge or stair gate on top of the character is undone and gently rejected
   (the web version did this for levers, switches, dials, pans and the brick; it now also covers
   mirrors, sequences and portals). No current level can trigger it; it guards future level edits.
3. **Keys and gems are also collected while walking a selected route**, not only while steering with
   the stick, so the two control styles behave the same.
4. **Interactions play an animation before the state changes** (about 0.4–0.7 s), so pick-up,
   placement, levers and switches read clearly; the solver and movement tests include this timing.
5. **The carried brick can be put down only on clear floor** inside the courtyard (never in walls,
   water, closed gates or off the board), and the drop always leaves the character free — verified by
   sampling drop positions in the dead-end search.
