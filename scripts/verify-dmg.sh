#!/usr/bin/env bash
# Mount a Supervim DMG and require Supervim.app plus an Applications symlink.
set -euo pipefail

DMG="${1:?missing dmg path}"
MOUNT="$(mktemp -d)"
cleanup() {
  hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
  rmdir "$MOUNT" 2>/dev/null || true
}
trap cleanup EXIT

hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$DMG"
test -d "$MOUNT/Supervim.app"
if [[ ! -L "$MOUNT/Applications" ]]; then
  echo "Applications link is missing from $DMG" >&2
  exit 1
fi
TARGET="$(readlink "$MOUNT/Applications")"
case "$TARGET" in
  /Applications) ;;
  *)
    echo "Applications link target is $TARGET, expected /Applications" >&2
    exit 1
    ;;
esac
if [[ ! -s "$MOUNT/Supervim.app/Contents/Resources/AppIcon.icns" ]]; then
  echo "AppIcon.icns is missing from the bundled app" >&2
  exit 1
fi
ICON="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$MOUNT/Supervim.app/Contents/Info.plist")"
if [[ "$ICON" != "AppIcon" ]]; then
  echo "CFBundleIconFile is ${ICON}, expected AppIcon" >&2
  exit 1
fi
if [[ ! -s "$MOUNT/.VolumeIcon.icns" ]]; then
  echo "volume icon .VolumeIcon.icns is missing from $DMG" >&2
  exit 1
fi
echo "DMG contains Supervim.app and an Applications link to /Applications"
