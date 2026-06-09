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
      url: "https://github.com/apple/swift-testing",
      exact: "6.3.2"
    ),
    .package(
      url: "https://github.com/ml-explore/mlx-swift-lm",
      branch: "main"
    ),
    .package(
      url: "https://github.com/huggingface/swift-huggingface",
      from: "0.9.0"
    ),
    .package(
      url: "https://github.com/huggingface/swift-transformers",
      from: "1.3.0"
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
        .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
        .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
        .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
        .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
        .product(name: "MLXLLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
        .product(name: "HuggingFace", package: "swift-huggingface"),
        .product(name: "Tokenizers", package: "swift-transformers"),
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
