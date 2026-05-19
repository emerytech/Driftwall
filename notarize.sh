#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Build (Developer ID signed) → zip → notarize → staple, for BOTH the
# app and the screen-saver bundle. The gold standard: trusted system-
# wide, which also makes SMAppService Launch-at-Login bulletproof and is
# REQUIRED for the .saver to load on Apple Silicon.
#
# Two auth methods, in priority order:
#   A. App Store Connect API key — needs AC_ISSUER:
#        export AC_ISSUER="<issuer-uuid>"          # ASC → Users and
#        ./notarize.sh                             # Access → API Keys
#   B. Apple ID + app-specific password:
#        export AC_APPLE_ID="you@example.com"
#        export AC_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # appleid.apple.com
#
# The Developer ID cert must be created under the SAME team that
# notarizes (the .p8/issuer's team), or the notary service rejects it.
# Personal values live in config.local.sh (git-ignored).

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
./build-saver.sh

# Capture once, then inspect — piping `codesign | grep -q` trips
# `set -o pipefail`: grep -q closes the pipe, codesign dies with SIGPIPE,
# and the pipeline reports failure even though the app is fine.
APP_SIG=$(codesign -dv --verbose=2 Driftwall.app 2>&1 || true)
if ! grep -q "Authority=Developer ID Application" <<<"$APP_SIG"; then
  echo "ERROR: Driftwall.app is not Developer ID signed. Create the cert"
  echo "in Xcode (Settings → Accounts → Manage Certificates → + →"
  echo "Developer ID Application) under the notarizing team, or run"
  echo "./tools/make-devid-cert.sh, then re-run. build.sh auto-detects it."
  exit 1
fi

if [ "$AUTH_METHOD" = "apikey" ]; then
  NOTARY_AUTH=(--key "$AC_API_KEY" --key-id "$AC_KEY_ID" --issuer "$AC_ISSUER")
else
  TEAM=$(sed -n 's/^TeamIdentifier=//p' <<<"$APP_SIG")
  NOTARY_AUTH=(--apple-id "$AC_APPLE_ID" --password "$AC_PASSWORD" --team-id "$TEAM")
fi

# Submit a bundle WITHOUT --wait, then poll. `--wait` blocks for the
# whole (multi-minute, occasionally 20+) window in one call; if that call
# is killed the submission still completes server-side but never staples.
# Polling keeps each command short and is resumable via `notarytool info`.
notarize_and_staple() {
  local bundle="$1"
  [ -e "$bundle" ] || { echo "skip: $bundle not found"; return 0; }
  if ! codesign -dv --verbose=2 "$bundle" 2>&1 \
       | grep -q "Authority=Developer ID Application"; then
    echo "ERROR: $bundle is not Developer ID signed."; return 1
  fi
  local zip="${bundle}.notarize.zip"
  rm -f "$zip"
  ditto -c -k --keepParent "$bundle" "$zip"

  echo "Submitting $bundle to Apple notary service…"
  local sj sid
  sj=$(xcrun notarytool submit "$zip" "${NOTARY_AUTH[@]}" --output-format json)
  sid=$(/usr/bin/python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])' \
          <<<"$sj" 2>/dev/null || true)
  if [ -z "$sid" ]; then
    echo "ERROR: no submission id returned:"; echo "$sj"; rm -f "$zip"; return 1
  fi
  echo "  id: $sid — polling (Ctrl-C is safe; resume: xcrun notarytool info $sid …)"

  local status=""
  for _ in $(seq 1 80); do                     # ~40 min ceiling (80 × 30s)
    sleep 30
    local info
    info=$(xcrun notarytool info "$sid" "${NOTARY_AUTH[@]}" \
             --output-format json 2>/dev/null || true)
    status=$(/usr/bin/python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("status",""))
except Exception: print("")' <<<"$info" 2>/dev/null || true)
    echo "  status: ${status:-querying…}"
    case "$status" in
      Accepted) break ;;
      Invalid|Rejected)
        echo "Notarization $status — log follows:"
        xcrun notarytool log "$sid" "${NOTARY_AUTH[@]}" || true
        rm -f "$zip"; return 1 ;;
    esac
  done
  if [ "$status" != "Accepted" ]; then
    echo "ERROR: $bundle notarization not done (last: ${status:-unknown})."
    echo "Resume: xcrun notarytool info $sid …  then  xcrun stapler staple $bundle"
    rm -f "$zip"; return 1
  fi

  xcrun stapler staple "$bundle"
  rm -f "$zip"
  spctl -a -vvv --type execute "$bundle" 2>/dev/null || true
  echo "✓ $bundle notarized + stapled."
}

notarize_and_staple "Driftwall.app"
notarize_and_staple "Driftwall.saver"

echo "Done. Driftwall.app + Driftwall.saver are notarized + stapled."
