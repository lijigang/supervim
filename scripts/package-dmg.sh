#!/usr/bin/env bash
# Package Supervim.app into a DMG with an Applications drop link.
# scripts/sign-app.sh signs the staged copy. With the stable certificate that
# signature keeps Accessibility and Input Monitoring across upgrades. Without
# the certificate it falls back to ad-hoc and says so. The image is not notarized.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/Supervim.app}"
DMG="${2:-$ROOT/build/Supervim.dmg}"

if [[ ! -d "$APP" ]]; then
  echo "missing app bundle: $APP" >&2
  exit 1
fi
if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg is not installed" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
cleanup() {
  rm -rf "$STAGE"
}
trap cleanup EXIT

cp -R "$APP" "$STAGE/Supervim.app"
"$ROOT/scripts/sign-app.sh" "$STAGE/Supervim.app"

mkdir -p "$(dirname "$DMG")"
rm -f "$DMG"

create-dmg \
  --volname "Supervim" \
  --volicon "$ROOT/Resources/AppIcon.icns" \
  --window-pos 200 120 \
  --window-size 640 400 \
  --icon-size 128 \
  --icon "Supervim.app" 160 190 \
  --hide-extension "Supervim.app" \
  --app-drop-link 480 190 \
  "$DMG" \
  "$STAGE"
