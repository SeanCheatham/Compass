// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CompassNative",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "CompassNative", targets: ["CompassNative"])
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
