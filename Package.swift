// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Compass",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "Compass", targets: ["Compass"]),
        .executable(name: "CompassGuestAgent", targets: ["CompassGuestAgent"]),
        .library(name: "CompassAgentRPC", targets: ["CompassAgentRPC"])
    ],
    dependencies: [
        .package(url: "https://github.com/MacPaw/OpenAI.git", from: "0.4.9")
    ],
    targets: [
        .target(
            name: "CompassAgentRPC"
        ),
        .executableTarget(
            name: "CompassGuestAgent",
            dependencies: ["CompassAgentRPC"]
        ),
        .executableTarget(
            name: "Compass",
            dependencies: [
                "CompassAgentRPC",
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
            name: "CompassAgentRPCTests",
            dependencies: ["CompassAgentRPC"]
        ),
        .testTarget(
            name: "CompassTests",
            dependencies: ["Compass"]
        )
    ]
)
