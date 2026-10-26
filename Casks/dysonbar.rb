cask "dysonbar" do
  version "0.1.1"
  sha256 "c92328799d03adbb21b54fd46c569ad1883748bd54d1d6e55f07465175dc80c1"

  url "https://github.com/jx-grxf/DysonBar/releases/download/v#{version}/DysonBar-#{version}.dmg"
  name "DysonBar"
  desc "Menu bar app for Dyson air purifiers over the local network"
  homepage "https://github.com/jx-grxf/DysonBar"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sequoia

  app "DysonBar.app"

  zap trash: [
    "~/Library/Application Support/DysonBar",
    "~/Library/Caches/at.johannesgrof.DysonBar",
    "~/Library/HTTPStorages/at.johannesgrof.DysonBar",
    "~/Library/Preferences/at.johannesgrof.DysonBar.plist",
  ]
end
