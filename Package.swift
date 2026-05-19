// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Compass",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "Compass", targets: ["Compass"])
    ],
    targets: [
        .executableTarget(
            name: "Compass",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CompassTests",
            dependencies: ["Compass"]
        )
    ]
)
