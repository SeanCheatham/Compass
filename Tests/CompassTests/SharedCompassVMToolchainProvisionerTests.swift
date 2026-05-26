import Foundation
import XCTest

@testable import Compass

final class SharedCompassVMToolchainProvisionerTests: XCTestCase {

  func testProbeReturnsTrueWhenPresent() async throws {
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
    XCTAssertTrue(installed)
  }

  func testProvisionShortCircuitsWhenAlreadyInstalled() async throws {
    let runner = FakeToolchainBashRunner { command, _ in
      if command.contains("PRESENT") || command.contains("MISSING") {
        return ProcessResult(exitCode: 0, stdout: "PRESENT\n", stderr: "")
      }
      XCTFail("Unexpected command: \(command)")
      return ProcessResult(exitCode: 1, stdout: "", stderr: "")
    }
    let report = try await SharedCompassVMToolchainProvisioner.provision(
      definition: SharedVMToolchainCatalog.definition(for: .node),
      runner: runner,
      progress: { _ in }
    )
    XCTAssertTrue(report.alreadyInstalled)
    XCTAssertEqual(report.toolchainID, "node")
  }

  func testRenderInstallLaunchDaemonPlistContainsLabel() {
    let plist = SharedCompassVMToolchainProvisioner.renderInstallLaunchDaemonPlist(
      definition: SharedVMToolchainCatalog.definition(for: .go)
    )
    XCTAssertTrue(plist.contains("com.seancheatham.Compass.toolchain-go"))
    XCTAssertTrue(plist.contains("compass-install-go.sh"))
  }

  func testPollSnapshotParsesDoneExitCode() {
    let raw = """
      DONE
      exit=0
      ---LOG_TAIL---
      [compass-toolchain-go] installed
      """
    let snapshot = SharedCompassVMToolchainProvisioner.PollSnapshot(parsing: raw)
    XCTAssertEqual(snapshot.exitCode, 0)
    XCTAssertTrue(snapshot.logTail.contains("installed"))
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
