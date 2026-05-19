cask "driftwall" do
  version "0.1.1"
  sha256 "2aa2465b9cd3ab0a050315ba857102d9bdb14043c76f39dc6b19ef68b5c4b167"

  url "https://github.com/emerytech/Driftwall/releases/download/v#{version}/Driftwall-#{version}.zip"
  name "Driftwall"
  desc "Live video wallpaper and lock-screen screen saver for macOS"
  homepage "https://github.com/emerytech/Driftwall"

  app "Driftwall.app"

  zap trash: [
    "~/Library/Preferences/com.local.driftwall.plist",
  ]
end
