#!/usr/bin/env bash
# Sign Supervim.app so TCC can recognize every future build as the same app.
#
# With SUPERVIM_SIGNING_P12_BASE64 and SUPERVIM_SIGNING_P12_PASSWORD set, this
# imports that one self-signed certificate into a temporary keychain and signs
# with its SHA-1 hash. codesign then writes a designated requirement of the form
#   identifier "com.lijigang.supervim" and certificate leaf = H"..."
# The hash is the certificate, not the build, so Accessibility and Input
# Monitoring survive an upgrade.
#
# The certificate stays untrusted. Trust prompts and identity verification
# hang on a headless runner, so this script never changes trust settings and
# never asks the system to pick a valid identity. codesign is given the
# certificate hash directly. The private key is made readable by codesign
# with set-key-partition-list, and the keychain is unlocked again immediately
# before signing.
#
# Hardened runtime is not used. This certificate is self-signed, not an Apple
# publisher certificate, and the app has no entitlements file. Adding runtime
# would not stabilize TCC.
#
# If the two variables are empty, the script falls back to an ad-hoc signature
# and says so. Ad-hoc requirements contain a cdhash, and that hash changes
# every build, so TCC will ask for permission again.
set -euo pipefail

APP="${1:-}"
BUNDLE_ID="com.lijigang.supervim"
IDENTITY_NAME="Supervim Stable Signing"
LIMIT_SECONDS=120

if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "usage: scripts/sign-app.sh /path/to/Supervim.app" >&2
  exit 1
fi

# A keychain dialog blocks forever on the runner. Kill the command and fail.
# The label is a fixed string so the p12 password is never written to the log.
run_bounded() {
  local label="$1"
  shift
  echo "running: $label" >&2
  "$@" &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [[ "$waited" -ge "$LIMIT_SECONDS" ]]; then
      echo "ERROR: ${label} did not finish within ${LIMIT_SECONDS}s. A keychain prompt is likely blocking it." >&2
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      exit 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
}

print_requirement() {
  echo "Designated requirement:"
  run_bounded "read designated requirement" codesign -d -r- "$APP" 2>&1 || true
}

sign_inner() {
  local identity="$1"
  local path
  # Sign nested Mach-O files before the bundle. The app bundle itself is last
  # and is the only one pinned to the product identifier.
  while IFS= read -r path; do
    case "$path" in
      "$APP") continue ;;
    esac
    if file "$path" | grep -q 'Mach-O'; then
      run_bounded "codesign nested file" codesign --force --sign "$identity" --timestamp=none "$path"
    fi
  done < <(find "$APP" -type f -print)
  run_bounded "codesign bundle" codesign --force --sign "$identity" --identifier "$BUNDLE_ID" --timestamp=none "$APP"
}

require_certificate_requirement() {
  local requirement
  requirement="$(run_bounded "check designated requirement" codesign -d -r- "$APP" 2>&1 || true)"
  printf '%s\n' "$requirement"
  case "$requirement" in
    *"identifier \"$BUNDLE_ID\""*"certificate leaf = H\""*) ;;
    *)
      echo "ERROR: designated requirement is not tied to the stable certificate." >&2
      echo "ERROR: expected identifier \"$BUNDLE_ID\" and certificate leaf = H\"...\"." >&2
      exit 1
      ;;
  esac
  if printf '%s\n' "$requirement" | grep -q 'cdhash'; then
    echo "ERROR: designated requirement still contains cdhash, so TCC will not survive the next build." >&2
    exit 1
  fi
}

certificate_sha1() {
  local fp
  fp="$(openssl x509 -in "$CRT_FILE" -noout -fingerprint -sha1)"
  fp="${fp##*=}"
  fp="${fp//:/}"
  printf '%s' "$fp" | tr '[:lower:]' '[:upper:]'
}

