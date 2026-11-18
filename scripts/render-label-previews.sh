#!/usr/bin/env bash
# Renders the four hint label redesign options over mock windows, light and
# dark. Option A is the one that ships. macOS only: the labels are drawn by
# the app's own AppKit views with the system fonts. Writes
# option-{A,B,C,D}-{light,dark}.png, before-*.png (the v0.1.5 label),
# compare.png and metrics.txt. The committed copies are in docs/label-redesign.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-build/label-previews}"
mkdir -p "$OUT"
swift run SupervimLabelPreviews "$OUT"

python3 - "$OUT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
expected = [f"option-{letter}-{mode}.png" for letter in "ABCD" for mode in ("light", "dark")]
expected += ["before-light.png", "before-dark.png", "compare.png"]
for name in expected:
    path = root / name
    if not path.is_file():
        sys.exit(f"{name} was not rendered")
    data = path.read_bytes()
    if len(data) < 20000 or data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"{name} is not a usable PNG ({len(data)} bytes)")
    print(f"{name} {len(data)} bytes")
print((root / "metrics.txt").read_text(), end="")
PY
