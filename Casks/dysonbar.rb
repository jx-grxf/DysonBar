cask "dysonbar" do
  version "0.1.0"
  sha256 "1543aa1bdcb54b094a5eb3feb0299b9db22b0dba7b2e37282c0bc9524db2909c"

  url "https://github.com/jx-grxf/DysonBar/releases/download/v#{version}/DysonBar-#{version}.dmg"
  name "DysonBar"
  desc "Menu bar app for Dyson air purifiers over the local network"
  homepage "https://github.com/jx-grxf/DysonBar"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sequoia"

  app "DysonBar.app"

  zap trash: [
    "~/Library/Application Support/DysonBar",
    "~/Library/Preferences/at.johannesgrof.DysonBar.plist",
    "~/Library/Caches/at.johannesgrof.DysonBar",
    "~/Library/HTTPStorages/at.johannesgrof.DysonBar",
  ]
end
