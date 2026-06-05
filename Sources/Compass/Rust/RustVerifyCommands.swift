import Foundation

enum RustVerifyCommands {
  static let fmt = ["fmt", "--all", "--check"]
  static let clippy = [
    "clippy",
    "--workspace",
    "--all-targets",
    "--all-features",
    "--",
    "-D",
    "warnings",
  ]
  static let test = ["test", "--workspace", "--all-features"]
  static let coverage = ["llvm-cov", "--summary-only"]
  static let build = ["build", "--workspace"]
  static let runDesktop = ["run", "-p", "app-desktop"]
  static let fastVerify = ["run", "-p", "xtask", "--", "verify"]
  static let visualVerifyNoBase64 = ["run", "-p", "xtask", "--", "visual-verify"]
  static let visualVerify = ["run", "-p", "xtask", "--", "visual-verify", "--emit-base64"]
  static let productizationSmoke = ["run", "-p", "xtask", "--", "productization-smoke"]
  static let pmfSmoke = productizationSmoke
  static let factorySmoke = ["run", "-p", "xtask", "--", "factory-smoke"]
  static let factorySmokeWithScreenshot = [
    "run", "-p", "xtask", "--", "factory-smoke", "--emit-base64",
  ]
  static let engineParityCheck = ["run", "-p", "xtask", "--", "engine-parity-check"]

  static let cargoSmokeCommands = [
    cargo(factorySmokeWithScreenshot),
  ]

  static let compassEngineSmokeCommands = [
    compassEngine(.workspaceOutline),
    compassEngine(.scaffoldCheck),
    compassEngine(.cargoCheck, arguments: ["--all-features"]),
    compassEngine(.clippyLint, arguments: ["--all-features"]),
  ]

  static func cargo(_ arguments: [String]) -> String {
    shellCommand(executable: "cargo", arguments: arguments)
  }

  static func compassEngine(_ command: RustEngineCommand, arguments: [String] = []) -> String {
    shellCommand(
      executable: "compass-engine",
      arguments: [command.rawValue, "--repo", ".", "--format", "json"] + arguments
    )
  }

  static func shellCommand(executable: String, arguments: [String]) -> String {
    ([executable] + arguments).map(shellQuote).joined(separator: " ")
  }

  static func shellQuote(_ value: String) -> String {
    guard !value.isEmpty else { return "''" }
    let safe = CharacterSet(
      charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_+-./:=,@")
    if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
      return value
    }
    return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}