# OpenSSL 3 refuses the legacy RC2-40-CBC bag unless -legacy is passed.
# The password stays in the environment. Do not use -passin pass:...
extract_cert_with_openssl() {
  rm -f "$CRT_FILE"
  if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
    if run_bounded "openssl pkcs12 -legacy" openssl pkcs12 -legacy \
        -in "$P12_FILE" -clcerts -nokeys \
        -passin env:SUPERVIM_SIGNING_P12_PASSWORD -out "$CRT_FILE"; then
      return 0
    fi
    rm -f "$CRT_FILE"
  fi
  run_bounded "openssl pkcs12" openssl pkcs12 \
    -in "$P12_FILE" -clcerts -nokeys \
    -passin env:SUPERVIM_SIGNING_P12_PASSWORD -out "$CRT_FILE"
}

P12_B64="${SUPERVIM_SIGNING_P12_BASE64:-}"
P12_PASSWORD="${SUPERVIM_SIGNING_P12_PASSWORD:-}"

if [[ -z "$P12_B64" || -z "$P12_PASSWORD" ]]; then
  echo "WARNING: SUPERVIM_SIGNING_P12_BASE64 or SUPERVIM_SIGNING_P12_PASSWORD is missing." >&2
  echo "WARNING: Falling back to ad-hoc codesign (-s -)." >&2
  echo "WARNING: The designated requirement will contain a cdhash. Accessibility and Input Monitoring will have to be granted again after the next build." >&2
  sign_inner "-"
  print_requirement
  exit 0
fi

WORK="$(mktemp -d)"
KEYCHAIN=""
cleanup() {
  if [[ -n "${KEYCHAIN:-}" ]]; then
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 &
    local pid=$!
    local waited=0
    while kill -0 "$pid" 2>/dev/null && [[ "$waited" -lt 20 ]]; do
      sleep 1
      waited=$((waited + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
      echo "ERROR: security delete-keychain did not finish within 20s." >&2
      kill -KILL "$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

P12_FILE="$WORK/supervim-signing.p12"
CRT_FILE="$WORK/supervim-signing.crt"
KEYCHAIN="$WORK/supervim-signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"

# macOS base64 wants -D. GNU base64 wants --decode. Try GNU first.
if ! printf '%s' "$P12_B64" | base64 --decode > "$P12_FILE" 2>/dev/null; then
  printf '%s' "$P12_B64" | base64 -D > "$P12_FILE"
fi
chmod 600 "$P12_FILE"

run_bounded "create keychain" security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
run_bounded "keychain settings" security set-keychain-settings -lut 21600 "$KEYCHAIN"
run_bounded "unlock keychain" security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
# `security import` has no file or env passphrase flag. -P is the only
# non-interactive form. xtrace is off around this call so the p12 password
# is not written to the log. -A stops the key-access dialog.
case $- in
  *x*) tracing=1; set +x ;;
  *) tracing=0 ;;
esac
run_bounded "security import" security import "$P12_FILE" -k "$KEYCHAIN" -P "$P12_PASSWORD" -f pkcs12 -A -T /usr/bin/codesign -T /usr/bin/security
if [[ "$tracing" -eq 1 ]]; then
  set -x
fi
run_bounded "set-key-partition-list" security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
run_bounded "keychain search list" security list-keychains -d user -s "$KEYCHAIN"

if ! run_bounded "find-certificate" security find-certificate -c "$IDENTITY_NAME" -p "$KEYCHAIN" > "$CRT_FILE" \
    || ! grep -q 'BEGIN CERTIFICATE' "$CRT_FILE"; then
  echo "keychain certificate lookup was empty; reading the p12 with openssl" >&2
  extract_cert_with_openssl
fi
if ! grep -q 'BEGIN CERTIFICATE' "$CRT_FILE"; then
  echo "ERROR: imported the p12 but could not read the certificate named \"$IDENTITY_NAME\"." >&2
  exit 1
fi

IDENTITY="$(certificate_sha1)"
if [[ ! "$IDENTITY" =~ ^[0-9A-F]{40}$ ]]; then
  echo "ERROR: certificate SHA-1 for \"$IDENTITY_NAME\" was not 40 hex characters." >&2
  exit 1
fi

echo "Signing $APP with certificate $IDENTITY ($IDENTITY_NAME)"
run_bounded "unlock keychain before codesign" security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
sign_inner "$IDENTITY"
require_certificate_requirement
