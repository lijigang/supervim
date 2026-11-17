#!/usr/bin/env bash
# Draw the Supervim app icon and pack AppIcon.icns.
# The source geometry lives in scripts/render_icon.py, which also writes
# Resources/AppIcon.svg. iconutil exists only on macOS; elsewhere the same
# script packs a PNG-based icns that macOS 13+ can read.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/scripts/render_icon.py" "$@"

if [[ "${1:-}" == "--check" ]]; then
  exit 0
fi

ICONSET="$ROOT/Resources/AppIcon.iconset"
ICNS="$ROOT/Resources/AppIcon.icns"
if command -v iconutil >/dev/null 2>&1; then
  iconutil -c icns "$ICONSET" -o "$ICNS"
  echo "Packed $ICNS with iconutil"
else
  echo "iconutil is not on this machine; kept the portable PNG icns at $ICNS"
fi
