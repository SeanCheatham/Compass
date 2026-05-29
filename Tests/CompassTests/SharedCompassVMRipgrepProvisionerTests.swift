import Foundation
import Testing

@testable import Compass

struct SharedCompassVMRipgrepProvisionerTests {

  @Test func renderedInstallScriptStartsWithBashShebang() throws {
    let script = SharedCompassVMRipgrepProvisioner.renderInstallScript()
    try #require(script.hasPrefix("#!/bin/bash"))
  }

  @Test func renderedInstallScriptUsesStrictErrorHandling() throws {
    let script = SharedCompassVMRipgrepProvisioner.renderInstallScript()
    try #require(script.contains("set -euo pipefail"))
    try #require(script.contains("fail()"))
  }

  @Test func renderedInstallScriptCreatesUsrLocalBinBeforeSymlink() throws {
    let script = SharedCompassVMRipgrepProvisioner.renderInstallScript()
    try #require(script.contains("install -d -o root -g wheel -m 0755 \"$(dirname \"$RG_BIN\")\""))
    try #require(script.contains("ln -sf \"$BREW_RG\" \"$RG_BIN\""))
  }

  @Test func renderedInstallScriptRequiresHomebrewBeforeRipgrepInstall() throws {
    let script = SharedCompassVMRipgrepProvisioner.renderInstallScript()
    try #require(script.contains("Homebrew missing"))
    try #require(script.contains("su - \"$GUEST_USER\" -c \"'$BREW_BIN' install ripgrep\""))
  }

  @Test func parsePhaseFromLogTailRecognisesRipgrepPhases() throws {
    try #require(
      SharedCompassVMRipgrepProvisioner.parsePhase(
        fromLogTail: "[compass-rg] bootstrapping Homebrew as compass"
      ) == .bootstrappingHomebrew
    )
    try #require(
      SharedCompassVMRipgrepProvisioner.parsePhase(fromLogTail: "exit=0") == .done
    )
  }

  @Test func provisionShortCircuitsWhenRipgrepAlreadyInstalled() async throws {
    let runner = FakeRipgrepBashRunner()
    runner.responder = { command, _ in
      if command.contains("PRESENT") || command.contains("MISSING") {
        return ProcessResult(exitCode: 0, stdout: "PRESENT\n", stderr: "")
      }
      #expect(Bool(false), "Provisioner should short-circuit before any other RPC. Got: \(command)")
      return ProcessResult(exitCode: 1, stdout: "", stderr: "unexpected")
    }
    let report = try await SharedCompassVMRipgrepProvisioner.provision(
      runner: runner,
      progress: { _ in }
    )
    try #require(report.alreadyInstalled)
    try #require(runner.callCount == 1)
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