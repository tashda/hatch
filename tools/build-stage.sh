#!/bin/sh
# Builds Stage.app: the Stage with a round, in a real app bundle so it has its own name and icon in the Dock.
#
#   tools/build-stage.sh [--dest DIR] [--config debug|release] [--round PRODUCT] [--sign IDENTITY]
#
# Defaults: DIR=Stage/.build/app, debug, the toast round. Hatch's Xcode build runs this and puts the result in
# Hatch.app/Contents/Helpers/Stage.app. The icon is drawn by the Stage itself (`--render-icon`), so there is no separate art file.
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

APP="$DEST/Stage.app"
STAMP="$DEST/.stage.last"
# An unchanged Stage keeps its bundle (and its signature), so Hatch's build does not touch Hatch.app for nothing.
if [ -d "$APP" ] && cmp -s "$BIN" "$STAMP" 2>/dev/null; then exit 0; fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -f "$BIN" "$APP/Contents/MacOS/Stage"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
"$BIN" --render-icon "$WORK/icon.png"
mkdir "$WORK/Stage.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon.png" --out "$WORK/Stage.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$WORK/icon.png" --out "$WORK/Stage.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/Stage.iconset" -o "$APP/Contents/Resources/Stage.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>Stage</string>
	<key>CFBundleIdentifier</key><string>app.hatch.Stage</string>
	<key>CFBundleName</key><string>Stage</string>
	<key>CFBundleDisplayName</key><string>Stage</string>
	<key>CFBundleIconFile</key><string>Stage</string>
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
cp -f "$BIN" "$STAMP"
echo "Built $APP"
