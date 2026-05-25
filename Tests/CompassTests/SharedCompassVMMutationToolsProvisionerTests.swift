import Foundation
import XCTest

@testable import Compass

final class SharedCompassVMMutationToolsProvisionerTests: XCTestCase {

  func testRenderedInstallScriptStartsWithBashShebang() {
    let script = SharedCompassVMMutationToolsProvisioner.renderInstallScript()
    XCTAssertTrue(script.hasPrefix("#!/bin/bash"))
  }

  func testRenderedInstallScriptBuildsPinnedMuterRelease() {
    let script = SharedCompassVMMutationToolsProvisioner.renderInstallScript()
    XCTAssertTrue(script.contains("muter-mutation-testing/muter/archive/refs/tags/${MUTER_TAG}.tar.gz"))
    XCTAssertTrue(script.contains("\"$CLT_SWIFT\" build -c release"))
    XCTAssertTrue(script.contains("install -m 755 .build/release/muter \"$MUTER_BIN\""))
  }

  func testRenderedInstallScriptRequiresCLTSwift() {
    let script = SharedCompassVMMutationToolsProvisioner.renderInstallScript()
    XCTAssertTrue(script.contains(SharedCompassVMDevToolsProvisioner.cltSwiftPath))
    XCTAssertTrue(script.contains("Command Line Tools swift missing"))
  }

  func testRenderedLaunchDaemonPlistIsValid() throws {
    let plist = SharedCompassVMMutationToolsProvisioner.renderInstallLaunchDaemonPlist()
    let parsed =
      try PropertyListSerialization.propertyList(
        from: Data(plist.utf8),
        options: [],
        format: nil
      ) as? [String: Any]
    XCTAssertNotNil(parsed)
    XCTAssertEqual(
      parsed?["Label"] as? String,
      SharedCompassVMMutationToolsProvisioner.installLaunchDaemonLabel
    )
    let args = parsed?["ProgramArguments"] as? [String]
    XCTAssertEqual(args, [SharedCompassVMMutationToolsProvisioner.scriptGuestPath])
  }

  func testParsePhaseFromLogTailRecognisesDownloadAndBuild() {
    XCTAssertEqual(
      SharedCompassVMMutationToolsProvisioner.parsePhase(fromLogTail: "[compass-muter] downloading release 16"),
      .downloading
    )
    XCTAssertEqual(
      SharedCompassVMMutationToolsProvisioner.parsePhase(fromLogTail: "[compass-muter] building Muter with guest swift"),
      .building
    )
    XCTAssertEqual(
      SharedCompassVMMutationToolsProvisioner.parsePhase(fromLogTail: "[compass-muter] installed /usr/local/bin/muter"),
      .done
    )
  }

  func testProvisionShortCircuitsWhenMuterAlreadyInstalled() async throws {
    let runner = FakeMutationBashRunner()
    runner.responder = { command, _ in
      if command.contains("PRESENT") || command.contains("MISSING") {
        return ProcessResult(exitCode: 0, stdout: "PRESENT\n", stderr: "")
      }
      XCTFail("Provisioner should short-circuit before any other RPC. Got: \(command)")
      return ProcessResult(exitCode: 1, stdout: "", stderr: "unexpected")
    }
    var progressUpdates: [Double] = []
    let report = try await SharedCompassVMMutationToolsProvisioner.provision(
      runner: runner,
      progress: { progressUpdates.append($0) }
    )
    XCTAssertTrue(report.alreadyInstalled)
    XCTAssertEqual(runner.callCount, 1)
    XCTAssertEqual(progressUpdates.first, 0)
    XCTAssertEqual(progressUpdates.last, 1)
  }

  func testProvisionDrivesFullInstallFlow() async throws {
    let runner = FakeMutationBashRunner()
    var pollCount = 0
    runner.responder = { command, _ in
      if command.contains("PRESENT") || command.contains("MISSING") {
        if runner.callCount == 1 {
          return ProcessResult(exitCode: 0, stdout: "MISSING\n", stderr: "")
        }
        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
      }
      if command.contains("base64 -D | sudo tee") {
        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
      }
      if command.contains("launchctl bootstrap system") {
        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
      }
      if command.contains("DONE") && command.contains("---LOG_TAIL---") {
        pollCount += 1
        switch pollCount {
        case 1:
          return ProcessResult(
            exitCode: 0,
            stdout: """
              RUNNING
              ---LOG_TAIL---
              [compass-muter] downloading release 16
              """,
            stderr: ""
          )
        case 2:
          return ProcessResult(
            exitCode: 0,
            stdout: """
              RUNNING
              ---LOG_TAIL---
              [compass-muter] building Muter with guest swift
              """,
            stderr: ""
          )
        default:
          return ProcessResult(
            exitCode: 0,
            stdout: """
              DONE
              exit=0
              ---LOG_TAIL---
              [compass-muter] installed /usr/local/bin/muter
              """,
            stderr: ""
          )
        }
      }
      if command.contains("test -x \(SharedCompassVMMutationToolsProvisioner.muterInstallPath)") {
        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
      }
      return ProcessResult(exitCode: 1, stdout: "", stderr: "unexpected: \(command)")
    }

    let report = try await SharedCompassVMMutationToolsProvisioner.provision(
      runner: runner,
      progress: { _ in },
      now: { Date() },
      sleep: { _ in }
    )
    XCTAssertFalse(report.alreadyInstalled)
    XCTAssertGreaterThanOrEqual(runner.callCount, 5)
  }
}

private final class FakeMutationBashRunner: AgentBashRunner, @unchecked Sendable {
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
