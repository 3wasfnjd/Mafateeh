#!/usr/bin/env bash
# Browser build of the table game (used by .github/workflows/web.yml): the same project as the
# Quest APK, exported with Godot's single-threaded Web template (no special server headers, so
# it runs on GitHub Pages and on iPhone Safari). Output: $OUT_DIR (default ../build/web), a
# folder to serve as is: index.html, index.js, index.wasm, index.pck, title.png.
#
# For the download only, the photo textures (JPEG sources, imported lossless for the headset)
# are imported as lossy WebP here: about a quarter of the size, the same on screen. This
# changes .import files in the checkout it runs in; CI throws the checkout away (locally:
# git checkout -- '*.import').
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"   # quest-native/
REPO="$(cd "$ROOT/.." && pwd)"
OUT="${OUT_DIR:-$REPO/build/web}"
CACHE="${GODOT_CACHE:-$HOME/.cache/mafateeh-godot}"

GODOT_VERSION="4.6.3-stable"
GODOT_TEMPLATE_DIR="4.6.3.stable"
GODOT_URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}"
GODOT_EDITOR_ZIP="Godot_v${GODOT_VERSION}_linux.x86_64.zip"
GODOT_EDITOR_SHA512="a035258da32b77f966a5376f9fa29c30a6adde826a85ba918e1605bd1fc9823eba7d85f1dd5e748956bd2ba72827c0025ffa11bb82aec91128c407a2e723c99c"
GODOT_TPZ="Godot_v${GODOT_VERSION}_export_templates.tpz"
GODOT_TPZ_SHA512="da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68"

log() { printf '\n==> %s\n' "$*"; }

fetch() {  # fetch <file> <sha512>
  local f="$1" sum="$2"
  mkdir -p "$CACHE"
  if [ ! -f "$CACHE/$f" ] || ! echo "$sum  $CACHE/$f" | sha512sum -c --quiet - 2>/dev/null; then
    curl -fL --retry 4 --retry-delay 5 -o "$CACHE/$f.part" "$GODOT_URL/$f"
    mv "$CACHE/$f.part" "$CACHE/$f"
  fi
  echo "$sum  $CACHE/$f" | sha512sum -c -
}

log "Godot ${GODOT_VERSION}"
fetch "$GODOT_EDITOR_ZIP" "$GODOT_EDITOR_SHA512"
mkdir -p "$CACHE/bin"
if [ ! -x "$CACHE/bin/godot" ]; then
  unzip -o -q "$CACHE/$GODOT_EDITOR_ZIP" -d "$CACHE/bin"
  mv "$CACHE/bin/Godot_v${GODOT_VERSION}_linux.x86_64" "$CACHE/bin/godot"
fi
GODOT="$CACHE/bin/godot"
"$GODOT" --version
TPL="$HOME/.local/share/godot/export_templates/$GODOT_TEMPLATE_DIR"
if [ ! -f "$TPL/web_nothreads_release.zip" ]; then
  fetch "$GODOT_TPZ" "$GODOT_TPZ_SHA512"
  mkdir -p "$TPL" /tmp/tpz
  unzip -o -q "$CACHE/$GODOT_TPZ" 'templates/web_nothreads_release.zip' 'templates/version.txt' -d /tmp/tpz
  mv /tmp/tpz/templates/* "$TPL/"
  rm -f "$CACHE/$GODOT_TPZ"   # 1.2 GB, of which the web build needs 10 MB
fi
ls -la "$TPL"

log "Photo textures as lossy WebP (web download only)"
n=0
while IFS= read -r f; do
  if grep -q '^compress/mode=0$' "$f"; then
    sed -i 's/^compress\/mode=0$/compress\/mode=1/; s/^compress\/lossy_quality=.*/compress\/lossy_quality=0.85/' "$f"
    n=$((n + 1))
  fi
done < <(find "$ROOT/assets" -type f \( -name '*.jpg.import' -o -name '*.jpeg.import' \))
echo "$n textures"

log "Import"
"$GODOT" --headless --xr-mode off --path "$ROOT" --import 2>&1 | grep -v "OpenXR-Loader" | tail -5 || true

log "Tests"
if [ "${SKIP_TESTS:-0}" != "1" ]; then
  GODOT="$GODOT" "$ROOT/tools/run_tests.sh"
fi

log "Export"
rm -rf "$OUT"
mkdir -p "$OUT"
"$GODOT" --headless --xr-mode off --path "$ROOT" --export-release "Web" "$OUT/index.html" 2>&1 | grep -v "OpenXR-Loader" | tee "$OUT/../web-export.log"
for f in index.html index.js index.wasm index.pck; do
  test -s "$OUT/$f" || { echo "Export failed: no $f"; exit 1; }
done
# the loading screen's picture: the game's title (as on the store), at a web size
python3 - "$ROOT/assets/brand/mafateeh_title.png" "$OUT/title.png" <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGBA")
im.thumbnail((840, 840))
im.save(sys.argv[2], optimize=True)
EOF
grep -q 'title.png' "$OUT/index.html"
ls -la "$OUT"
du -sh "$OUT"
