#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# A stable install path is the other half of reliable Launch-at-Login:
# SMAppService keys off bundle identity + path, so running from a fixed
# /Applications location (not a rebuilt dev folder) keeps it sticking.

./build.sh

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
echo "Launch it from /Applications (Spotlight: \"Driftwall\"), then enable"
echo "Launch at Login in Settings — it will now survive rebuilds."
open "$DEST"
