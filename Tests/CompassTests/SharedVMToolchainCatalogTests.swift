import Foundation
import Testing

@testable import Compass

struct SharedVMToolchainCatalogTests {

  @Test func catalogHasUniqueIDs() throws {
    let ids = SharedVMToolchainCatalog.all.map(\.stringID)
    #require(Set(ids).count == ids.count)
  }

  @Test func defaultProvisionedIDsMatchCatalog() throws {
    #require(SharedVMToolchainCatalog.defaultProvisionedIDs.contains("command_line_tools"))
    #require(SharedVMToolchainCatalog.defaultProvisionedIDs.contains("homebrew"))
    #require(SharedVMToolchainCatalog.defaultProvisionedIDs.contains("ripgrep"))
    #require(!SharedVMToolchainCatalog.defaultProvisionedIDs.contains("rust"))
  }

  @Test func eachInstallableToolchainRendersNonEmptyScript() throws {
    for definition in SharedVMToolchainCatalog.all where definition.installableViaGenericProvisioner {
      let script = definition.renderInstallScript()
      #require(script.hasPrefix("#!/bin/bash"))
      #require(script.contains("set -euo pipefail"))
      #require(script.contains("exit=0"))
    }
  }

  @Test func dependencyIDsExistInCatalog() throws {
    let ids = Set(SharedVMToolchainCatalog.all.map(\.stringID))
    for definition in SharedVMToolchainCatalog.all {
      for dependency in definition.dependencies {
        #require(ids.contains(dependency.rawValue), "\(definition.stringID) -> \(dependency)")
      }
    }
  }

  @Test func homebrewScriptBootstrapsNonInteractively() throws {
    let script = SharedVMToolchainCatalog.definition(for: .homebrew).renderInstallScript()
    #require(script.contains("NONINTERACTIVE=1"))
    #require(script.contains("Homebrew bootstrap"))
  }

  @Test func ripgrepScriptRequiresHomebrewAndSymlinks() throws {
    let script = SharedVMToolchainCatalog.definition(for: .ripgrep).renderInstallScript()
    #require(script.contains("Homebrew missing"))
    #require(script.contains("brew install ripgrep"))
    #require(script.contains("ln -sf"))
  }

  @Test func rustScriptUsesRustup() throws {
    let script = SharedVMToolchainCatalog.definition(for: .rust).renderInstallScript()
    #require(script.contains("sh.rustup.rs"))
    #require(script.contains("--default-toolchain stable"))
  }

  @Test func nodeScriptInstallsNodeAndGlobalTypeScript() throws {
    let script = SharedVMToolchainCatalog.definition(for: .node).renderInstallScript()
    #require(script.contains("brew install node"))
    #require(script.contains("npm install -g typescript"))
    #require(script.contains("command -v tsc"))
    #require(script.contains("node --version"))
  }

  @Test func nodeProbeRequiresNodeNpmNpxAndTsc() throws {
    let probe = SharedVMToolchainCatalog.definition(for: .node).probeCommand
    #require(probe.contains("command -v node"))
    #require(probe.contains("command -v npm"))
    #require(probe.contains("command -v npx"))
    #require(probe.contains("command -v tsc"))
  }
}