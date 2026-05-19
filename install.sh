#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Installs Driftwall.app to /Applications. A stable path is the other
# half of reliable Launch-at-Login (SMAppService keys off bundle
# identity + path), and notarization makes Gatekeeper silent.
#
# Crucially: if a NOTARIZED Driftwall.app already exists it is installed
# AS-IS. Rebuilding would discard the stapled notarization ticket (it's
# tied to the exact binary), so we only build when there's nothing
# notarized to install — and warn that that build is not notarized.

if [ -d Driftwall.app ] && xcrun stapler validate Driftwall.app >/dev/null 2>&1; then
  echo "Using existing notarized Driftwall.app (not rebuilding)."
else
  echo "No notarized build present — building an UN-notarized app."
  echo "For the trusted install run ./notarize.sh first, then ./install.sh."
  ./build.sh
fi

DEST="/Applications/Driftwall.app"
killall Driftwall 2>/dev/null || true

if cp -R "Driftwall.app" "$DEST.tmp" 2>/dev/null; then
  rm -rf "$DEST"
  mv "$DEST.tmp" "$DEST"
else
  echo "Couldn't write to /Applications without elevation; retrying with sudo…"
  sudo rm -rf "$DEST"
  sudo cp -R "Driftwall.app" "$DEST"
fi

echo "Installed to $DEST"
xcrun stapler validate "$DEST" >/dev/null 2>&1 \
  && echo "Verified: notarized + stapled." \
  || echo "Note: this install is NOT notarized (Gatekeeper may prompt)."
echo "Launch from /Applications (Spotlight: \"Driftwall\"), then enable"
echo "Launch at Login in Settings."
open "$DEST"
