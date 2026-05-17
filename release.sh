#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Package a distributable Driftwall release: a .dmg (drag-to-Applications)
# and a .zip (used by the Homebrew cask), plus the sha256 the cask needs.
#
# Signing:
#   - If a Developer ID cert + notarization creds are available it runs
#     ./notarize.sh first, producing a notarized + stapled app (cleanest
#     install, no Gatekeeper prompt). Set up creds in config.local.sh —
#     see config.local.sh.example and the notarize.sh header.
#   - Otherwise it falls back to ./build.sh (ad-hoc signed). The artifact
#     still works, but users must right-click → Open the first time, or
#     install via `brew install --cask --no-quarantine`.
#
# Usage:
#   ./release.sh              # auto: notarize if possible, else ad-hoc
#   NOTARIZE=0 ./release.sh   # force the plain (ad-hoc) build
#
# Then create the GitHub release with both artifacts, e.g.:
#   gh release create "v$VER" dist/Driftwall-$VER.dmg dist/Driftwall-$VER.zip \
#     --title "Driftwall $VER" --notes "…"
# and push the regenerated Casks/driftwall.rb to the homebrew tap repo.

APP="Driftwall.app"
VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
OUT="dist"
DMG="$OUT/Driftwall-$VER.dmg"
ZIP="$OUT/Driftwall-$VER.zip"

have_devid() {
  security find-identity -v -p codesigning 2>/dev/null \
    | grep -q "Developer ID Application"
}
have_notary_creds() {
  [ -f config.local.sh ] && grep -qE 'AC_(ISSUER|APPLE_ID)=' config.local.sh
}

NOTARIZE="${NOTARIZE:-auto}"
if [ "$NOTARIZE" != "0" ] && have_devid && have_notary_creds; then
  echo "==> Developer ID + notary creds found — notarizing."
  ./notarize.sh
  SIGNED="notarized"
else
  echo "==> No Developer ID/notary creds — ad-hoc build (Gatekeeper prompt)."
  ./build.sh
  SIGNED="adhoc"
fi

mkdir -p "$OUT"
rm -f "$DMG" "$ZIP"

# .zip — what the Homebrew cask downloads.
ditto -c -k --keepParent "$APP" "$ZIP"

# .dmg — drag-to-Applications window for the website download.
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Driftwall" -srcfolder "$STAGE" \
  -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')

# Regenerate the tracked cask with this version + checksum.
CASK="homebrew-driftwall/Casks/driftwall.rb"
mkdir -p "$(dirname "$CASK")"
cat > "$CASK" <<EOF
cask "driftwall" do
  version "$VER"
  sha256 "$SHA"

  url "https://github.com/emerytech/Driftwall/releases/download/v#{version}/Driftwall-#{version}.zip"
  name "Driftwall"
  desc "Video wallpaper for macOS"
  homepage "https://github.com/emerytech/Driftwall"

  app "Driftwall.app"

  zap trash: [
    "~/Library/Preferences/com.local.driftwall.plist",
  ]
end
EOF

echo
echo "==> Release $VER ($SIGNED)"
echo "    $DMG"
echo "    $ZIP"
echo "    sha256: $SHA"
echo "    cask:   $CASK (regenerated)"
echo
echo "Next:"
echo "  gh release create \"v$VER\" \"$DMG\" \"$ZIP\" --title \"Driftwall $VER\""
echo "  cp \"$CASK\" <homebrew-driftwall checkout>/Casks/ && git -C … commit && push"
