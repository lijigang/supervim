#!/usr/bin/env bash
# Sign Supervim.app so TCC can recognize every future build as the same app.
#
# With SUPERVIM_SIGNING_P12_BASE64 and SUPERVIM_SIGNING_P12_PASSWORD set, this
# imports that one self-signed certificate into a temporary keychain and signs
# with it. codesign then writes a designated requirement of the form
#   identifier "com.lijigang.supervim" and certificate leaf = H"..."
# The hash is the certificate, not the build, so Accessibility and Input
# Monitoring survive an upgrade.
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

if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "usage: scripts/sign-app.sh /path/to/Supervim.app" >&2
  exit 1
fi

print_requirement() {
  echo "Designated requirement:"
  codesign -d -r- "$APP" 2>&1 || true
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
      codesign --force --sign "$identity" --timestamp=none "$path"
    fi
  done < <(find "$APP" -type f -print)
  codesign --force --sign "$identity" --identifier "$BUNDLE_ID" --timestamp=none "$APP"
}

require_certificate_requirement() {
  local requirement
  requirement="$(codesign -d -r- "$APP" 2>&1 || true)"
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
cleanup() {
  if [[ -n "${KEYCHAIN:-}" ]]; then
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
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

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
# `security import` has no file or env passphrase flag. -P is the only
# non-interactive form. xtrace is off for this command so the p12 password
# is not written to the log. The value is not echoed.
case $- in
  *x*) tracing=1; set +x ;;
  *) tracing=0 ;;
esac
security import "$P12_FILE" -k "$KEYCHAIN" -P "$P12_PASSWORD" -f pkcs12 -T /usr/bin/codesign -T /usr/bin/security
if [[ "$tracing" -eq 1 ]]; then
  set -x
fi
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

# The checked-in secret is a legacy PKCS#12 (RC2-40-CBC). OpenSSL 3 refuses
# that bag unless -legacy is passed, and `pass:` would put the password on
# the command line. Prefer the certificate already imported into the
# temporary keychain. Fall back to openssl only if that lookup is empty.
extract_leaf_cert() {
  if security find-certificate -c "$IDENTITY_NAME" -p "$KEYCHAIN" > "$CRT_FILE" 2>/dev/null \
      && grep -q 'BEGIN CERTIFICATE' "$CRT_FILE"; then
    return 0
  fi
  rm -f "$CRT_FILE"
  # Password comes from the environment. Do not use -passin pass:...
  if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
    if openssl pkcs12 -legacy -in "$P12_FILE" -clcerts -nokeys \
        -passin env:SUPERVIM_SIGNING_P12_PASSWORD -out "$CRT_FILE"; then
      return 0
    fi
    rm -f "$CRT_FILE"
  fi
  openssl pkcs12 -in "$P12_FILE" -clcerts -nokeys \
    -passin env:SUPERVIM_SIGNING_P12_PASSWORD -out "$CRT_FILE"
}
extract_leaf_cert
if ! grep -q 'BEGIN CERTIFICATE' "$CRT_FILE"; then
  echo "ERROR: imported the p12 but could not read the certificate named \"$IDENTITY_NAME\"." >&2
  exit 1
fi
# A self-signed code-signing certificate is invisible to `find-identity` until
# this keychain trusts it for the codeSign policy. Trust stays in the temporary
# keychain and is deleted with it.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$CRT_FILE"

# Keep the existing search list so other jobs on the runner still find their keys.
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')

IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk -v name="$IDENTITY_NAME" '
  index($0, name) { print $2; exit }
')"
if [[ -z "$IDENTITY" ]]; then
  echo "ERROR: imported the p12 but found no code signing identity named \"$IDENTITY_NAME\"." >&2
  security find-identity -v -p codesigning "$KEYCHAIN" >&2 || true
  exit 1
fi

echo "Signing $APP with identity $IDENTITY ($IDENTITY_NAME)"
sign_inner "$IDENTITY"
require_certificate_requirement
