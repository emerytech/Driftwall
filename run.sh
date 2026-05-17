#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Interim launcher for unsigned/ad-hoc local builds.
#
# Double-clicking the .app goes through LaunchServices, which runs the
# Gatekeeper/XProtect assessment — and that can false-flag an ad-hoc
# agent that spawns helpers (yt-dlp) + installs a login item as
# "malware" and trash it. Exec'ing the binary directly does NOT trigger
# that assessment, so the app just runs. (The real durable fix is
# notarization with the Developer ID cert — see notarize.sh.)

[ -x "Driftwall.app/Contents/MacOS/Driftwall" ] || ./build.sh

killall Driftwall 2>/dev/null || true
exec ./Driftwall.app/Contents/MacOS/Driftwall
