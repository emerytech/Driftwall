cask "driftwall" do
  version "0.1.4"
  sha256 "854ab6e06c5bcd84dec4bede64f2b97ca1241ca7a7874caabd983ce829edd595"

  url "https://github.com/emerytech/Driftwall/releases/download/v#{version}/Driftwall-#{version}.zip"
  name "Driftwall"
  desc "Live video wallpaper and lock-screen screen saver for macOS"
  homepage "https://github.com/emerytech/Driftwall"

  app "Driftwall.app"

  zap trash: [
    "~/Library/Preferences/com.local.driftwall.plist",
  ]
end
