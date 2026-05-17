// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Compass",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "Compass", targets: ["CompassNative"])
    ],
    targets: [
        .executableTarget(
            name: "CompassNative",
            path: "Sources/CompassNative",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
