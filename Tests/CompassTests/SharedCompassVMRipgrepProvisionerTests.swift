import Foundation
import XCTest

@testable import Compass

final class SharedCompassVMRipgrepProvisionerTests: XCTestCase {

  func testRenderedInstallScriptStartsWithBashShebang() {
    let script = SharedCompassVMRipgrepProvisioner.renderInstallScript()
    XCTAssertTrue(script.hasPrefix("#!/bin/bash"))
  }

  func testRenderedInstallScriptUsesStrictErrorHandling() {
    let script = SharedCompassVMRipgrepProvisioner.renderInstallScript()
    XCTAssertTrue(script.contains("set -euo pipefail"))
    XCTAssertTrue(script.contains("fail()"))
  }

  func testRenderedInstallScriptCreatesUsrLocalBinBeforeSymlink() {
    let script = SharedCompassVMRipgrepProvisioner.renderInstallScript()
    XCTAssertTrue(script.contains("install -d -o root -g wheel -m 0755 \"$(dirname \"$RG_BIN\")\""))
    XCTAssertTrue(script.contains("ln -sf \"$BREW_RG\" \"$RG_BIN\""))
  }

  func testRenderedInstallScriptRequiresHomebrewBeforeRipgrepInstall() {
    let script = SharedCompassVMRipgrepProvisioner.renderInstallScript()
    XCTAssertTrue(script.contains("Homebrew missing"))
    XCTAssertTrue(script.contains("su - \"$GUEST_USER\" -c \"'$BREW_BIN' install ripgrep\""))
  }

  func testParsePhaseFromLogTailRecognisesRipgrepPhases() {
    XCTAssertEqual(
      SharedCompassVMRipgrepProvisioner.parsePhase(
        fromLogTail: "[compass-rg] bootstrapping Homebrew as compass"
      ),
      .bootstrappingHomebrew
    )
    XCTAssertEqual(
      SharedCompassVMRipgrepProvisioner.parsePhase(fromLogTail: "exit=0"),
      .done
    )
  }

  func testProvisionShortCircuitsWhenRipgrepAlreadyInstalled() async throws {
    let runner = FakeRipgrepBashRunner()
    runner.responder = { command, _ in
      if command.contains("PRESENT") || command.contains("MISSING") {
        return ProcessResult(exitCode: 0, stdout: "PRESENT\n", stderr: "")
      }
      XCTFail("Provisioner should short-circuit before any other RPC. Got: \(command)")
      return ProcessResult(exitCode: 1, stdout: "", stderr: "unexpected")
    }
    let report = try await SharedCompassVMRipgrepProvisioner.provision(
      runner: runner,
      progress: { _ in }
    )
    XCTAssertTrue(report.alreadyInstalled)
    XCTAssertEqual(runner.callCount, 1)
  }
}

private final class FakeRipgrepBashRunner: AgentBashRunner, @unchecked Sendable {
  var responder: (@Sendable (_ command: String, _ workingDirectory: URL) -> ProcessResult)?
  private(set) var callCount: Int = 0

  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    callCount += 1
    guard let responder else {
      return ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
    return responder(command, workingDirectory)
  }
}
