# Mafateeh — level campaign (native Quest)

All puzzle values (positions, sequences, circuit masks, dial links and targets, weights, portal
pairs, mirror layouts and win conditions) are ported verbatim from the web reference
(`src/game.js`, `roomDefs`) into `quest-native/scripts/core/level_data.gd`. The architecture and
presentation are rebuilt from the Najdi kit; the core mechanic of every level is unchanged.

Every row below is verified by the exhaustive solver (`quest-native/tests/solver.gd`) using the game's
own rules: a solution exists, **every reachable state can still be won** (no irreversible traps),
and the listed gate mechanics cannot be bypassed (forbidding them makes the level unsolvable).
"Actions" is the shortest solution's number of interactions; walking between them is implicit.

| # | Name | Mechanics | Time / weather | Actions | Gates proven necessary |
|---|---|---|---|---|---|
| 1 | الفناء الأول — First Courtyard | crate → pressure plate, key, exit | day / clear | 3 | — |
| 2 | فناءان — Two Courtyards | two crates on separate routes, 4-step symbol sequence | day / clear | 7 | — |
| 3 | الممر المقفل — Locked Passage | key, locked inner door, gem | dawn / clear | 4 | lock |
| 4 | الجسران المتناوبان — Alternating Bridges | lever swaps which bridge stands; both gems | day / clear | 4 | lever |
| 5 | قناديل الفناء — Courtyard Lamps | three switches toggling linked lamps, lamp door, gem | sunset / clear | 5 | switches |
| 6 | درب الضوء — Path of Light | rotate mirrors; walls block the beam | day / clear | 3 | — |
| 7 | النقش المتسلسل — Carved Sequence | 5-step sequence across a dividing wall | dawn / rain | 6 | — |
| 8 | الصلة الخفية — Hidden Connection | relocation passage, key, locked door, gem | night / clear | 6 | passage, lock |
| 9 | الماء والضوء — Water and Light | lever bridges + lit bridge (mirrors), key, gem | day / clear | 6 | lever, mirrors |
| 10 | بوابة الفناء — Courtyard Gate | 4-lamp circuit bridge, sequence + key bridge, gem | sunset / rain | 11 | switches, sequence |
| 11 | الأقراص المترابطة — Linked Dials | three linked dials open the key room | dawn / clear | 5 | dials |
| 12 | الميزان — The Balance | four weights (1–4) balanced on two pans | day / clear | 10 | weights, pans |
| 13 | الدور العلوي — Upper Floor | lamp circuit opens the stair gate; key upstairs | day / clear | 5 | switches |
| 14 | أقراص بين الطابقين — Dials Across Floors | linked dials on both floors | sunset / clear | 4 | dials |
| 15 | أوزان السطح — Weights on the Terrace | carry weights upstairs to the terrace balance | day / rain | 7 | weights |
| 16 | درج الضوء — Stairway of Light | light opens the stairs, then a sequence upstairs | night / clear | 9 | mirrors |
| 17 | الدرجان — Two Stairways | lever picks a stairway; key opens the second; dials | dawn / clear | 6 | lever, key |
| 18 | الحجرات المتصلة — Connected Chambers | two relocation passages between floors, 6-step sequence, key | night / rain | 15 | passages |
| 19 | القناديل والميزان — Lamps and Balance | circuit opens the stairs; five weights between floors | sunset / clear | 14 | switches, weights |
| 20 | البيت الكبير — The Great House | lever + key stairways, dials, sequence, key, gem | sunset / clear | 15 | lever, key |
| 21 | بيت البركة — House of the Pool | lift the brick from the entrance, set it on its socket to raise the stepping stones, key, inner door, gem | day / rain | 6 | brick, socket, lock |

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
