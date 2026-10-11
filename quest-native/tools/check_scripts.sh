#!/usr/bin/env bash
# Parse-checks every GDScript file (autoload "Save" is unknown in --check-only mode and ignored).
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
status=0
for f in $(find scripts tests -name "*.gd"); do
  out=$("$GODOT" --headless --xr-mode off --path . --check-only --script "$f" 2>&1 | grep -A1 "SCRIPT ERROR" | awk '/SCRIPT ERROR/ {e=$0; next} /at:/ {if (e !~ /Identifier not found: Save|Failed to compile depended/) print e "\n" $0}')
  if [ -n "$out" ]; then echo "$out"; status=1; fi
done
exit $status
