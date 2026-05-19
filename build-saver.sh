#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Builds Driftwall.saver (the lock-screen / login-window companion) and,
# with --install, copies it to ~/Library/Screen Savers/.
#
# NOTE: on Apple Silicon the screensaver host (legacyScreenSaver) will
# refuse to load a saver that isn't Developer ID signed + notarized.
# Ad-hoc builds are fine to compile but typically won't run until
# notarize.sh has been used. The cert step is the prerequisite.

SAVER="Driftwall.saver"
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

if [ "${1:-}" = "--install" ]; then
  DEST="$HOME/Library/Screen Savers"
  mkdir -p "$DEST"
  rm -rf "$DEST/$SAVER"
  cp -R "$SAVER" "$DEST/"
  xattr -dr com.apple.quarantine "$DEST/$SAVER" 2>/dev/null || true
  echo "Installed to $DEST/$SAVER"
  echo "Select it in System Settings → Screen Saver (and set the lock"
  echo "screen to use the screen saver)."
else
  echo "Built $SAVER — install with: ./build-saver.sh --install"
fi
