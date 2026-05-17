#!/bin/bash
set -euo pipefail

# One-time: create a persistent self-signed *code-signing* identity in the
# login keychain. This replaces anonymous ad-hoc signing with a stable
# signer, which stops macOS treating the app as anonymous code (the thing
# that triggers the XProtect "contains malware" false positive for an
# unsigned binary that spawns helpers / installs a login item).
#
# No sudo, no system trust changes — codesign only needs the identity
# present to *produce* a signature.

NAME="Driftwall Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "Identity \"$NAME\" already exists — nothing to do."
  exit 0
fi

openssl genrsa -out "$TMP/dw.key" 2048
openssl req -x509 -new -key "$TMP/dw.key" -out "$TMP/dw.crt" -days 3650 \
  -subj "/CN=$NAME" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false"
# Legacy PBE/MAC so Apple's `security import` (not OpenSSL 3) can read it.
openssl pkcs12 -export -out "$TMP/dw.p12" \
  -inkey "$TMP/dw.key" -in "$TMP/dw.crt" \
  -passout pass:driftwall -name "$NAME" \
  -legacy -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

security import "$TMP/dw.p12" -k "$KEYCHAIN" -P driftwall \
  -T /usr/bin/codesign -T /usr/bin/security

# Let codesign use the key without an interactive prompt every build.
security set-key-partition-list -S apple-tool:,apple: -s \
  -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo "Created code-signing identity: \"$NAME\""
security find-identity -v -p codesigning | grep "$NAME" || true
