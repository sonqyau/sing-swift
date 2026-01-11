// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "sing-swift",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "sing-swift",
            targets: ["sing-swift"],
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "sing-swift",
            dependencies: [],
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency=complete"),
            ],
        )
    ],
)
