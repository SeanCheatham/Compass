import Foundation
import Testing

@testable import Compass

struct SharedCompassVMToolchainProvisionerTests {

  @Test func installedToolchainIDsFromStateBackfillsCurrentDefaults() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let bundle = SharedCompassVMBundle(rootURL: root.appending(path: "bundle.vmbundle"))
    try bundle.saveState(
      SharedCompassVMBundle.State(
        provisionStep: .ready,
        installedToolchains: ["command_line_tools", "homebrew", "ripgrep"]
      )
    )

    let manager = SharedCompassVMToolchainManager(bundle: bundle)
    let ids = manager.installedToolchainIDsFromState()

    try #require(ids.contains("rust"))
    try #require(!ids.contains("node"))
    try #require(ids == ids.sorted())
  }

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

  @Test func provisionErrorLocalizedDescriptionUsesDetailedMessage() throws {
    let error = SharedCompassVMToolchainProvisioner.ProvisionError.probeFailed(
      toolchainID: "node",
      stderr: "vsock connect failed"
    )
    try #require(
      error.localizedDescription == "Toolchain node probe failed: vsock connect failed")
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
      definition: SharedVMToolchainCatalog.definition(for: .node)
    )
    try #require(plist.contains("com.seancheatham.Compass.toolchain-node"))
    try #require(plist.contains("compass-install-node.sh"))
  }

  @Test func pollSnapshotParsesDoneExitCode() throws {
    let raw = """
      DONE
      exit=0
      ---LOG_TAIL---
      [compass-toolchain-node] installed
      """
    let snapshot = SharedCompassVMToolchainProvisioner.PollSnapshot(parsing: raw)
    try #require(snapshot.exitCode == 0)
    try #require(snapshot.logTail.contains("installed"))
  }
}

private final class FakeToolchainBashRunner: AgentBashRunner, @unchecked Sendable {
  let responder: @Sendable (_ command: String, _ workingDirectory: URL) -> ProcessResult

  init(responder: @escaping @Sendable (_ command: String, _ workingDirectory: URL) -> ProcessResult)
  {
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
