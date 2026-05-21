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
    dependencies: [
        .package(url: "https://github.com/MacPaw/OpenAI.git", from: "0.4.9")
    ],
    targets: [
        .executableTarget(
            name: "Compass",
            dependencies: [
                .product(name: "OpenAI", package: "OpenAI")
            ],
            exclude: [
                "SharedVM/README.md"
            ],
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
