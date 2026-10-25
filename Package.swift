// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "DysonBar",
  platforms: [
    .macOS(.v15)
  ],
  targets: [
    .executableTarget(
      name: "DysonBar",
      path: "Sources/DysonBar",
      swiftSettings: [.swiftLanguageMode(.v5)]
    )
  ]
)
