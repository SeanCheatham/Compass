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
    .library(name: "CompassAgentRPC", targets: ["CompassAgentRPC"]),
  ],
  dependencies: [
    .package(url: "https://github.com/MacPaw/OpenAI.git", from: "0.4.9"),
    .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.9.0"),
    .package(
      url: "https://github.com/alex-pinkus/tree-sitter-swift",
      revision: "7b7909f2f6b9414be0958275f4c8e5d69c3bca43"
    ),
    .package(
      url: "https://github.com/tree-sitter/tree-sitter-typescript",
      branch: "master"
    ),
    .package(
      url: "https://github.com/tree-sitter/tree-sitter-javascript",
      branch: "master"
    ),
    .package(
      url: "https://github.com/tree-sitter/tree-sitter-python",
      branch: "master"
    ),
    .package(
      url: "https://github.com/tree-sitter/tree-sitter-go",
      branch: "master"
    ),
    .package(
      url: "https://github.com/tree-sitter/tree-sitter-rust",
      branch: "master"
    ),
    .package(
      url: "https://github.com/apple/swift-testing",
      branch: "main"
    ),
  ],
  targets: [
    .target(
      name: "CompassAgentRPC"
    ),
    .target(
      name: "TreeSitterScanners",
      exclude: ["README.md"],
      publicHeadersPath: "include",
      cSettings: [
        .headerSearchPath("include"),
        .unsafeFlags(["-w"]),
      ]
    ),
    .executableTarget(
      name: "CompassGuestAgent",
      dependencies: ["CompassAgentRPC"]
    ),
    .executableTarget(
      name: "Compass",
      dependencies: [
        "CompassAgentRPC",
        "TreeSitterScanners",
        .product(name: "OpenAI", package: "OpenAI"),
        .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
        .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
        .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
        .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
        .product(name: "TreeSitterPython", package: "tree-sitter-python"),
        .product(name: "TreeSitterGo", package: "tree-sitter-go"),
        .product(name: "TreeSitterRust", package: "tree-sitter-rust"),
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
      dependencies: ["CompassAgentRPC", .product(name: "Testing", package: "swift-testing")]
    ),
    .testTarget(
      name: "CompassTests",
      dependencies: ["Compass"]
    ),
  ]
)
