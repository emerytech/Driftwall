cask "driftwall" do
  version "0.1.3"
  sha256 "fa0a4bb7bca8291ae31353245df591a9d18c72da1bddf2a715e71b84f961668e"

  url "https://github.com/emerytech/Driftwall/releases/download/v#{version}/Driftwall-#{version}.zip"
  name "Driftwall"
  desc "Live video wallpaper and lock-screen screen saver for macOS"
  homepage "https://github.com/emerytech/Driftwall"

  app "Driftwall.app"

  zap trash: [
    "~/Library/Preferences/com.local.driftwall.plist",
  ]
end
