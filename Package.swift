// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "DysonBar",
  defaultLocalization: "en",
  platforms: [
    .macOS(.v15)
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.2")
  ],
  targets: [
    .target(
      name: "DysonKit",
      path: "Sources/DysonKit",
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .executableTarget(
      name: "DysonBar",
      dependencies: [
        "DysonKit",
        .product(name: "Sparkle", package: "Sparkle"),
      ],
      path: "Sources/DysonBar",
      // Strings are compiled by script/build_and_run.sh into the app's own
      // Resources so Bundle.main and the per-app language override find them.
      exclude: ["Resources"],
      swiftSettings: [.swiftLanguageMode(.v5)],
      linkerSettings: [
        .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
      ]
    ),
    .testTarget(
      name: "DysonKitTests",
      dependencies: ["DysonKit"],
      path: "Tests/DysonKitTests"
    ),
  ]
)
