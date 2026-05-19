cask "driftwall" do
  version "0.1.5"
  sha256 "7450f6a886c975a99b0305d25b452e6498fc0ee7701723dc933a1d17d09e9606"

  url "https://github.com/emerytech/Driftwall/releases/download/v#{version}/Driftwall-#{version}.zip"
  name "Driftwall"
  desc "Live video wallpaper and lock-screen screen saver for macOS"
  homepage "https://github.com/emerytech/Driftwall"

  app "Driftwall.app"

  zap trash: [
    "~/Library/Preferences/com.local.driftwall.plist",
  ]
end
