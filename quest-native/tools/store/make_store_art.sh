#!/usr/bin/env bash
# Renders Meta Horizon Store art from the real game scenes (desktop renderer).
# Output: ../store/  (repo root, not part of the Godot project or the APK).
# Sizes follow Meta's asset guidelines: cover landscape 2560x1440, square 1440x1440,
# portrait 1008x1440, hero 3000x900, screenshots 2560x1440, trailer cover 2560x1440.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="$(cd .. && pwd)/store"
mkdir -p "$OUT/screenshots"
GODOT="${GODOT:-godot}"
shot() {  # out WxH level time weather yaw pitch zoom [extra args...]
  local out=$1 res=$2 level=$3 time=$4 weather=$5 yaw=$6 pitch=$7 zoom=$8; shift 8
  local w=${res%x*} h=${res#*x}
  xvfb-run -a -s "-screen 0 $((w+64))x$((h+64))x24" "$GODOT" --xr-mode off --rendering-driver opengl3 \
    --resolution "$res" --path . -- --level="$level" --time="$time" --weather="$weather" \
    --yaw="$yaw" --pitch="$pitch" --zoom="$zoom" --nocard --noscenery --screenshot="$out" "$@" >/dev/null 2>&1
  # Meta asks for 24-bit PNG (no alpha channel).
  python3 -c "from PIL import Image; Image.open('$out').convert('RGB').save('$out')"
  echo "$out"
}
# Cover art (branded with the exact app name).
shot "$OUT/cover_landscape_2560x1440.png" 2560x1440 20 sunset clear -25 42 1.25 --title=line
shot "$OUT/cover_square_1440x1440.png" 1440x1440 21 sunset clear 200 24 3.2 --focus_hero --title=stack
shot "$OUT/cover_portrait_1008x1440.png" 1008x1440 13 sunset clear 15 46 0.78 --title=stack
shot "$OUT/hero_3000x900.png" 3000x900 20 sunset clear 25 34 2.3 --title=line
shot "$OUT/trailer_cover_2560x1440.png" 2560x1440 4 dawn clear 25 44 1.2 --title=line
# Screenshots (no text).
shot "$OUT/screenshots/01_great_house_sunset.png" 2560x1440 20 sunset clear 30 46 1.2
shot "$OUT/screenshots/02_pool_house_rain.png" 2560x1440 21 day rain -20 48 1.2
shot "$OUT/screenshots/03_stairway_of_light_night.png" 2560x1440 16 night clear 20 50 1.25
shot "$OUT/screenshots/04_hero_close.png" 2560x1440 1 day clear 200 20 4.5 --focus_hero
shot "$OUT/screenshots/05_alternating_bridges.png" 2560x1440 4 day clear 25 45 1.2
shot "$OUT/screenshots/06_balance_terrace_rain.png" 2560x1440 15 day rain -30 45 1.2
shot "$OUT/screenshots/07_carved_sequence_dawn.png" 2560x1440 7 dawn clear 15 52 1.25
