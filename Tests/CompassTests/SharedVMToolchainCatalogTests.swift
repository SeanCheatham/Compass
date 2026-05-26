import Foundation
import XCTest

@testable import Compass

final class SharedVMToolchainCatalogTests: XCTestCase {

  func testCatalogHasUniqueIDs() {
    let ids = SharedVMToolchainCatalog.all.map(\.stringID)
    XCTAssertEqual(Set(ids).count, ids.count)
  }

  func testDefaultProvisionedIDsMatchCatalog() {
    XCTAssertTrue(SharedVMToolchainCatalog.defaultProvisionedIDs.contains("command_line_tools"))
    XCTAssertTrue(SharedVMToolchainCatalog.defaultProvisionedIDs.contains("homebrew"))
    XCTAssertTrue(SharedVMToolchainCatalog.defaultProvisionedIDs.contains("ripgrep"))
    XCTAssertFalse(SharedVMToolchainCatalog.defaultProvisionedIDs.contains("rust"))
  }

  func testEachInstallableToolchainRendersNonEmptyScript() {
    for definition in SharedVMToolchainCatalog.all where definition.installableViaGenericProvisioner {
      let script = definition.renderInstallScript()
      XCTAssertTrue(script.hasPrefix("#!/bin/bash"), definition.stringID)
      XCTAssertTrue(script.contains("set -euo pipefail"), definition.stringID)
      XCTAssertTrue(script.contains("exit=0"), definition.stringID)
    }
  }

  func testDependencyIDsExistInCatalog() {
    let ids = Set(SharedVMToolchainCatalog.all.map(\.stringID))
    for definition in SharedVMToolchainCatalog.all {
      for dependency in definition.dependencies {
        XCTAssertTrue(ids.contains(dependency.rawValue), "\(definition.stringID) -> \(dependency)")
      }
    }
  }

  func testHomebrewScriptBootstrapsNonInteractively() {
    let script = SharedVMToolchainCatalog.definition(for: .homebrew).renderInstallScript()
    XCTAssertTrue(script.contains("NONINTERACTIVE=1"))
    XCTAssertTrue(script.contains("Homebrew bootstrap"))
  }

  func testRipgrepScriptRequiresHomebrewAndSymlinks() {
    let script = SharedVMToolchainCatalog.definition(for: .ripgrep).renderInstallScript()
    XCTAssertTrue(script.contains("Homebrew missing"))
    XCTAssertTrue(script.contains("brew install ripgrep"))
    XCTAssertTrue(script.contains("ln -sf"))
  }

  func testRustScriptUsesRustup() {
    let script = SharedVMToolchainCatalog.definition(for: .rust).renderInstallScript()
    XCTAssertTrue(script.contains("sh.rustup.rs"))
    XCTAssertTrue(script.contains("--default-toolchain stable"))
  }

  func testNodeScriptInstallsNodeAndGlobalTypeScript() {
    let script = SharedVMToolchainCatalog.definition(for: .node).renderInstallScript()
    XCTAssertTrue(script.contains("brew install node"))
    XCTAssertTrue(script.contains("npm install -g typescript"))
    XCTAssertTrue(script.contains("command -v tsc"))
    XCTAssertTrue(script.contains("node --version"))
  }

  func testNodeProbeRequiresNodeNpmNpxAndTsc() {
    let probe = SharedVMToolchainCatalog.definition(for: .node).probeCommand
    XCTAssertTrue(probe.contains("command -v node"))
    XCTAssertTrue(probe.contains("command -v npm"))
    XCTAssertTrue(probe.contains("command -v npx"))
    XCTAssertTrue(probe.contains("command -v tsc"))
  }
}
