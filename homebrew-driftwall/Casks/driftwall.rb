cask "driftwall" do
  version "0.1.0"
  sha256 "57e87aef239c7905327314f230fcdd693615c28041f8089cc17c921856725922"

  url "https://github.com/emerytech/Driftwall/releases/download/v#{version}/Driftwall-#{version}.zip"
  name "Driftwall"
  desc "Video wallpaper for macOS"
  homepage "https://github.com/emerytech/Driftwall"

  app "Driftwall.app"

  zap trash: [
    "~/Library/Preferences/com.local.driftwall.plist",
  ]
end
