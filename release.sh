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
#   ./release.sh --check      # validate signing/notary config, then exit
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

# Fail-fast validation: catch a config typo in ~1s instead of after a
# full build + a multi-minute notary round-trip. Returns 0 when the
# intended path is sound (including a deliberate ad-hoc build).
preflight() {
  local ok=1
  echo "==> Preflight"
  # shellcheck disable=SC1091
  [ -f config.local.sh ] && source ./config.local.sh
  local key="${AC_API_KEY:-}" kid="${AC_KEY_ID:-}" iss="${AC_ISSUER:-}"
  local aid="${AC_APPLE_ID:-}" pw="${AC_PASSWORD:-}"

  if ! have_devid; then
    echo "  • No Developer ID cert — release will be AD-HOC (Gatekeeper"
    echo "    prompt). Fine if intended; use a Developer ID cert to notarize."
    echo "  preflight OK ✅ (ad-hoc)"
    return 0
  fi
  echo "  ✓ Developer ID Application certificate present"

  if [ -n "$iss" ]; then
    echo "  → notary auth: App Store Connect API key"
    if [ -n "$key" ] && [ -f "$key" ] && [ -r "$key" ]; then
      local first; first=$(head -1 "$key" 2>/dev/null || true)
      if [[ "$first" == *"BEGIN PRIVATE KEY"* ]]; then
        echo "  ✓ .p8 present, readable, PEM-shaped"
      else
        echo "  ✗ .p8 is not a PEM private key: $key"; ok=0
      fi
    else
      echo "  ✗ AC_API_KEY missing/unreadable: '${key:-<unset>}'"; ok=0
    fi
    [ -n "$kid" ] && echo "  ✓ AC_KEY_ID set" || { echo "  ✗ AC_KEY_ID unset"; ok=0; }
    if [[ "$iss" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
      echo "  ✓ AC_ISSUER is a UUID"
    else
      echo "  ✗ AC_ISSUER not a UUID: '$iss'"; ok=0
    fi
  elif [ -n "$aid" ] && [ -n "$pw" ]; then
    echo "  → notary auth: Apple ID + app-specific password"
    echo "  ✓ AC_APPLE_ID/AC_PASSWORD set (only verifiable at submit time)"
  else
    echo "  ✗ Developer ID cert present but NO notary creds in config.local.sh"
    echo "    Set AC_ISSUER (+ .p8) or AC_APPLE_ID/AC_PASSWORD — see"
    echo "    config.local.sh.example."
    ok=0
  fi

  if [ "$ok" = 1 ]; then echo "  preflight OK ✅"; return 0; fi
  echo "  preflight FAILED ❌"; return 1
}

if [ "${1:-}" = "--check" ]; then
  preflight; exit $?
fi

# Catch misconfig before any expensive work.
preflight || { echo "Aborting. Fix config.local.sh, or run NOTARIZE=0 ./release.sh for ad-hoc."; exit 1; }

NOTARIZE="${NOTARIZE:-auto}"
if [ "$NOTARIZE" != "0" ] && have_devid && have_notary_creds; then
  echo "==> Developer ID + notary creds found — notarizing."
  ./notarize.sh
  SIGNED="notarized"
else
  echo "==> No Developer ID/notary creds — ad-hoc build (Gatekeeper prompt)."
  ./build.sh
  ./build-saver.sh
  SIGNED="adhoc"
fi
SAVER="Driftwall.saver"
SAVER_ZIP="$OUT/Driftwall-$VER-ScreenSaver.zip"

mkdir -p "$OUT"
rm -f "$DMG" "$ZIP" "$SAVER_ZIP"

# .zip — what the Homebrew cask downloads.
ditto -c -k --keepParent "$APP" "$ZIP"

# Screen saver — shipped as its own zip (the cask installs the app; the
# saver is an optional drag-to-install extra, also placed in the .dmg).
if [ -d "$SAVER" ]; then
  ditto -c -k --keepParent "$SAVER" "$SAVER_ZIP"
fi

# .dmg — drag-to-Applications window for the website download.
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
[ -d "$SAVER" ] && cp -R "$SAVER" "$STAGE/"
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
  desc "Live video wallpaper and lock-screen screen saver for macOS"
  homepage "https://github.com/emerytech/Driftwall"

  app "Driftwall.app"

  zap trash: [
    "~/Library/Preferences/com.local.driftwall.plist",
  ]
end
EOF

# Sparkle appcast — signed with the EdDSA key in the login Keychain.
# Enclosure URLs point at the v$VER GitHub release assets; output goes
# to docs/ so GitHub Pages serves it at the Info.plist SUFeedURL.
if [ -x vendor/bin/generate_appcast ]; then
  ACSRC=$(mktemp -d)
  cp "$ZIP" "$ACSRC/"
  mkdir -p docs
  vendor/bin/generate_appcast \
    --download-url-prefix "https://github.com/emerytech/Driftwall/releases/download/v$VER/" \
    -o docs/appcast.xml \
    "$ACSRC"
  rm -rf "$ACSRC"
  APPCAST="docs/appcast.xml"
else
  echo "WARNING: vendor/bin/generate_appcast missing — appcast NOT updated."
fi

echo
echo "==> Release $VER ($SIGNED)"
echo "    $DMG"
echo "    $ZIP"
[ -f "$SAVER_ZIP" ] && echo "    $SAVER_ZIP (screen saver)"
echo "    sha256: $SHA"
echo "    cask:   $CASK (regenerated)"
[ -n "${APPCAST:-}" ] && echo "    appcast: $APPCAST (signed — commit + push so Pages serves it)"
echo
echo "Next:"
echo "  gh release create \"v$VER\" \"$DMG\" \"$ZIP\" \"$SAVER_ZIP\" --title \"Driftwall $VER\""
echo "  git add docs/appcast.xml \"$CASK\" && git commit && git push   # Pages serves the appcast"
echo "  cp \"$CASK\" <homebrew-driftwall checkout>/Casks/ && commit + push the tap"
