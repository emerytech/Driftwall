#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Mac App Store variant: SANDBOXED, NO Sparkle (MAS forbids self-update).
#
# This produces a sandboxed Driftwall-MAS.app and signs it for LOCAL
# testing. It is NOT yet App Store-submittable — that additionally needs
# (your side, in Apple Developer / App Store Connect):
#   • a registered App ID matching MAS_BUNDLE_ID
#   • an "Apple Distribution" certificate + a Mac App Store provisioning
#     profile (embedded.provisionprofile next to this script)
#   • productbuild into a .pkg signed with "3rd Party Mac Developer
#     Installer", uploaded via Transporter
#   • screenshots, privacy nutrition labels, age rating, App Review
#
# Still-open product risks (validate before investing in submission):
#   • Does the desktop-level wallpaper window work under App Sandbox?
#   • Sandbox blocks yt-dlp, reading /Library Apple Aerials, ~/Wallpapers,
#     installing the .saver, and setting the desktop picture — those
#     features need rework or removal for a compliant build.

APP="Driftwall-MAS.app"
BUNDLE_ID="${MAS_BUNDLE_ID:-com.emerytech.driftwall}"
ENT="Driftwall-MAS.entitlements"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ ! -f Resources/AppIcon.icns ] || [ ! -f Resources/MenuBar.pdf ]; then
  mkdir -p Resources
  swift tools/MakeIcons.swift Resources
fi

# Compile with -D MAS, WITHOUT Sources/SparkleUpdater.swift / Sparkle.
swiftc -O -D MAS \
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
  Sources/LockScreenMatch.swift \
  Sources/AppleAerials.swift \
  -framework Cocoa -framework AVFoundation -framework AVKit \
  -framework IOKit -framework ServiceManagement \
  -o "$APP/Contents/MacOS/Driftwall"

# Info.plist: derive from the shipping one, strip Sparkle keys, set the
# MAS bundle id (must match the registered App ID).
cp Info.plist "$APP/Contents/Info.plist"
for k in SUFeedURL SUPublicEDKey SUAutomaticallyChecksForUpdates SUScheduledCheckInterval; do
  /usr/libexec/PlistBuddy -c "Delete :$k" "$APP/Contents/Info.plist" 2>/dev/null || true
done
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuBar.pdf  "$APP/Contents/Resources/MenuBar.pdf"

dist_id=$(security find-identity -v -p codesigning 2>/dev/null \
            | grep -o '"Apple Distribution:[^"]*"' | head -1 | tr -d '"' || true)
if [ -n "$dist_id" ] && [ -f embedded.provisionprofile ]; then
  cp embedded.provisionprofile "$APP/Contents/embedded.provisionprofile"
  codesign --force --options runtime --entitlements "$ENT" --sign "$dist_id" "$APP"
  echo "Signed with: $dist_id"
  echo "Next: productbuild --component \"$APP\" /Applications \\"
  echo "        --sign \"3rd Party Mac Developer Installer: …\" Driftwall-MAS.pkg"
  echo "      then upload Driftwall-MAS.pkg via Transporter / xcrun altool."
else
  devid=$(security find-identity -v -p codesigning 2>/dev/null \
            | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"' || true)
  echo "No Apple Distribution cert + provisioning profile — signing the"
  echo "sandboxed build locally (${devid:-ad-hoc}) for testing only."
  codesign --force --entitlements "$ENT" --sign "${devid:--}" "$APP"
fi

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
echo "Built $APP (App Sandbox ON, no Sparkle). See header for the"
echo "remaining App Store submission steps + open product risks."
