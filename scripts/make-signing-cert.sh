#!/usr/bin/env bash
# Create the one stable Supervim code-signing identity.
#
# Run this once, on a Mac the maintainer controls. It writes a private key and
# a password-protected .p12 OUTSIDE the git repo. Do not commit either file.
# The same certificate must be used for every release. A new certificate makes
# TCC ask for Accessibility and Input Monitoring again.
#
# Usage:
#   SUPERVIM_SIGNING_P12_PASSWORD='choose-a-long-password' \
#     scripts/make-signing-cert.sh "$HOME/supervim-signing"
#
# Then store the p12 and the password as GitHub Actions secrets. See
# docs/stable-signing.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$HOME/supervim-signing}"
PASSWORD="${SUPERVIM_SIGNING_P12_PASSWORD:-}"
NAME="Supervim Stable Signing"

if [[ -z "$PASSWORD" ]]; then
  echo "Set SUPERVIM_SIGNING_P12_PASSWORD before running this script." >&2
  exit 1
fi

case "$OUT_DIR" in
  "$ROOT"|"$ROOT"/*)
    echo "refusing to write the signing key inside the git repo ($OUT_DIR)" >&2
    exit 1
    ;;
esac

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

KEY="$OUT_DIR/supervim-signing.key"
CRT="$OUT_DIR/supervim-signing.crt"
P12="$OUT_DIR/supervim-signing.p12"
CONF="$OUT_DIR/openssl.cnf"

if [[ -e "$KEY" || -e "$P12" ]]; then
  echo "refusing to overwrite an existing key or p12 in $OUT_DIR" >&2
  exit 1
fi

cat > "$CONF" <<EOF
[req]
distinguished_name = req_dn
x509_extensions = v3_codesign
prompt = no

[req_dn]
CN = $NAME

[v3_codesign]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:3072 -sha256 -days 7300 -nodes \
  -keyout "$KEY" \
  -out "$CRT" \
  -config "$CONF" \
  -extensions v3_codesign

# Older `security import` builds reject the default OpenSSL 3 algorithms.
# SHA1 and 3DES are what the macOS keychain importer still accepts.
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
  openssl pkcs12 -export -legacy \
    -inkey "$KEY" \
    -in "$CRT" \
    -out "$P12" \
    -name "$NAME" \
    -passout "pass:$PASSWORD"
else
  openssl pkcs12 -export \
    -inkey "$KEY" \
    -in "$CRT" \
    -out "$P12" \
    -name "$NAME" \
    -keypbe PBE-SHA1-3DES \
    -certpbe PBE-SHA1-3DES \
    -macalg sha1 \
    -passout "pass:$PASSWORD"
fi

chmod 600 "$KEY" "$P12"
rm -f "$CONF"

echo "Wrote $P12"
echo "The private key is $KEY. Do not commit this directory."
openssl x509 -in "$CRT" -noout -fingerprint -sha1
echo "Certificate subject:"
openssl x509 -in "$CRT" -noout -subject
