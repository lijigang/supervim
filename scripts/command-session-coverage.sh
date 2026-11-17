#!/bin/bash
# Measures line coverage of the task 11 command session.
# Exits 0 when each listed file's line coverage is at least 90%.
# AXInputFocuser.swift is macOS-only and is not in this gate.
set -euo pipefail

cd "$(dirname "$0")/.."

swift test --enable-code-coverage

if [[ -x "$(dirname "$(command -v swift)")/llvm-cov" ]]; then
  cov() { "$(dirname "$(command -v swift)")/llvm-cov" "$@"; }
elif command -v xcrun >/dev/null 2>&1 && xcrun --find llvm-cov >/dev/null 2>&1; then
  cov() { xcrun llvm-cov "$@"; }
elif command -v llvm-cov >/dev/null 2>&1; then
  cov() { llvm-cov "$@"; }
else
  echo "llvm-cov was not found next to swift or via xcrun" >&2
  exit 1
fi

prof_stamp() {
  if stat -c %Y "$1" >/dev/null 2>&1; then
    stat -c %Y "$1"
  else
    stat -f %m "$1"
  fi
}

newest=""
newest_stamp=0
while IFS= read -r prof; do
  stamp="$(prof_stamp "$prof")"
  if [[ "$stamp" -ge "$newest_stamp" ]]; then
    newest="$prof"
    newest_stamp="$stamp"
  fi
done < <(find .build -name default.profdata -type f)

if [[ -z "$newest" ]]; then
  echo "no default.profdata under .build" >&2
  exit 1
fi

sources=(
  "Sources/SupervimCore/CommandFollowThrough.swift"
  "Sources/SupervimSystem/NormalCommandSession.swift"
  "Sources/SupervimSystem/ScrollAreaCatalog.swift"
)

found_binary=0
while IFS= read -r bin; do
  found_binary=1
  break
done < <(find .build -type f \( \
  -name 'SupervimCoreTests.so' -o \
  -name 'SupervimCoreTests.dylib' -o \
  -name 'libSupervimCore.so' -o \
  -name 'libSupervimCore.dylib' -o \
  -name 'SupervimSystemTests.so' -o \
  -name 'SupervimSystemTests.dylib' -o \
  -name 'libSupervimSystem.so' -o \
  -name 'libSupervimSystem.dylib' -o \
  -name 'SupervimPackageTests' -o \
  -name 'SupervimCoreTests-test-runner' -o \
  -name 'SupervimSystemTests-test-runner' \
\))

if [[ "$found_binary" -eq 0 ]]; then
  echo "could not find an instrumented test binary" >&2
  exit 1
fi

for source in "${sources[@]}"; do
  base="$(basename "$source")"
  report=""
  while IFS= read -r bin; do
    if cov export "$bin" -instr-profile "$newest" \
      -sources "$source" \
      -summary-only > /tmp/command-session-coverage.json 2>/dev/null \
      && python3 - "$base" /tmp/command-session-coverage.json <<'PY'
import json, sys
base, path = sys.argv[1], sys.argv[2]
data = json.load(open(path))
files = data.get("data", [{}])[0].get("files", [])
ok = any(
    item["filename"].endswith(base) and item["summary"]["lines"]["count"] > 0
    for item in files
)
sys.exit(0 if ok else 1)
PY
    then
      report="$bin"
      break
    fi
  done < <(find .build -type f \( \
    -name 'SupervimCoreTests.so' -o \
    -name 'SupervimCoreTests.dylib' -o \
    -name 'libSupervimCore.so' -o \
    -name 'libSupervimCore.dylib' -o \
    -name 'SupervimSystemTests.so' -o \
    -name 'SupervimSystemTests.dylib' -o \
    -name 'libSupervimSystem.so' -o \
    -name 'libSupervimSystem.dylib' -o \
    -name 'SupervimPackageTests' -o \
    -name 'SupervimCoreTests-test-runner' -o \
    -name 'SupervimSystemTests-test-runner' \
  \))

  if [[ -z "$report" ]]; then
    echo "could not find an instrumented binary containing $base" >&2
    exit 1
  fi

  python3 - "$report" "$base" <<'PY'
import json, sys
binary, base = sys.argv[1], sys.argv[2]
data = json.load(open("/tmp/command-session-coverage.json"))
chosen = None
for item in data["data"][0]["files"]:
    if item["filename"].endswith(base):
        chosen = item
        break
if chosen is None:
    sys.exit(f"{base} missing from coverage export")
lines = chosen["summary"]["lines"]
regions = chosen["summary"]["regions"]
functions = chosen["summary"]["functions"]
print(f"binary: {binary}")
print(
    f"{base} line coverage: "
    f"{lines['percent']:.2f}% ({lines['covered']}/{lines['count']})"
)
print(
    f"{base} region coverage: "
    f"{regions['percent']:.2f}% ({regions['covered']}/{regions['count']})"
)
print(
    f"{base} function coverage: "
    f"{functions['percent']:.2f}% ({functions['covered']}/{functions['count']})"
)
if lines["percent"] < 90:
    sys.exit(f"{base} line coverage is below 90%")
PY
done
