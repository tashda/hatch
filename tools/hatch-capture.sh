#!/bin/sh
# Hatch's capture command (decision CM21): draws every screen of the app, the Stage and the Components Designer on made-up
# data, light and dark, each picture with a .json beside it naming the frame of every view of Hatch's own on it
# (`.hatchMark`). Hatch runs it for `hatch components capture` and for the evidence `hatch ready` keeps; it writes into
# $HATCH_CAPTURES. Nothing here touches the real database or the notebook.
#
#   HATCH_CAPTURES=/tmp/out tools/hatch-capture.sh
set -e
OUT="${HATCH_CAPTURES:?set HATCH_CAPTURES to the folder to write into}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# One build folder per checkout, so two tickets can be drawn at once.
DERIVED="${TMPDIR:-/tmp}/hatch-capture-build-$(printf %s "$ROOT" | shasum | cut -c1-8)"
mkdir -p "$OUT"

# The app: every main screen, sheet and step, and the gallery of views no screen shows.
xcodebuild -project "$ROOT/Hatch.xcodeproj" -scheme Hatch -destination 'platform=macOS' -derivedDataPath "$DERIVED" build -quiet
"$DERIVED/Build/Products/Debug/Hatch.app/Contents/MacOS/Hatch" --snapshots "$OUT"

# The Stage and the Components Designer (one program), their pictures named apart from the app's.
cd "$ROOT/Stage"
env -u SDKROOT -u TOOLCHAINS xcrun --sdk macosx swift build --product HatchStageToast >/dev/null
BIN="$ROOT/Stage/.build/debug/HatchStageToast"
for part in stage designer; do
  TMP="$OUT/.$part"; rm -rf "$TMP"; mkdir -p "$TMP"
  if [ "$part" = stage ]; then
    "$BIN" --snapshots "$TMP"
  else
    # The project's own system and pictures when Hatch passes its notebook (role pages, its own components, checks).
    if [ -n "$HATCH_NOTEBOOK" ]; then SOURCE="--notebook $HATCH_NOTEBOOK"; else SOURCE="--components-demo native"; fi
    # shellcheck disable=SC2086
    HATCH_DESIGNER_SIZE=1500x1000 "$BIN" $SOURCE --app "$ROOT" --snapshots "$TMP"
  fi
  for f in "$TMP"/*; do
    [ -e "$f" ] || continue
    name="$(basename "$f")"
    case "$name" in "$part"-*) mv "$f" "$OUT/$name" ;; *) mv "$f" "$OUT/$part-$name" ;; esac
  done
  rm -rf "$TMP"
done

# The Designer's canvas measured against the same roles in real macOS containers (CM25), with the project's own system
# when Hatch passes its notebook.
TMP="$OUT/.truth"; rm -rf "$TMP"; mkdir -p "$TMP"
if [ -n "$HATCH_NOTEBOOK" ]; then SYSTEM="--notebook $HATCH_NOTEBOOK"; else SYSTEM="--components-demo native"; fi
# shellcheck disable=SC2086
"$BIN" $SYSTEM --snapshots "$TMP" --canvas-truth >/dev/null
for f in "$TMP"/*-light.png "$TMP"/*-light.json; do [ -e "$f" ] && mv "$f" "$OUT/$(basename "$f")"; done
[ -e "$TMP/canvas-truth.json" ] && mv "$TMP/canvas-truth.json" "$OUT/canvas-truth.json"
rm -rf "$TMP"
