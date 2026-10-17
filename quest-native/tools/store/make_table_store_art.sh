#!/usr/bin/env bash
# Store art for the tabletop game (scenes/table.tscn), rendered with the desktop renderer:
# screenshots (no text) and covers (with the name). Output: ../store/ at the repo root.
# Sizes follow Meta's asset guidelines. Usage: GODOT=... tools/store/make_table_store_art.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="$(cd .. && pwd)/store"
mkdir -p "$OUT/screenshots"
GODOT="${GODOT:-godot}"
shot() {  # out WxH [game args...]   rendered at twice the size and scaled down: smooth edges
  local out=$1 res=$2; shift 2
  local w=${res%x*} h=${res#*x}
  local W=$((w * 2)) H=$((h * 2))
  xvfb-run -a -s "-screen 0 $((W+64))x$((H+64))x24" "$GODOT" --xr-mode off --rendering-driver opengl3 \
    --resolution "${W}x${H}" --path . scenes/table.tscn -- --screenshot="$out" --start=play "$@" >/dev/null 2>&1
  python3 -c "from PIL import Image; Image.open('$out').convert('RGB').resize(($w, $h), Image.LANCZOS).save('$out')"   # 24-bit
  echo "$out"
}
S="$OUT/screenshots"
# Screenshots: the game as played, looking down into the scene from close by so the scene
# fills the whole picture (Meta rejects empty borders), no text, logos or overlays.
R="--room=1 --k=3.8 --cam=0,1.6,0.3,0,-50"
shot "$S/01_courtyard_cat.png" 2560x1440 --level=1 $R --wait=14
shot "$S/02_falcon_perches.png" 2560x1440 --level=3 $R --wait=14
shot "$S/03_camp_cars.png" 2560x1440 --level=4 $R --wait=14
shot "$S/04_lanterns_evening.png" 2560x1440 --level=5 $R --solved=1 --wait=60
shot "$S/05_drums.png" 2560x1440 --level=6 $R --wait=14
shot "$S/06_market.png" 2560x1440 --level=8 $R --wait=14
shot "$S/07_raid.png" 2560x1440 --level=10 $R --wait=110
shot "$S/08_chest_salute_night.png" 2560x1440 --level=11 $R --solved=1 --wait=60
# Covers (the exact app name on them, in the sky above the table).
shot "$OUT/cover_landscape_2560x1440.png" 2560x1440 --level=1 --k=2.2 --cam=0,1.42,0.75,0,-12 --sky=day --title=line --wait=14
shot "$OUT/cover_square_1440x1440.png" 1440x1440 --level=1 --k=2.0 --cam=0,1.45,0.75,0,-14 --sky=day --title=stack --wait=14
shot "$OUT/cover_portrait_1008x1440.png" 1008x1440 --level=1 --k=1.6 --cam=0,1.45,0.8,0,-14 --sky=day --title=stack --wait=14
shot "$OUT/hero_3000x900.png" 3000x900 --level=10 --k=2.4 --cam=0.35,1.4,0.75,10,-8 --sky=day --title=line --wait=110
shot "$OUT/mini_landscape_1080x360.png" 1080x360 --level=1 --k=2.2 --cam=0,1.4,0.8,0,-6 --sky=day --title=line --wait=14
shot "$OUT/trailer_cover_2560x1440.png" 2560x1440 --level=5 --k=2.4 --cam=0,1.42,0.75,0,-12 --sky=day --solved=1 --title=line --wait=60
