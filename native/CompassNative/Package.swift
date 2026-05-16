// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CompassNative",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CompassNative", targets: ["CompassNative"])
    ],
    targets: [
        .executableTarget(
            name: "CompassNative",
            path: "Sources/CompassNative"
        )
    ]
)
