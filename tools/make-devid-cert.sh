#!/bin/bash
set -euo pipefail

# Create + install a "Developer ID Application" certificate via the App
# Store Connect API, authenticated with the .p8 key. After this,
# build.sh signs with Developer ID and notarize.sh just works.
#
# Requires the Issuer ID (App Store Connect → Users and Access →
# Integrations → API keys → "Issuer ID" at the top):
#
#   export AC_ISSUER="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#   ./tools/make-devid-cert.sh
#
# The .p8 is read in place and never copied into the repo. Personal
# values live in config.local.sh (git-ignored). See config.local.sh.example.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/config.local.sh" ] && source "$ROOT/config.local.sh"

AC_API_KEY="${AC_API_KEY:-}"
AC_KEY_ID="${AC_KEY_ID:-}"
AC_ISSUER="${AC_ISSUER:-}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

[ -n "$AC_KEY_ID" ] || { echo "ERROR: set AC_KEY_ID (see config.local.sh.example)"; exit 1; }

[ -f "$AC_API_KEY" ] || { echo "ERROR: .p8 not found: $AC_API_KEY"; exit 1; }
[ -n "$AC_ISSUER" ] || { echo "ERROR: set AC_ISSUER (see header)"; exit 1; }

if security find-identity -v -p codesigning 2>/dev/null \
     | grep -q "Developer ID Application"; then
  echo "A Developer ID Application identity already exists — nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
b64url() { openssl base64 -e -A | tr '+/' '-_' | tr -d '='; }

# --- ES256 JWT for the App Store Connect API ---
NOW=$(date +%s); EXP=$((NOW + 1080))
HDR=$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$AC_KEY_ID" | b64url)
PAY=$(printf '{"iss":"%s","iat":%d,"exp":%d,"aud":"appstoreconnect-v1"}' \
        "$AC_ISSUER" "$NOW" "$EXP" | b64url)
SIG=$(printf '%s' "$HDR.$PAY" \
      | openssl dgst -sha256 -sign "$AC_API_KEY" -binary \
      | python3 -c '
import sys, base64
d = sys.stdin.buffer.read()                       # DER: SEQ{ INT r, INT s }
i = 2 if d[1] < 0x80 else 2 + (d[1] & 0x7f)
lr = d[i+1]; r = d[i+2:i+2+lr]
j = i + 2 + lr
ls = d[j+1]; s = d[j+2:j+2+ls]
r = r.lstrip(b"\x00").rjust(32, b"\x00")
s = s.lstrip(b"\x00").rjust(32, b"\x00")
sys.stdout.write(base64.urlsafe_b64encode(r+s).decode().rstrip("="))')
JWT="$HDR.$PAY.$SIG"

# --- CSR (RSA 2048; Apple ignores the subject) ---
openssl req -new -newkey rsa:2048 -nodes \
  -keyout "$TMP/devid.key" -out "$TMP/devid.csr" \
  -subj "/CN=Driftwall Developer ID/C=US" >/dev/null 2>&1

python3 - "$TMP/devid.csr" "$TMP/body.json" <<'PY'
import json, sys
csr = open(sys.argv[1]).read()
json.dump({"data": {"type": "certificates",
                     "attributes": {"certificateType": "DEVELOPER_ID_APPLICATION",
                                    "csrContent": csr}}},
          open(sys.argv[2], "w"))
PY

echo "Requesting Developer ID Application certificate…"
HTTP=$(curl -s -o "$TMP/resp.json" -w "%{http_code}" \
  -X POST "https://api.appstoreconnect.apple.com/v1/certificates" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  --data @"$TMP/body.json")

if [ "$HTTP" != "201" ]; then
  echo "ERROR: App Store Connect returned HTTP $HTTP:"
  python3 -c 'import json,sys;print(json.dumps(json.load(open(sys.argv[1])),indent=2))' \
    "$TMP/resp.json" 2>/dev/null || cat "$TMP/resp.json"
  echo
  echo "Common causes: wrong AC_ISSUER, the API key lacks Admin role, or"
  echo "Developer ID certs must be created by the Account Holder. If so,"
  echo "make it via developer.apple.com/account → Certificates instead."
  exit 1
fi

python3 -c '
import json, base64, sys
c = json.load(open(sys.argv[1]))["data"]["attributes"]["certificateContent"]
open(sys.argv[2], "wb").write(base64.b64decode(c))' "$TMP/resp.json" "$TMP/devid.cer"

openssl x509 -inform DER -in "$TMP/devid.cer" -out "$TMP/devid.pem"
CN=$(openssl x509 -in "$TMP/devid.pem" -noout -subject 2>/dev/null \
     | sed -n 's/.*CN=\([^,/]*\).*/\1/p')
openssl pkcs12 -export -out "$TMP/devid.p12" \
  -inkey "$TMP/devid.key" -in "$TMP/devid.pem" \
  -name "$CN" -passout pass:driftwall \
  -legacy -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

security import "$TMP/devid.p12" -k "$KEYCHAIN" -P driftwall \
  -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -s -k "" \
  "$KEYCHAIN" >/dev/null 2>&1 || true

echo "Installed: $CN"
security find-identity -v -p codesigning | grep "Developer ID Application" || true
echo "Now: ./build.sh   (auto-signs Developer ID)   then   ./notarize.sh"
