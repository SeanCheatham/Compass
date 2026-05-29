import Foundation
import Testing

@testable import Compass

struct SharedCompassVMToolchainProvisionerTests {

  @Test func probeReturnsTrueWhenPresent() async throws {
    let runner = FakeToolchainBashRunner { command, _ in
      if command.contains("PRESENT") || command.contains("MISSING") {
        return ProcessResult(exitCode: 0, stdout: "PRESENT\n", stderr: "")
      }
      return ProcessResult(exitCode: 1, stdout: "", stderr: "unexpected")
    }
    let installed = try await SharedCompassVMToolchainProvisioner.probe(
      definition: SharedVMToolchainCatalog.definition(for: .homebrew),
      runner: runner
    )
    try #require(installed)
  }

  @Test func provisionShortCircuitsWhenAlreadyInstalled() async throws {
    let runner = FakeToolchainBashRunner { command, _ in
      if command.contains("PRESENT") || command.contains("MISSING") {
        return ProcessResult(exitCode: 0, stdout: "PRESENT\n", stderr: "")
      }
      #expect(Bool(false), "Unexpected command: \(command)")
      return ProcessResult(exitCode: 1, stdout: "", stderr: "")
    }
    let report = try await SharedCompassVMToolchainProvisioner.provision(
      definition: SharedVMToolchainCatalog.definition(for: .node),
      runner: runner,
      progress: { _ in }
    )
    try #require(report.alreadyInstalled)
    try #require(report.toolchainID == "node")
  }

  @Test func renderInstallLaunchDaemonPlistContainsLabel() throws {
    let plist = SharedCompassVMToolchainProvisioner.renderInstallLaunchDaemonPlist(
      definition: SharedVMToolchainCatalog.definition(for: .go)
    )
    try #require(plist.contains("com.seancheatham.Compass.toolchain-go"))
    try #require(plist.contains("compass-install-go.sh"))
  }

  @Test func pollSnapshotParsesDoneExitCode() throws {
    let raw = """
      DONE
      exit=0
      ---LOG_TAIL---
      [compass-toolchain-go] installed
      """
    let snapshot = SharedCompassVMToolchainProvisioner.PollSnapshot(parsing: raw)
    try #require(snapshot.exitCode == 0)
    try #require(snapshot.logTail.contains("installed"))
  }
}

private final class FakeToolchainBashRunner: AgentBashRunner, @unchecked Sendable {
  let responder: @Sendable (_ command: String, _ workingDirectory: URL) -> ProcessResult

  init(responder: @escaping @Sendable (_ command: String, _ workingDirectory: URL) -> ProcessResult) {
    self.responder = responder
  }

  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    responder(command, workingDirectory)
  }
}