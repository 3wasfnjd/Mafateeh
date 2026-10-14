#!/usr/bin/env bash
# Headless test suite: rules/solver/movement/save (tests/run_tests.gd), then the
# integration scene (real main scene, desktop fallback), then audio asset checks.
# Usage: tools/run_tests.sh [-- --levels=1,2 --report=out.txt]
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
PY="${PYTHON:-python3}"
"$GODOT" --headless --xr-mode off --path . --import >/dev/null 2>&1 || true
REPORT=""
for a in "$@"; do case "$a" in --report=*) REPORT="${a#--report=}";; esac; done
status=0
UNIT=$("$GODOT" --headless --xr-mode off --path . -s tests/run_tests.gd "$@" 2>&1 | grep -v "OpenXR-Loader")
echo "$UNIT"
echo "$UNIT" | grep -q "RESULT: PASS" || status=1
echo
echo "== Integration (main scene)"
INT=$("$GODOT" --headless --xr-mode off --path . res://tests/integration_test.tscn 2>&1 | grep -E "✗|INTEGRATION|FAIL:|SCRIPT ERROR")
echo "$INT"
echo "$INT" | grep -q "INTEGRATION: PASS" || status=1
echo "$INT" | grep -q "SCRIPT ERROR" && status=1
echo
echo "== Draw budget (static proxy; real frame time needs a headset)"
DRW=$("$GODOT" --headless --xr-mode off --path . res://tests/draw_budget.tscn 2>&1 | grep -E "^level|DRAW_BUDGET")
echo "$DRW" | tail -1
echo "$DRW" | grep -q "PASS" || status=1
echo
echo "== Audio assets"
AUD=$("$PY" tools/audio/check_audio.py audio 2>&1 | tail -4)
echo "$AUD"
echo "$AUD" | grep -q "RESULT: PASS" || status=1
if [ -n "$REPORT" ]; then
  { echo; echo "== Integration (main scene)"; echo "$INT"; echo; echo "== Draw budget"; echo "$DRW"; echo; echo "== Audio assets"; echo "$AUD"; } >> "$REPORT"
fi
echo
echo "SUITE: $([ $status -eq 0 ] && echo PASS || echo FAIL)"
exit $status
