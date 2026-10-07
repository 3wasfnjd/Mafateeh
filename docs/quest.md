# Quest controls and device verification

Open the HTTPS game URL in Meta Quest Browser. Choose VR or AR. AR requires `local-floor` and `hit-test`; denied or unavailable surface tracking shows an error instead of placing a fake tracked surface.

- Trigger: select a destination, puzzle object or numbered stage tile.
- AR placement: look at a horizontal real surface until the gold ring appears, then press the trigger.
- Grip: re-place the AR board or re-center the VR board.
- Left stick: rotate horizontally; resize vertically.
- Right stick: move the model horizontally along the placement plane.
- The small board dock also provides size, re-place, stage selection and exit controls. Quest's system UI can end the session.

The interaction model is a miniature board, not first-person locomotion. No account, backend, external asset service or API key is required. Progress is local to the browser and origin; the older Sites save is not automatically transferred to GitHub Pages.

## Verification status

Automated checks cover all 21 room spawns, geometry validity, room 21 interactions/completion, mock XR surface placement, model scaling/rotation, ray transformation, controller selection, mode exit/restore and both session types. These checks do not measure real GPU rendering, passthrough stability or headset frame rate.

On Quest, verify: both eyes render correctly; AR surface ring follows a real table/floor; trigger places the board; interaction remains aligned after resizing/rotation; stairs and pool work; stage changes retain placement; session exit returns to working mobile/desktop controls.

## Deployment

The Pages workflow publishes `index.html`, `src/`, and `vendor/`. If automatic Pages setup is unavailable, select **GitHub Actions** under repository **Settings → Pages** and rerun the workflow.
