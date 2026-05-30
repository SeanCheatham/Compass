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
      revision: "75b3874edb2dc714fb1fd77a32013d0f8699989f"
    ),
    .package(
      url: "https://github.com/tree-sitter/tree-sitter-javascript",
      revision: "58404d8cf191d69f2674a8fd507bd5776f46cb11"
    ),
    .package(
      url: "https://github.com/tree-sitter/tree-sitter-go",
      revision: "2346a3ab1bb3857b48b29d779a1ef9799a248cd7"
    ),
    .package(
      url: "https://github.com/tree-sitter/tree-sitter-rust",
      revision: "77a3747266f4d621d0757825e6b11edcbf991ca5"
    ),
    .package(
      url: "https://github.com/apple/swift-testing",
      exact: "6.3.2"
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
      dependencies: ["Compass", .product(name: "Testing", package: "swift-testing")]
    ),
  ]
)
