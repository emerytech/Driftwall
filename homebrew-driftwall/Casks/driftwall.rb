cask "driftwall" do
  version "0.1.2"
  sha256 "e0485f5d42a22c53aaaf81cbe08ae86cd3812011e771cbb77f79ef332a1944bd"

  url "https://github.com/emerytech/Driftwall/releases/download/v#{version}/Driftwall-#{version}.zip"
  name "Driftwall"
  desc "Live video wallpaper and lock-screen screen saver for macOS"
  homepage "https://github.com/emerytech/Driftwall"

  app "Driftwall.app"

  zap trash: [
    "~/Library/Preferences/com.local.driftwall.plist",
  ]
end
