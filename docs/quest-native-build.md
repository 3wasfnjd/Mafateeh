# Mafateeh for Meta Quest — build and project guide

The native game lives in `quest-native/` (Godot project). The web game in the repository root
stays as the reference implementation and fallback.

## Pinned versions

| Tool | Version | Where it is pinned |
|---|---|---|
| Godot Engine editor + export templates | 4.6.3-stable (SHA-512 checked) | `quest-native/tools/ci/build_apk.sh` |
| Godot OpenXR Vendors plugin (Meta) | 5.1.0-stable (`compatibility_minimum = 4.6`) | vendored in `quest-native/addons/godotopenxrvendors/` |
| Renderer | GL Compatibility (OpenGL ES 3, multiview) | `project.godot` |
| JDK | Temurin 17 | `.github/workflows/quest-apk.yml` |
| Android compile/target SDK | 36 (from Godot 4.6.3 `config.gradle`) | Godot template |
| Android build-tools | 36.1.0 | `build_apk.sh` |
| Android NDK | 29.0.14206865 | `build_apk.sh` |
| min SDK | 24 (Godot default) | Godot template |
| Runner | `ubuntu-24.04` | workflow |
| Blender (asset authoring only) | 5.2.2 LTS via the `bpy` Python module | `tools/blender/*.py` |
| Audio/texture generation | Python 3.13, NumPy 2.3.3, SciPy 1.16.2, Pillow | `tools/audio`, `tools/art` |

The Android values were read from the Godot 4.6.3 sources (`platform/android/java/app/config.gradle`),
not guessed. The Meta export options were read from the plugin's `meta_export_plugin.cpp`.

## Building the APK without installing an editor (GitHub Actions)

Workflow: `.github/workflows/quest-apk.yml` → runs `quest-native/tools/ci/build_apk.sh`.

1. Downloads Godot 4.6.3 and its export templates from the official `godotengine/godot-builds`
   release and verifies SHA-512; installs Android platform 36, build-tools 36.1.0 and NDK.
2. Imports the project and runs the full headless test suite (see below). A failing test fails the build.
3. Installs the Godot Android build template and exports the **release** APK with Gradle
   (the OpenXR Vendors plugin requires a Gradle build).
4. Verifies the result and fails the build unless: the APK signature verifies (`apksigner`), only
   `arm64-v8a` native code is present, the manifest has `com.oculus.intent.category.VR` and
   `org.khronos.openxr.intent.category.IMMERSIVE_HMD`, and the package is `com.abodengames.mafateeh`.
5. Uploads the APK, its SHA-256 and the test/verification reports as a workflow artifact.
6. Publishes a GitHub **pre-release** (public download link) when the workflow is started manually
   with *publish* ticked (Actions → Quest APK → Run workflow), or when a commit message contains `[release]`.

Version name comes from `application/config/version` in `project.godot`; the version code is the
workflow run number.

### Signing

- Default: `quest-native/tools/ci/test-signing/mafateeh-test.keystore` — a **public, test-only** key
  (see its README). Fine for sideloading; never for a store submission.
- Private release key: add repository secrets `MAFATEEH_KEYSTORE_B64` (base64 of the keystore),
  `MAFATEEH_KEYSTORE_ALIAS` and `MAFATEEH_KEYSTORE_PASSWORD`. The build then signs with that key.
  Never commit a production key or password.

The build report states which key signed the APK.

## Building locally (optional)

With Godot 4.6.3, export templates, JDK 17 and an Android SDK (platform 36, build-tools 36.1.0):

```
cd quest-native
bash tools/ci/build_apk.sh          # same script as CI; writes ../build/*.apk
```

## Tests

```
cd quest-native
tools/run_tests.sh                   # all suites (needs Python + NumPy for the audio check)
tools/run_tests.sh -- --levels=1,21  # limit the solver to some levels
tools/check_scripts.sh               # parse-check every GDScript file
```

| Suite | What it proves |
|---|---|
| `tests/run_tests.gd` — level data | 37 levels (5 chapters + bonus), chapters, secret gems and three hint steps for each, valid spawns, valid time/weather presets, no interactable hidden under a roof |
| `tests/solver.gd` | Exhaustive search with the real rules: every level has a solution; **no reachable state is a dead end** (no irreversible traps); forbidding each gate mechanic (lock, lever, portal, brick socket, …) makes the level unsolvable, i.e. **no collision bypass** |
| `tests/run_tests.gd` — movement | Stops at walls, closed doors, water and closed stairs; walks up/down stairs; no diagonal speed advantage; release stops immediately; interruption requires re-centring the stick; crates push only from the correct side; carried brick stays attached and cannot be dropped into walls; keys collect on contact |
| `tests/run_tests.gd` — save | Progressive unlock and persistence across reload |
| `tests/integration_test.tscn` | Boots the real main scene: footsteps follow animation contacts and stop on release; level 21 completed through the game controller; gameplay and mechanism sounds fire; all time×weather presets leave puzzle state untouched and keep ambient light readable; rain stops on roofs and is muffled indoors; pause/mute; exit → unlock → next level; developer tools hidden |
| `tests/draw_budget.tscn` | Static draw-item budget per level (≤ 400) — a proxy only |
| `tools/audio/check_audio.py` | Every referenced sound exists; no clipping; seamless loops; stone vs wood footsteps are spectrally distinct |

