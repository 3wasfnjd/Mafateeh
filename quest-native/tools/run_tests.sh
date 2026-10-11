#!/usr/bin/env bash
# Runs the headless test suite. Usage: tools/run_tests.sh [-- --levels=1,2 --report=out.txt]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --xr-mode off --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --xr-mode off --path . -s tests/run_tests.gd "$@" 2>&1 | grep -v "OpenXR-Loader"
exit "${PIPESTATUS[0]}"
