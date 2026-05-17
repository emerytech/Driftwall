#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="Driftwall.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Generate icons on first build (or after `rm -rf Resources`).
if [ ! -f Resources/AppIcon.icns ] || [ ! -f Resources/MenuBar.pdf ]; then
  mkdir -p Resources
  swift tools/MakeIcons.swift Resources
fi

swiftc -O \
  Sources/main.swift \
  Sources/AppDelegate.swift \
  Sources/Appearance.swift \
  Sources/Onboarding.swift \
  Sources/WallpaperWindow.swift \
  Sources/VideoWallpaperView.swift \
  Sources/WallpaperController.swift \
  Sources/PowerMonitor.swift \
  Sources/FullscreenMonitor.swift \
  Sources/BatteryWarning.swift \
  Sources/SupportPrompt.swift \
  Sources/SettingsWindow.swift \
  Sources/VideoFetcher.swift \
  Sources/StockBrowser.swift \
  Sources/VideoLibrary.swift \
  Sources/DisplayConfig.swift \
  Sources/ScheduleWindow.swift \
  -framework Cocoa -framework AVFoundation -framework AVKit \
  -framework IOKit -framework ServiceManagement \
  -o "$APP/Contents/MacOS/Driftwall"

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuBar.pdf "$APP/Contents/Resources/MenuBar.pdf"

# Signing preference:
#   1. Developer ID  → Hardened Runtime + timestamp (notarizable).
#   2. "Driftwall Self-Signed" → stable identified signer (run
#      tools/make-signing-cert.sh once). Beats anonymous ad-hoc, which
#      XProtect false-flags as malware for a helper-spawning agent.
#   3. ad-hoc fallback.
sign() {
  local id
  if id=$(security find-identity -v -p codesigning 2>/dev/null \
            | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"'); \
     [ -n "$id" ]; then
    echo "Signing with: $id (Developer ID — notarizable)"
    codesign --force --deep --options runtime --timestamp --sign "$id" "$APP"
  elif security find-identity -v -p codesigning 2>/dev/null \
         | grep -q "Driftwall Self-Signed"; then
    echo "Signing with: Driftwall Self-Signed (stable local identity)"
    codesign --force --deep --sign "Driftwall Self-Signed" "$APP"
  else
    echo "No signing cert — ad-hoc. Run tools/make-signing-cert.sh to"
    echo "create a stable self-signed identity (recommended)."
    codesign --force --deep --sign - "$APP"
  fi
}
sign

# Locally built bundles shouldn't carry quarantine, but strip it defensively
# so Gatekeeper never gets a reason to intercept on launch.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "Built $APP — launch with: open $APP"
