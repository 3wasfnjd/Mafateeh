#!/usr/bin/env bash
# Store art for the tabletop game (scenes/table.tscn), rendered with the desktop renderer:
# screenshots (no text) and covers (with the name). Output: ../store/ at the repo root.
# Sizes follow Meta's asset guidelines. Usage: GODOT=... tools/store/make_table_store_art.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="$(cd .. && pwd)/store"
mkdir -p "$OUT/screenshots"
GODOT="${GODOT:-godot}"
shot() {  # out WxH [game args...]
  local out=$1 res=$2; shift 2
  local w=${res%x*} h=${res#*x}
  xvfb-run -a -s "-screen 0 $((w+64))x$((h+64))x24" "$GODOT" --xr-mode off --rendering-driver opengl3 \
    --resolution "$res" --path . scenes/table.tscn -- --screenshot="$out" --start=play "$@" >/dev/null 2>&1
  python3 -c "from PIL import Image; Image.open('$out').convert('RGB').save('$out')"   # 24-bit, no alpha
  echo "$out"
}
S="$OUT/screenshots"
shot "$S/01_courtyard_cat.png" 2560x1440 --level=1 --k=2.4 --cam=0,1.55,0.55,0,-28 --sky=day --wait=14
shot "$S/02_camp_cars.png" 2560x1440 --level=4 --k=2.4 --cam=0,1.6,0.5,0,-30 --sky=day --wait=14
shot "$S/03_lanterns_evening.png" 2560x1440 --level=5 --k=2.6 --cam=0,1.5,0.55,0,-26 --sky=day --solved=1 --wait=60
shot "$S/04_stars_night.png" 2560x1440 --level=7 --k=2.4 --cam=0,1.5,0.55,0,-26 --sky=night --wait=14
shot "$S/05_water_channels.png" 2560x1440 --level=9 --k=2.4 --cam=0,1.6,0.5,0,-30 --sky=day --wait=14
shot "$S/06_market.png" 2560x1440 --level=8 --k=2.4 --cam=0,1.5,0.55,0,-26 --sky=day --wait=14
shot "$S/07_raid.png" 2560x1440 --level=10 --k=2.6 --cam=0.35,1.5,0.6,10,-27 --sky=day --wait=110
shot "$S/08_chest_salute_night.png" 2560x1440 --level=11 --k=2.6 --cam=0,1.5,0.55,0,-26 --sky=night --solved=1 --wait=60
# Covers (the exact app name on them, in the sky above the table).
shot "$OUT/cover_landscape_2560x1440.png" 2560x1440 --level=1 --k=2.2 --cam=0,1.42,0.75,0,-12 --sky=day --title=line --wait=14
shot "$OUT/cover_square_1440x1440.png" 1440x1440 --level=1 --k=2.0 --cam=0,1.45,0.75,0,-14 --sky=day --title=stack --wait=14
shot "$OUT/cover_portrait_1008x1440.png" 1008x1440 --level=1 --k=1.6 --cam=0,1.45,0.8,0,-14 --sky=day --title=stack --wait=14
shot "$OUT/hero_3000x900.png" 3000x900 --level=10 --k=2.4 --cam=0.35,1.4,0.75,10,-8 --sky=day --title=line --wait=110
shot "$OUT/mini_landscape_1080x360.png" 1080x360 --level=1 --k=2.2 --cam=0,1.4,0.8,0,-6 --sky=day --title=line --wait=14
shot "$OUT/trailer_cover_2560x1440.png" 2560x1440 --level=5 --k=2.4 --cam=0,1.42,0.75,0,-12 --sky=day --solved=1 --title=line --wait=60
