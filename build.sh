#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"

APP="Driftwall.app"
SPARKLE_VER="2.9.2"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

# Generate icons on first build (or after `rm -rf Resources`).
if [ ! -f Resources/AppIcon.icns ] || [ ! -f Resources/MenuBar.pdf ]; then
  mkdir -p Resources
  swift tools/MakeIcons.swift Resources
fi

# Vendor Sparkle if missing (gitignored; re-fetched here).
if [ ! -d vendor/Sparkle.framework ]; then
  echo "Fetching Sparkle $SPARKLE_VER…"
  mkdir -p vendor
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VER/Sparkle-$SPARKLE_VER.tar.xz" \
    -o vendor/sparkle.tar.xz
  tar -C vendor -xJf vendor/sparkle.tar.xz
  rm -f vendor/sparkle.tar.xz
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
  Sources/SparkleUpdater.swift \
  -F "$ROOT/vendor" -framework Sparkle \
  -framework Cocoa -framework AVFoundation -framework AVKit \
  -framework IOKit -framework ServiceManagement \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$APP/Contents/MacOS/Driftwall"

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuBar.pdf "$APP/Contents/Resources/MenuBar.pdf"

cp -R vendor/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"

# Signing preference: Developer ID (notarizable) → self-signed → ad-hoc.
# Sparkle's prebuilt framework is signed by the Sparkle team, so Hardened
# Runtime's Library Validation refuses to load it. It must be RE-SIGNED
# with our identity, inside-out, before the app (no --deep so each nested
# Mach-O gets a correct, individually valid signature).
RUNTIME=()
if ID=$(security find-identity -v -p codesigning 2>/dev/null \
          | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"'); \
   [ -n "$ID" ]; then
  echo "Signing with: $ID (Developer ID — notarizable)"
  RUNTIME=(--options runtime --timestamp)
elif security find-identity -v -p codesigning 2>/dev/null \
       | grep -q "Driftwall Self-Signed"; then
  ID="Driftwall Self-Signed"
  echo "Signing with: Driftwall Self-Signed (stable local identity)"
else
  ID="-"
  echo "No signing cert — ad-hoc (Sparkle updates need Developer ID)."
fi

FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
csign() { codesign --force "${RUNTIME[@]}" --sign "$ID" "$@"; }
csign "$FW/XPCServices/Installer.xpc"
csign "$FW/XPCServices/Downloader.xpc"
csign "$FW/Updater.app"
csign "$FW/Autoupdate"
csign "$APP/Contents/Frameworks/Sparkle.framework"
csign "$APP"

# Locally built bundles shouldn't carry quarantine, but strip it defensively
# so Gatekeeper never gets a reason to intercept on launch.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "Built $APP — launch with: open $APP"
