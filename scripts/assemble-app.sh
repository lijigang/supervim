#!/usr/bin/env bash
# Assemble an unsigned menu-bar app bundle from the SwiftPM executable.
# LSUIElement lives in the bundle Info.plist. Launch Services reads it only
# when the process is opened as Supervim.app. swift run uses the accessory
# activation policy in the executable instead.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="debug"
if [[ "${1:-}" == "release" ]]; then
  CONFIG="release"
fi

swift build -c "$CONFIG" --product Supervim
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path | tail -n 1)"
APP="$ROOT/build/Supervim.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/Supervim" "$APP/Contents/MacOS/Supervim"
chmod +x "$APP/Contents/MacOS/Supervim"
cp "$ROOT/App/Supervim/Info.plist" "$APP/Contents/Info.plist"

if [[ "$(uname -s)" == "Darwin" ]]; then
  LSUI="$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist")"
  if [[ "$LSUI" != "true" ]]; then
    echo "LSUIElement must be true so the app has no Dock icon. Found: $LSUI" >&2
    exit 1
  fi
fi

echo "Assembled $APP"
