#!/usr/bin/env bash
# Level-select thumbnails (assets/ui/levels/level_NN.jpg) from in-engine screenshots.
# Needs Godot 4.6.3 and a display (on a headless machine: xvfb-run).
#   GODOT=/path/to/godot tools/art/make_thumbnails.sh [first] [last]
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
FIRST="${1:-1}"
LAST="${2:-37}"
TMP="$(mktemp -d)"
RUN=()
command -v xvfb-run >/dev/null && [ -z "${DISPLAY:-}" ] && RUN=(xvfb-run -a -s "-screen 0 1280x720x24")
for n in $(seq "$FIRST" "$LAST"); do
  timeout 240 "${RUN[@]}" "$GODOT" --xr-mode off --rendering-driver opengl3 --path . -- \
    --level="$n" --screenshot="$TMP/l$n.png" --nocard --weather=clear --zoom=1.2 --pitch=55 --yaw=0 >/dev/null 2>&1 || true
  python3 - "$TMP/l$n.png" "assets/ui/levels/level_$(printf %02d "$n").jpg" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
# centre crop to 16:9 around the board, then the thumbnail size used by the menu
cw, ch = int(w * 0.72), int(w * 0.72 * 9 / 16)
x0, y0 = (w - cw) // 2, int((h - ch) * 0.55)
im.crop((x0, y0, x0 + cw, y0 + ch)).resize((480, 270), Image.LANCZOS).save(sys.argv[2], quality=86)
print("thumb", sys.argv[2])
PY
done
rm -rf "$TMP"
