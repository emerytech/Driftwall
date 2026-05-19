#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Builds Driftwall.saver (the lock-screen / login-window companion) and,
# with --install, copies it to ~/Library/Screen Savers/.
#
# `--install` installs an EXISTING notarized Driftwall.saver as-is and
# skips the rebuild — rebuilding would discard the stapled notarization
# ticket, and on Apple Silicon legacyScreenSaver refuses a saver that
# isn't Developer ID signed + notarized. Run ./notarize.sh to produce
# the notarized bundle; then ./build-saver.sh --install.

SAVER="Driftwall.saver"
INSTALL=0
[ "${1:-}" = "--install" ] && INSTALL=1

install_saver() {
  local dest="$HOME/Library/Screen Savers"
  mkdir -p "$dest"
  rm -rf "$dest/$SAVER"
  cp -R "$SAVER" "$dest/"
  xattr -dr com.apple.quarantine "$dest/$SAVER" 2>/dev/null || true
  echo "Installed to $dest/$SAVER"
  echo "Select it in System Settings → Screen Saver (and set the Lock"
  echo "Screen to use the screen saver)."
}

# Install the already-notarized bundle without touching it.
if [ "$INSTALL" = 1 ] && [ -d "$SAVER" ] \
   && xcrun stapler validate "$SAVER" >/dev/null 2>&1; then
  echo "Installing existing NOTARIZED $SAVER (not rebuilding)."
  install_saver
  exit 0
fi

rm -rf "$SAVER"
mkdir -p "$SAVER/Contents/MacOS"

# Build a loadable bundle (MH_BUNDLE) — the linker flag overrides the
# default executable output.
swiftc -O \
  Saver/DriftwallSaverView.swift \
  -module-name DriftwallSaver \
  -framework Cocoa -framework AVFoundation -framework ScreenSaver \
  -Xlinker -bundle \
  -o "$SAVER/Contents/MacOS/Driftwall"

cp Saver/Info.plist "$SAVER/Contents/Info.plist"

# Same identity preference as build.sh: Developer ID (notarizable) else
# ad-hoc.
if id=$(security find-identity -v -p codesigning 2>/dev/null \
          | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"'); \
   [ -n "$id" ]; then
  echo "Signing saver with: $id"
  codesign --force --deep --options runtime --timestamp --sign "$id" "$SAVER"
else
  echo "No Developer ID cert — ad-hoc (will likely NOT load on Apple"
  echo "Silicon until notarized; see notarize.sh / make-devid-cert.sh)."
  codesign --force --deep --sign - "$SAVER"
fi

if [ "$INSTALL" = 1 ]; then
  if ! xcrun stapler validate "$SAVER" >/dev/null 2>&1; then
    echo "WARNING: this build is NOT notarized — it likely will not load"
    echo "on Apple Silicon. Run ./notarize.sh, then ./build-saver.sh --install."
  fi
  install_saver
else
  echo "Built $SAVER — notarize with ./notarize.sh, then ./build-saver.sh --install"
fi
