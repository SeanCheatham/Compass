import Foundation
import Testing

@testable import Compass

struct SharedVMToolchainCatalogTests {

  @Test func catalogHasUniqueIDs() throws {
    let ids = SharedVMToolchainCatalog.all.map(\.stringID)
    try #require(Set(ids).count == ids.count)
  }

  @Test func defaultProvisionedIDsMatchCatalog() throws {
    try #require(SharedVMToolchainCatalog.defaultProvisionedIDs.contains("command_line_tools"))
    try #require(SharedVMToolchainCatalog.defaultProvisionedIDs.contains("homebrew"))
    try #require(SharedVMToolchainCatalog.defaultProvisionedIDs.contains("ripgrep"))
    try #require(SharedVMToolchainCatalog.defaultProvisionedIDs.contains("rust"))
    try #require(!SharedVMToolchainCatalog.defaultProvisionedIDs.contains("node"))
  }

  @Test func defaultToolchainsCenterGeneratedRustAndMarkNodeLegacy() throws {
    let clt = SharedVMToolchainCatalog.definition(for: .commandLineTools)
    let rust = SharedVMToolchainCatalog.definition(for: .rust)
    let node = SharedVMToolchainCatalog.definition(for: .node)

    try #require(clt.description.contains("Rust native linking"))
    try #require(rust.defaultProvisioned)
    try #require(rust.description.contains("Rust generated-project toolchain"))
    try #require(!node.defaultProvisioned)
    try #require(node.displayName.contains("Legacy"))
    try #require(node.description.contains("Not provisioned for generated Rust projects"))
  }

  @Test func eachInstallableToolchainRendersNonEmptyScript() throws {
    for definition in SharedVMToolchainCatalog.all where definition.installableViaGenericProvisioner
    {
      let script = definition.renderInstallScript()
      try #require(script.hasPrefix("#!/bin/bash"))
      try #require(script.contains("set -euo pipefail"))
      try #require(script.contains("exit=0"))
    }
  }

  @Test func dependencyIDsExistInCatalog() throws {
    let ids = Set(SharedVMToolchainCatalog.all.map(\.stringID))
    for definition in SharedVMToolchainCatalog.all {
      for dependency in definition.dependencies {
        try #require(ids.contains(dependency.rawValue), "\(definition.stringID) -> \(dependency)")
      }
    }
  }

  @Test func homebrewScriptBootstrapsNonInteractively() throws {
    let script = SharedVMToolchainCatalog.definition(for: .homebrew).renderInstallScript()
    try #require(script.contains("NONINTERACTIVE=1"))
    try #require(script.contains("Homebrew bootstrap"))
  }

  @Test func ripgrepScriptRequiresHomebrewAndSymlinks() throws {
    let script = SharedVMToolchainCatalog.definition(for: .ripgrep).renderInstallScript()
    try #require(script.contains("Homebrew missing"))
    try #require(script.contains("brew install ripgrep"))
    try #require(script.contains("ln -sf"))
  }

  @Test func rustScriptUsesRustup() throws {
    let script = SharedVMToolchainCatalog.definition(for: .rust).renderInstallScript()
    try #require(script.contains("sh.rustup.rs"))
    try #require(script.contains("--default-toolchain stable"))
    try #require(script.contains("export PATH=\"$HOME/.cargo/bin:$PATH\"; rustup component add"))
    try #require(script.contains("export PATH=\"$HOME/.cargo/bin:$PATH\"; cargo install"))
    try #require(script.contains("rustup component add rustfmt clippy"))
    try #require(script.contains("cargo install cargo-llvm-cov --locked"))
  }

  @Test func rustProbeRequiresGeneratedProjectToolchain() throws {
    let probe = SharedVMToolchainCatalog.definition(for: .rust).probeCommand
    try #require(probe.contains("export PATH=\"$HOME/.cargo/bin:$PATH\""))
    try #require(probe.contains("command -v rustc"))
    try #require(probe.contains("command -v cargo"))
    try #require(probe.contains("command -v rustfmt"))
    try #require(probe.contains("command -v cargo-clippy"))
    try #require(probe.contains("command -v cargo-llvm-cov"))
  }

  @Test func nodeScriptInstallsNodeAndGlobalTypeScript() throws {
    let script = SharedVMToolchainCatalog.definition(for: .node).renderInstallScript()
    try #require(script.contains("brew install node"))
    try #require(script.contains("npm install -g typescript"))
    try #require(script.contains("command -v tsc"))
    try #require(script.contains("node --version"))
  }

  @Test func nodeProbeRequiresNodeNpmNpxAndTsc() throws {
    let probe = SharedVMToolchainCatalog.definition(for: .node).probeCommand
    try #require(probe.contains("command -v node"))
    try #require(probe.contains("command -v npm"))
    try #require(probe.contains("command -v npx"))
    try #require(probe.contains("command -v tsc"))
  }
}