None of these replace testing on a headset: rendering in both eyes, passthrough, comfort,
frame rate and thermals can only be verified on a Quest.

## Project structure

```
quest-native/
  project.godot, export_presets.cfg, openxr_action_map.tres
  scripts/core/    level_data.gd (34 levels in 5 chapters + 3 bonus, data only) · puzzle_state.gd
                   (rules, undo snapshots) · navigator.gd (collision, pathfinding) · hero_motor.gd
                   (character control) · save_data.gd (autoload: progress, stars, secret gems,
                   wardrobe, settings) · level_hints.gd (three hint steps per level, AR/EN) ·
                   wardrobe.gd (unlockable outfits)
  scripts/xr/      xr_rig.gd (OpenXR, passthrough, controller input) · board_placement.gd
                   (board transform, scale, drag, surface snap) · scene_surfaces.gd +
                   scene_anchor_probe.gd (Meta Scene API tables/floors)
  scripts/game/    game.gd (level lifecycle, picking, undo, stars) · hero_view.gd (animation, face,
                   wardrobe, footsteps) · shemagh_spring.gd (secondary motion) ·
                   falcon_companion.gd (Shaheen on the old man's shoulder)
  scripts/art/     kit.gd (shared materials, kit pieces) · level_view.gd (level visuals) ·
                   falcon_view.gd
  scripts/env/     sky_weather.gd (time of day, automatic day/rain cycle) · rain_field.gd (weather) ·
                   dust_field.gd (light dust) · vr_scenery.gd · life_layer.gd (sparrows, cat,
                   villagers, finale ardah)
  scripts/audio/   game_audio.gd
  scripts/ui/      settings_menu.gd (start screen with the Aboden Games name and MR/VR choice,
                   Najdi-styled menu, level cards, hints, wardrobe, settings tabs) ·
                   celebration.gd (Diriyah-style level-complete panel)
  assets/character/shaib.glb · assets/creatures (falcon, cat, sparrow) · assets/kit/najdi_kit.glb · assets/textures · assets/fonts · assets/ui (menu icons, level thumbnails)
  audio/sfx, audio/ambience (generated WAV, imported as QOA)
  art_source/      editable Blender files (ignored by Godot, not packaged)
  tools/blender/   build_shaib.py (+ shaib_textures.py, shaib_anim.py), build_creatures.py,
                   build_kit.py, render_shaib.py, render_glb.py, render_kit.py
  tools/audio/     generate_audio.py, check_audio.py
  tools/art/       make_textures.py, make_icon.py, make_icons.py (menu icons), make_identity.py
                   (Sadu band, Najdi star, crenels, petals), make_thumbnails.sh (level cards)
  tests/           solver, unit, integration and budget tests (not packaged)
```

Level data, puzzle state, character control, XR input, board placement, rendering, time of day,
weather, save data and audio are separate modules; weather and time never read or write puzzle state.

## Regenerating assets

```
python -m venv /opt/bpyenv && /opt/bpyenv/bin/pip install bpy==5.2.2
/opt/bpyenv/bin/python tools/blender/build_shaib.py -- assets/character       # shaib.glb + art_source/character/shaib.blend
/opt/bpyenv/bin/python tools/blender/build_creatures.py                       # falcon/cat/sparrow.glb + art_source/creatures
/opt/bpyenv/bin/python tools/blender/render_shaib.py                          # review renders (turnaround, faces, clips)
/opt/bpyenv/bin/python tools/blender/build_kit.py -- assets/kit               # najdi_kit.glb + art_source/kit/najdi_kit.blend
python3 tools/art/make_textures.py assets/textures
python3 tools/art/make_icons.py assets/ui/icons
python3 tools/art/make_identity.py assets/ui/identity
GODOT=godot tools/art/make_thumbnails.sh 1 37                                  # needs a display or xvfb-run
python3 tools/audio/generate_audio.py audio                                   # needs numpy + scipy
python3 tools/art/make_brand.py assets/brand <cairo-arabic.ttf> <cairo-latin.ttf> ../store  # studio mark
```

All are deterministic (fixed seeds). The `.blend` files can be edited directly in Blender 5.2;
re-export with the same names to keep the game's lookups working.

## Developer options

- Players can replay any level they have reached (menu → *Levels*, or previous/next). Developer
  tools unlock every level and add time and weather overrides: settings panel → *About* → tap the title seven
  times (toggles developer tools on this device), or set `mafateeh/dev/level_select=true` in
  `project.godot` for a developer build. `mafateeh/dev/force_time` / `force_weather` force a preset.
- Desktop run without a headset (for development and screenshots): run the project normally; it falls
  back to an orbit camera. Keys: WASD move, mouse click interact, right-drag orbit, R restart,
  N/P next/previous level, T cycle time, Y toggle rain. Command line:
  `godot --path quest-native -- --level=16 --time=night --weather=rain --screenshot=out.png`.
