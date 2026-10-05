#!/bin/sh
# Builds Stage.app and Components Designer.app: the Stage with a round, in two real app bundles so each has its own name
# and icon in the Dock (decision AI3). Both hold the same program; the launch arguments choose Stage or Designer.
#
#   tools/build-stage.sh [--dest DIR] [--config debug|release] [--round PRODUCT] [--sign IDENTITY]
#
# Defaults: DIR=Stage/.build/app, debug, the toast round. Hatch's Xcode build runs this and puts the result in
# Hatch.app/Contents/Helpers/. The icons are drawn by the Stage itself (`--render-icon`), so there are no separate art files.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Stage/.build/app"; CONFIG=debug; ROUND=HatchStageToast; SIGN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dest) DEST="$2"; shift 2 ;;
    --config) CONFIG="$2"; shift 2 ;;
    --round) ROUND="$2"; shift 2 ;;
    --sign) SIGN="$2"; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

cd "$ROOT/Stage"
env -u SDKROOT -u TOOLCHAINS xcrun --sdk macosx swift build -c "$CONFIG" --product "$ROUND"
BIN="$ROOT/Stage/.build/$CONFIG/$ROUND"

STAGE="$DEST/Stage.app"
DESIGNER="$DEST/Components Designer.app"
STAMP="$DEST/.stage.last"
# An unchanged Stage keeps its bundles (and their signatures), so Hatch's build does not touch Hatch.app for nothing.
if [ -d "$STAGE" ] && [ -d "$DESIGNER" ] && cmp -s "$BIN" "$STAMP" 2>/dev/null; then exit 0; fi

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# make_app BUNDLE EXECUTABLE ID NAME [--designer]: one bundle around a copy of the program (a copy, not a symlink, which
# signing rejects), with its own name, icon and Info.plist. The arguments choose the mode, the bundle only names it (AI3).
make_app() {
  APP="$1"; EXE="$2"; ID="$3"; NAME="$4"; KIND="$5"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp -f "$BIN" "$APP/Contents/MacOS/$EXE"
  # 16 and 32 px come from the small drawing (no hairlines), the rest from the full one.
  "$BIN" --render-icon "$WORK/icon.png" $KIND
  "$BIN" --render-icon "$WORK/small.png" $KIND --small
  rm -rf "$WORK/icon.iconset"; mkdir "$WORK/icon.iconset"
  for s in 16 32; do sips -z $s $s "$WORK/small.png" --out "$WORK/icon.iconset/icon_${s}x${s}.png" >/dev/null; done
  sips -z 32 32 "$WORK/small.png" --out "$WORK/icon.iconset/icon_16x16@2x.png" >/dev/null
  sips -z 64 64 "$WORK/icon.png" --out "$WORK/icon.iconset/icon_32x32@2x.png" >/dev/null
  for s in 128 256 512; do
    sips -z $s $s "$WORK/icon.png" --out "$WORK/icon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$WORK/icon.png" --out "$WORK/icon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$WORK/icon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>$EXE</string>
	<key>CFBundleIdentifier</key><string>$ID</string>
	<key>CFBundleName</key><string>$NAME</string>
	<key>CFBundleDisplayName</key><string>$NAME</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleShortVersionString</key><string>0.1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>26.0</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

  if [ -n "$SIGN" ]; then
    codesign --force --options runtime --timestamp=none --sign "$SIGN" "$APP"
  fi
}

make_app "$STAGE" Stage app.hatch.Stage Stage ""
make_app "$DESIGNER" ComponentsDesigner app.hatch.ComponentsDesigner "Components Designer" --designer
cp -f "$BIN" "$STAMP"
echo "Built $STAGE and $DESIGNER"
