# Browser build (abodengames.com)

The table game in `quest-native/` also runs in the browser, from the same scenes and scripts.

- Build: `quest-native/tools/ci/build_web.sh` (Godot 4.6.3, single-threaded Web template, no
  special server headers). CI: `.github/workflows/pages.yml` deploys it to GitHub Pages; the
  studio site plays it at `/play/mafateeh/`.
- `Save.web` is true in the browser (or with `--web` on the desktop). Then `WebView`
  (`scripts/web/web_view.gd`) stands the table in a virtual Diriyah (`VRScenery`) under a sky that
  follows the level's time of day, and turns the camera round it:
  one finger or the mouse points and presses (the trigger); dragging the sky, two fingers or the
  right mouse button turn the view; pinch or the wheel zoom; the corner button (or Esc) is the menu.
- Menu and intro wording without controllers (tap instead of trigger, no hand or vibration
  settings, no QR code at the end) lives beside the headset wording in `table_menu.gd` and
  `table_intro.gd`.
- Textures, resolution and anti-aliasing are exactly the headset's (owner: quality first; nothing
  is reduced for the web until it has been tried on devices).
- Try it locally: `godot --path quest-native scenes/table.tscn -- --web`, or build and serve
  `build/web/` with any static server.
