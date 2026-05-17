#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Build (Developer ID signed) → zip → notarize → staple. The gold
# standard: the app becomes trusted system-wide, which also makes
# SMAppService Launch-at-Login bulletproof.
#
# Two auth methods, in priority order:
#   A. App Store Connect API key — needs AC_ISSUER (the one value not
#      stored locally and not shown in Xcode):
#        export AC_ISSUER="<issuer-uuid>"          # ASC → Users and
#        ./notarize.sh                             # Access → API Keys
#   B. Apple ID + app-specific password — no Issuer ID required:
#        export AC_APPLE_ID="you@example.com"
#        export AC_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # appleid.apple.com
#        ./notarize.sh
#
# The .p8 is referenced by path and never copied into the repo.
# Personal values live in config.local.sh (git-ignored). See
# config.local.sh.example.

[ -f config.local.sh ] && source ./config.local.sh

AC_API_KEY="${AC_API_KEY:-}"
AC_KEY_ID="${AC_KEY_ID:-}"
AC_ISSUER="${AC_ISSUER:-}"
AC_APPLE_ID="${AC_APPLE_ID:-}"
AC_PASSWORD="${AC_PASSWORD:-}"

if [ -n "$AC_ISSUER" ]; then
  AUTH_METHOD="apikey"
  [ -f "$AC_API_KEY" ] || { echo "ERROR: .p8 not found: $AC_API_KEY"; exit 1; }
elif [ -n "$AC_APPLE_ID" ] && [ -n "$AC_PASSWORD" ]; then
  AUTH_METHOD="appleid"
else
  echo "ERROR: set EITHER AC_ISSUER (with the .p8) OR AC_APPLE_ID +"
  echo "AC_PASSWORD (app-specific password). See the header for details."
  exit 1
fi

./build.sh

# Capture once, then inspect — piping `codesign | grep -q` trips
# `set -o pipefail`: grep -q closes the pipe on first match, codesign
# dies with SIGPIPE, and the pipeline reports failure even though the
# app is correctly signed.
SIG=$(codesign -dv --verbose=2 Driftwall.app 2>&1 || true)
if ! grep -q "Authority=Developer ID Application" <<<"$SIG"; then
  echo "ERROR: Driftwall.app is not Developer ID signed. Create the cert"
  echo "in Xcode (Settings → Accounts → Manage Certificates → + →"
  echo "Developer ID Application), or run ./tools/make-devid-cert.sh,"
  echo "then re-run. build.sh auto-detects it."
  exit 1
fi

if [ "$AUTH_METHOD" = "apikey" ]; then
  NOTARY_AUTH=(--key "$AC_API_KEY" --key-id "$AC_KEY_ID" --issuer "$AC_ISSUER")
else
  TEAM=$(sed -n 's/^TeamIdentifier=//p' <<<"$SIG")
  NOTARY_AUTH=(--apple-id "$AC_APPLE_ID" --password "$AC_PASSWORD" --team-id "$TEAM")
fi

ZIP="Driftwall.zip"
rm -f "$ZIP"
ditto -c -k --keepParent Driftwall.app "$ZIP"

echo "Submitting to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "$ZIP" "${NOTARY_AUTH[@]}" --wait

xcrun stapler staple Driftwall.app
rm -f "$ZIP"

spctl -a -vvv --type execute Driftwall.app || true
echo "Notarized + stapled. Driftwall.app is now fully trusted."
