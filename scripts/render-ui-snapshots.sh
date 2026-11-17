#!/usr/bin/env bash
# Renders every Supervim surface to PNG at 2x, light and dark, legacy and polished.
# macOS only: the views are AppKit. Writes build/ui-snapshots/*.png.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-build/ui-snapshots}"
mkdir -p "$OUT"
swift run SupervimUISnapshots "$OUT"

python3 - "$OUT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
files = sorted(root.glob("*.png"))
if len(files) < 30:
    sys.exit(f"expected at least 30 snapshots, found {len(files)}")
for path in files:
    data = path.read_bytes()
    if len(data) < 800 or data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"{path.name} is not a usable PNG ({len(data)} bytes)")
    print(f"{path.name} {len(data)} bytes")
PY
