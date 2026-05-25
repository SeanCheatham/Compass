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

  func testRenderedInstallScriptBootstrapsHomebrewUnderGuestUser() {
    let script = SharedCompassVMMutationToolsProvisioner.renderInstallScript()
    // brew refuses to run as root, so the install must drop privileges
    // to the compass user via `su -` and pass NONINTERACTIVE=1 to skip
    // the installer's RETURN prompt.
    XCTAssertTrue(script.contains("NONINTERACTIVE=1"))
    XCTAssertTrue(
      script.contains(
        "su - \"$GUEST_USER\" -c 'NONINTERACTIVE=1 CI=1 /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"'"
      )
    )
    XCTAssertTrue(script.contains("su - \"$GUEST_USER\" -c \"'$BREW_BIN' install ripgrep\""))
    XCTAssertTrue(
      script.contains("GUEST_USER=\"\(SharedCompassVMBundle.State.defaultGuestUserName)\"")
    )
  }

  func testRenderedInstallScriptSymlinksRipgrepIntoUsrLocalBin() {
    let script = SharedCompassVMMutationToolsProvisioner.renderInstallScript()
    // /opt/homebrew/bin isn't on path_helper's default PATH inside
    // non-interactive SSH sessions, so the brew-installed rg has to
    // be symlinked into /usr/local/bin where firstboot's zshenv
    // (path_helper) will find it.
    XCTAssertTrue(
      script.contains("ln -sf /opt/homebrew/bin/rg \"$RG_BIN\"")
    )
    XCTAssertTrue(
      script.contains("RG_BIN=\"\(SharedCompassVMMutationToolsProvisioner.ripgrepInstallPath)\"")
    )
  }

  func testRenderedInstallScriptSkipsToolWhenAlreadyPresent() {
    let script = SharedCompassVMMutationToolsProvisioner.renderInstallScript()
    // Both Muter and rg are guarded by an `[ -x ... ]` short-circuit so
    // re-running after a partial install only does the missing half.
    XCTAssertTrue(script.contains("if [ -x \"$MUTER_BIN\" ]; then"))
    XCTAssertTrue(script.contains("if [ -x \"$RG_BIN\" ]; then"))
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
    // "installed muter" is mid-script now — the ripgrep section
    // follows — so it maps to .installing, not .done.
    XCTAssertEqual(
      SharedCompassVMMutationToolsProvisioner.parsePhase(fromLogTail: "[compass-muter] installed /usr/local/bin/muter"),
      .installing
    )
  }

  func testParsePhaseFromLogTailRecognisesRipgrepPhases() {
    XCTAssertEqual(
      SharedCompassVMMutationToolsProvisioner.parsePhase(
        fromLogTail: "[compass-rg] bootstrapping Homebrew as compass"
      ),
      .bootstrappingHomebrew
    )
    XCTAssertEqual(
      SharedCompassVMMutationToolsProvisioner.parsePhase(
        fromLogTail: "[compass-rg] brew install ripgrep"
      ),
      .installingRipgrep
    )
    XCTAssertEqual(
      SharedCompassVMMutationToolsProvisioner.parsePhase(
        fromLogTail: "[compass-rg] installed /usr/local/bin/rg"
      ),
      .installingRipgrep
    )
    // The `exit=0` sentinel — written only at the very end of the
    // script after both tools are in place — is what flips to .done.
    XCTAssertEqual(
      SharedCompassVMMutationToolsProvisioner.parsePhase(fromLogTail: "exit=0"),
      .done
    )
  }

  func testProvisionShortCircuitsWhenBothToolsAlreadyInstalled() async throws {
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

  func testProbeRequiresBothMuterAndRipgrepExecutable() async throws {
    let runner = FakeMutationBashRunner()
    runner.responder = { command, _ in
      runner.lastCommand = command
      return ProcessResult(exitCode: 0, stdout: "MISSING\n", stderr: "")
    }
    let present = try await SharedCompassVMMutationToolsProvisioner.probeAlreadyInstalled(
      runner: runner
    )
    XCTAssertFalse(present)
    // Probe must `-x` test both binaries; either missing should
    // re-run the install.
    XCTAssertTrue(
      runner.lastCommand?.contains(
        "[ -x \(SharedCompassVMMutationToolsProvisioner.muterInstallPath) ]"
      ) ?? false
    )
    XCTAssertTrue(
      runner.lastCommand?.contains(
        "[ -x \(SharedCompassVMMutationToolsProvisioner.ripgrepInstallPath) ]"
      ) ?? false
    )
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
  var lastCommand: String?

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
