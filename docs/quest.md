# Quest controls and device verification

Open the HTTPS game URL in Meta Quest Browser. Choose VR or AR. AR requires `local-floor` and `hit-test`; denied or unavailable surface tracking shows an error instead of placing a fake tracked surface.

- Trigger: select a destination, puzzle object or numbered stage tile. Puzzle interactions still use the trigger.
- AR placement: look at a horizontal real surface until the gold ring appears, then press the trigger.
- Grip: re-place the AR board or re-center the VR board.
- Left stick: rotate horizontally; resize vertically.
- Right stick: move the character relative to your viewing direction. Releasing it stops movement; walls, water and closed stairs remain solid. Walk into a crate from its pushing side to push it.
- The small board dock also provides size, re-place, stage selection and exit controls. Quest's system UI can end the session.

On mobile, the small touch stick moves the character; taps still interact and dragging the scene still rotates the view. Arrow keys or WASD work on desktop.

The interaction model is a miniature board, not first-person locomotion. No account, backend, external asset service or API key is required. Progress is local to the browser and origin; the older Sites save is not automatically transferred to GitHub Pages.

## Verification status

Automated checks cover all 21 room spawns, geometry validity, room 21 interactions/completion, mock XR surface placement, model scaling/rotation, ray transformation, controller selection, mode exit/restore, both session types, right-stick movement, controller release/disconnection, view-relative direction, multi-touch ownership and movement collisions. These checks do not measure real GPU rendering, passthrough stability or headset frame rate.

On Quest, verify: both eyes render correctly; AR surface ring follows a real table/floor; trigger places the board; interaction remains aligned after resizing/rotation; stairs and pool work; stage changes retain placement; session exit returns to working mobile/desktop controls.

## Deployment

The Pages workflow publishes `index.html`, `src/`, and `vendor/`. If automatic Pages setup is unavailable, select **GitHub Actions** under repository **Settings → Pages** and rerun the workflow.
