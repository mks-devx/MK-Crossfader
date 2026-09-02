// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MKMIDICrossfader",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CrossfaderCore", targets: ["CrossfaderCore"]),
        .executable(name: "MKMIDICrossfader", targets: ["MKMIDICrossfader"])
    ],
    targets: [
        .target(name: "CrossfaderCore"),
        .executableTarget(
            name: "MKMIDICrossfader",
            dependencies: ["CrossfaderCore"]
        ),
        .testTarget(
            name: "CrossfaderCoreTests",
            dependencies: ["CrossfaderCore"]
        ),
        .testTarget(
            name: "MKMIDICrossfaderTests",
            dependencies: ["MKMIDICrossfader", "CrossfaderCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
