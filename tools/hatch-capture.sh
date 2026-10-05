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
DERIVED="${TMPDIR:-/tmp}/hatch-capture-build"
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
    HATCH_DESIGNER_SIZE=1500x1000 "$BIN" --components-demo native --app "$ROOT" --snapshots "$TMP"
  fi
  for f in "$TMP"/*; do
    [ -e "$f" ] || continue
    name="$(basename "$f")"
    case "$name" in "$part"-*) mv "$f" "$OUT/$name" ;; *) mv "$f" "$OUT/$part-$name" ;; esac
  done
  rm -rf "$TMP"
done
