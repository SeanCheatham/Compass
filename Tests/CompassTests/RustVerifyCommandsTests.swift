import Testing

@testable import Compass

struct RustVerifyCommandsTests {
  @Test func cargoCommandsRenderSharedFactoryChecks() throws {
    try #require(RustVerifyCommands.cargo(RustVerifyCommands.fmt) == "cargo fmt --all --check")
    try #require(
      RustVerifyCommands.cargo(RustVerifyCommands.clippy)
        == "cargo clippy --workspace --all-targets --all-features -- -D warnings"
    )
    try #require(
      RustVerifyCommands.cargo(RustVerifyCommands.visualVerify)
        == "cargo run -p xtask -- visual-verify --emit-base64"
    )
    try #require(
      RustVerifyCommands.cargo(RustVerifyCommands.fastVerify)
        == "cargo run -p xtask -- verify"
    )
    try #require(
      RustVerifyCommands.cargo(RustVerifyCommands.factorySmoke)
        == "cargo run -p xtask -- factory-smoke"
    )
    try #require(
      RustVerifyCommands.cargo(RustVerifyCommands.factorySmokeWithScreenshot)
        == "cargo run -p xtask -- factory-smoke --emit-base64"
    )
    try #require(RustVerifyCommands.cargoSmokeCommands == [
      "cargo run -p xtask -- factory-smoke --emit-base64"
    ])
  }

  @Test func compassEngineSmokeCommandsUseRepoAndJsonFlags() throws {
    try #require(
      RustVerifyCommands.compassEngine(.workspaceOutline)
        == "compass-engine workspace-outline --repo . --format json"
    )
    try #require(
      RustVerifyCommands.compassEngine(.clippyLint, arguments: ["--all-features"])
        == "compass-engine clippy-lint --repo . --format json --all-features"
    )
    try #require(
      RustVerifyCommands.compassEngineSmokeCommands.contains(
        "compass-engine scaffold-check --repo . --format json"))
  }

  @Test func shellQuotingProtectsUnsafeArguments() throws {
    try #require(RustVerifyCommands.shellQuote("simple/path") == "simple/path")
    try #require(RustVerifyCommands.shellQuote("") == "''")
    try #require(RustVerifyCommands.shellQuote("has space") == "'has space'")
    try #require(RustVerifyCommands.shellQuote("has'quote") == "'has'\\''quote'")
  }
}
