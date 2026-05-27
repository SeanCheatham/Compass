import Foundation
import Testing

@testable import Compass

struct SharedCompassVMRipgrepProvisionerTests {

  @Test func renderedInstallScriptStartsWithBashShebang() {
    let script = SharedCompassVMRipgrepProvisioner.renderInstallScript()
    #require(script.hasPrefix("#!/bin/bash"))
  }

  @Test func renderedInstallScriptUsesStrictErrorHandling() {
    let script = SharedCompassVMRipgrepProvisioner.renderInstallScript()
    #require(script.contains("set -euo pipefail"))
    #require(script.contains("fail()"))
  }

  @Test func renderedInstallScriptCreatesUsrLocalBinBeforeSymlink() {
    let script = SharedCompassVMRipgrepProvisioner.renderInstallScript()
    #require(script.contains("install -d -o root -g wheel -m 0755 \"$(dirname \"$RG_BIN\")\""))
    #require(script.contains("ln -sf \"$BREW_RG\" \"$RG_BIN\""))
  }

  @Test func renderedInstallScriptRequiresHomebrewBeforeRipgrepInstall() {
    let script = SharedCompassVMRipgrepProvisioner.renderInstallScript()
    #require(script.contains("Homebrew missing"))
    #require(script.contains("su - \"$GUEST_USER\" -c \"'$BREW_BIN' install ripgrep\""))
  }

  @Test func parsePhaseFromLogTailRecognisesRipgrepPhases() {
    #require(
      SharedCompassVMRipgrepProvisioner.parsePhase(
        fromLogTail: "[compass-rg] bootstrapping Homebrew as compass"
      ) == .bootstrappingHomebrew
    )
    #require(
      SharedCompassVMRipgrepProvisioner.parsePhase(fromLogTail: "exit=0") == .done
    )
  }

  @Test func provisionShortCircuitsWhenRipgrepAlreadyInstalled() async throws {
    let runner = FakeRipgrepBashRunner()
    runner.responder = { command, _ in
      if command.contains("PRESENT") || command.contains("MISSING") {
        return ProcessResult(exitCode: 0, stdout: "PRESENT\n", stderr: "")
      }
      #require(false, "Provisioner should short-circuit before any other RPC. Got: \(command)")
      return ProcessResult(exitCode: 1, stdout: "", stderr: "unexpected")
    }
    let report = try await SharedCompassVMRipgrepProvisioner.provision(
      runner: runner,
      progress: { _ in }
    )
    #require(report.alreadyInstalled)
    #require(runner.callCount == 1)
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