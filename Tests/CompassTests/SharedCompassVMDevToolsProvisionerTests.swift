import Foundation
import Testing

@testable import Compass

/// Coverage for `SharedCompassVMDevToolsProvisioner`. Two layers:
///
/// 1. Pure helpers — the rendered install script and the log-tail
///    progress parsers. These are byte-stable contracts; Apple has changed
///    `softwareupdate` output across major macOS releases before, and a
///    silent regression here breaks every CLT install going forward.
///
/// 2. End-to-end with a `FakeBashRunner` driving the provisioner through
///    probe → install kickoff → poll → finalise, exercising both the
///    happy path and the failure modes the caller has to react to
///    (timeout, non-zero exit, kickoff failure, finalise failure).
struct SharedCompassVMDevToolsProvisionerTests {

  // MARK: - Rendered install script

  @Test
  func testRenderedInstallScriptStartsWithBashShebang() {
    let script = SharedCompassVMDevToolsProvisioner.renderInstallScript()
    #require(script.hasPrefix("#!/bin/bash"))
  }

  @Test
  func testRenderedInstallScriptTouchesAppleSoftwareupdateSentinel() {
    let script = SharedCompassVMDevToolsProvisioner.renderInstallScript()
    // The well-known sentinel softwareupdate looks for to expose CLT
    // in its catalog without a GUI session. Bytes pinned because Apple
    // sometimes changes the path across majors — diverging silently
    // would break headless install on the new major with no error.
    #require(
      script.contains("touch \"$SENTINEL\""),
      "Script must touch the softwareupdate CLT request sentinel"
    )
    #require(
      script.contains("/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"),
      "Script must reference Apple's documented CLT-install sentinel path"
    )
  }

  @Test
  func testRenderedInstallScriptPicksLatestCLTLabel() {
    let script = SharedCompassVMDevToolsProvisioner.renderInstallScript()
    // Pick by `tail -n1` of the catalog entries whose lines start
    // with `* Label: Command Line Tools`. Apple sometimes ships
    // multiple labels (different Xcode majors); newest one wins.
    // The `^\* Label:` anchor matters — on macOS 26+ each Label
    // entry is followed by an indented `Title: Command Line Tools …`
    // line that the older un-anchored matcher would also pick up
    // (producing an empty label string and breaking install).
    #require(script.contains("softwareupdate -l"))
    #require(
      script.contains("'^\\* Label: Command Line Tools'"),
      "Label selector must anchor on the '* Label:' line, not match any 'Command Line Tools' substring"
    )
    #require(script.contains("tail -n1"))
  }

  @Test
  func testRenderedInstallScriptInvokesSoftwareupdateVerbose() {
    let script = SharedCompassVMDevToolsProvisioner.renderInstallScript()
    #require(
      script.contains("softwareupdate -i \"$LABEL\" --verbose"),
      "Must use --verbose so the host can parse progress phases out of the log"
    )
  }

  @Test
  func testRenderedInstallScriptActivatesCLTAfterSuccess() {
    let script = SharedCompassVMDevToolsProvisioner.renderInstallScript()
    #require(
      script.contains("xcode-select -s /Library/Developer/CommandLineTools"),
      "Successful install must promote CLT to active developer dir so subsequent calls (swift, clang) work without xcode-select"
    )
  }

  @Test
  func testRenderedInstallScriptWritesDoneSentinelInAllExitPaths() {
    let script = SharedCompassVMDevToolsProvisioner.renderInstallScript()
    // Two exit paths: missing label (rc=2) and softwareupdate completion
    // (rc=whatever). Both must touch the done-sentinel or the host's
    // pollUntilDone loop will hang to the timeout.
    #require(script.contains("echo \"exit=2\" > \"$DONE_PATH\""))
    #require(script.contains("echo \"exit=$rc\" > \"$DONE_PATH\""))
  }

  @Test
  func testRenderedInstallScriptRemovesSentinelOnAllExitPaths() {
    let script = SharedCompassVMDevToolsProvisioner.renderInstallScript()
    // Both early-exit (missing label) and the post-install path must
    // remove the in-progress sentinel; leaving it behind on the guest
    // would confuse future softwareupdate calls (some Apple tooling
    // refuses to re-list CLT when the sentinel is stuck).
    let occurrences = script.components(separatedBy: "rm -f \"$SENTINEL\"").count - 1
    #require(occurrences >= 2, "Sentinel must be cleared on both exit paths")
  }

  // MARK: - LaunchDaemon plist

  @Test
  func testRenderedLaunchDaemonPlistIsValid() throws {
    let plist = SharedCompassVMDevToolsProvisioner.renderInstallLaunchDaemonPlist()
    let parsed =
      try PropertyListSerialization.propertyList(
        from: Data(plist.utf8),
        options: [],
        format: nil
      ) as? [String: Any]
    #require(parsed != nil)
    #require(parsed?["Label"] as? String == "com.seancheatham.Compass.devtools-install")
    #require(parsed?["RunAtLoad"] as? Bool == true)
    // KeepAlive must be false so the script runs once and exits;
    // KeepAlive=true would have launchd restart softwareupdate after
    // it succeeds, looping forever.
    #require(parsed?["KeepAlive"] as? Bool == false)
    #require(parsed?["LaunchOnlyOnce"] as? Bool == true)
    let args = parsed?["ProgramArguments"] as? [String]
    #require(args == ["/usr/local/libexec/compass-install-clt.sh"])
  }

  // MARK: - Phase parsing

  @Test
  func testParsePhaseFromLogTailRecognisesScriptStart() {
    let tail = "[compass-clt] 2026-05-21T17:00:00Z starting"
    #require(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail) == .scriptRunning)
  }

  @Test
  func testParsePhaseFromLogTailRecognisesDownloading() {
    let tail = """
      [compass-clt] selected label: Command Line Tools for Xcode-15.2
      Downloading: Command Line Tools for Xcode
      """
    #require(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail) == .downloading)
  }

  @Test
  func testParsePhaseFromLogTailRecognisesDownloadingMacOS26Form() {
    // macOS 26's softwareupdate --verbose drops the trailing colon
    // we used to key on. Confirmed live against a Sequoia successor
    // guest: "Downloading Command Line Tools for Xcode 26.5".
    let tail = "Downloading Command Line Tools for Xcode 26.5"
    #require(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail) == .downloading)
  }

  @Test
  func testParsePhaseFromLogTailRecognisesDownloaded() {
    let tail = "Downloaded: Command Line Tools for Xcode"
    #require(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail) == .downloaded)
  }

  @Test
  func testParsePhaseFromLogTailRecognisesDownloadedMacOS26Form() {
    let tail = "Downloaded Command Line Tools for Xcode 26.5"
    #require(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail) == .downloaded)
  }

  @Test
  func testParsePhaseFromLogTailRecognisesInstalling() {
    let tail = "Installing: Command Line Tools for Xcode"
    #require(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail) == .installing)
  }

  @Test
  func testParsePhaseFromLogTailRecognisesInstallingMacOS26Form() {
    let tail = "Installing Command Line Tools for Xcode 26.5"
    #require(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail) == .installing)
  }

  @Test
  func testParsePhaseFromLogTailRecognisesInstalled() {
    let tail = "Installed: Command Line Tools for Xcode"
    #require(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail) == .installed)
  }

  @Test
  func testParsePhaseFromLogTailRecognisesInstalledMacOS26Form() {
    let tail = "Installed Command Line Tools for Xcode 26.5"
    #require(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail) == .installed)
  }

  @Test
  func testParsePhaseFromLogTailRecognisesDone() {
    let tail = """
      Installed: Command Line Tools for Xcode
      Done.
      [compass-clt] softwareupdate exit=0
      """
    #require(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail) == .done)
  }

  @Test
  func testParsePhaseFromLogTailReturnsNilForNoise() {
    #require(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: "") == nil)
    #require(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: "no markers here") == nil)
  }

  @Test
  func testFractionForPhaseIsMonotone() {
    let order: [SharedCompassVMDevToolsProvisioner.InstallPhase] = [
      .kickoff, .scriptRunning, .downloading, .downloaded, .installing, .installed, .done,
    ]
    let fractions = order.map(SharedCompassVMDevToolsProvisioner.fractionForPhase)
    for i in 1..<fractions.count {
      #require(
        fractions[i] > fractions[i - 1],
        "Fraction for \(order[i]) must be strictly greater than for \(order[i - 1])"
      )
    }
    #require(fractions.last == 1.0)
  }

  // MARK: - Poll snapshot parsing

  @Test
  func testPollSnapshotParsesRunningWhenSentinelAbsent() {
    let raw = """
      RUNNING
      ---LOG_TAIL---
      Downloading: Command Line Tools for Xcode
      """
    let snapshot = SharedCompassVMDevToolsProvisioner.PollSnapshot(parsing: raw)
    #require(snapshot.exitCode == nil)
    #require(snapshot.logTail.contains("Downloading"))
  }

  @Test
  func testPollSnapshotParsesSuccessExit() {
    let raw = """
      DONE
      exit=0
      ---LOG_TAIL---
      Done.
      """
    let snapshot = SharedCompassVMDevToolsProvisioner.PollSnapshot(parsing: raw)
    #require(snapshot.exitCode == 0)
    #require(snapshot.logTail.contains("Done."))
  }

  @Test
  func testPollSnapshotParsesFailureExit() {
    let raw = """
      DONE
      exit=2
      ---LOG_TAIL---
      ERROR: no Command Line Tools label found
      """
    let snapshot = SharedCompassVMDevToolsProvisioner.PollSnapshot(parsing: raw)
    #require(snapshot.exitCode == 2)
  }

  @Test
  func testPollSnapshotTreatsMissingExitLineAsFailure() {
    // Defensive: if the cat-of-sentinel got truncated, we must NOT
    // hang waiting for a clean exit code — treat as failure so the
    // caller surfaces the issue.
    let raw = """
      DONE
      ---LOG_TAIL---
      """
    let snapshot = SharedCompassVMDevToolsProvisioner.PollSnapshot(parsing: raw)
    #require(snapshot.exitCode == -1)
  }

  // MARK: - Full provisioner flow with a fake runner

  @Test
  func testProvisionShortCircuitsWhenCLTAlreadyInstalled() async throws {
    let runner = FakeBashRunner()
    runner.responder = { command, _ in
      if command.contains("PRESENT") || command.contains("MISSING") {
        return ProcessResult(exitCode: 0, stdout: "PRESENT\n", stderr: "")
      }
      #require(false, "Provisioner should short-circuit before any other RPC. Got: \(command)")
      return ProcessResult(exitCode: 1, stdout: "", stderr: "unexpected")
    }
    var progressUpdates: [Double] = []
    let report = try await SharedCompassVMDevToolsProvisioner.provision(
      runner: runner,
      progress: { progressUpdates.append($0) }
    )
    #require(report.alreadyInstalled)
    #require(runner.callCount == 1)
    #require(progressUpdates.first == 0)
    #require(progressUpdates.last == 1)
  }

  @Test
  func testProvisionDrivesFullInstallFlow() async throws {
    let runner = FakeBashRunner()
    var pollCount = 0
    runner.responder = { command, _ in
      // Probe — first call.
      if command.contains("PRESENT") || command.contains("MISSING") {
        if runner.callCount == 1 {
          return ProcessResult(exitCode: 0, stdout: "MISSING\n", stderr: "")
        }
        // Finalise re-probes via the xcode-select -p chain.
        return ProcessResult(
          exitCode: 0, stdout: "/Library/Developer/CommandLineTools\n", stderr: "")
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
              [compass-clt] starting
              """,
            stderr: ""
          )
        case 2:
          return ProcessResult(
            exitCode: 0,
            stdout: """
              RUNNING
              ---LOG_TAIL---
              Downloading: Command Line Tools for Xcode
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
              Done.
              """,
            stderr: ""
          )
        }
      }
      if command.contains("sudo xcode-select -s") {
        return ProcessResult(
          exitCode: 0, stdout: "/Library/Developer/CommandLineTools\n", stderr: "")
      }
      #require(false, "Unexpected RPC: \(command)")
      return ProcessResult(exitCode: 1, stdout: "", stderr: "unexpected")
    }

    var progressUpdates: [Double] = []
    let report = try await SharedCompassVMDevToolsProvisioner.provision(
      runner: runner,
      progress: { progressUpdates.append($0) },
      now: { Date() },
      sleep: { _ in }  // Drive the poll loop without real waits.
    )

    #require(!report.alreadyInstalled)
    #require(pollCount >= 3)
    #require(progressUpdates.first == 0)
    #require(progressUpdates.last == 1)
    // Monotone — once we've seen a higher fraction we must never go
    // back. UI would otherwise flicker backwards.
    for i in 1..<progressUpdates.count {
      #require(progressUpdates[i] >= progressUpdates[i - 1])
    }
  }

  @Test
  func testProvisionThrowsOnInstallFailure() async {
    let runner = FakeBashRunner()
    runner.responder = { command, _ in
      if command.contains("PRESENT") || command.contains("MISSING") {
        return ProcessResult(exitCode: 0, stdout: "MISSING\n", stderr: "")
      }
      if command.contains("base64 -D | sudo tee") || command.contains("launchctl bootstrap system")
      {
        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
      }
      if command.contains("DONE") && command.contains("---LOG_TAIL---") {
        return ProcessResult(
          exitCode: 0,
          stdout: """
            DONE
            exit=2
            ---LOG_TAIL---
            ERROR: no Command Line Tools label found in softwareupdate catalog
            """,
          stderr: ""
        )
      }
      return ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
    var threw = false
    do {
      _ = try await SharedCompassVMDevToolsProvisioner.provision(
        runner: runner,
        progress: { _ in },
        now: { Date() },
        sleep: { _ in }
      )
    } catch let error as SharedCompassVMDevToolsProvisioner.ProvisionError {
      threw = true
      guard case .installFailed(let code, let tail) = error else {
        #require(false, "Expected .installFailed, got \(error)")
        return
      }
      #require(code == 2)
      #require(tail.contains("no Command Line Tools label"))
    } catch {
      #require(false, "Unexpected error type: \(error)")
    }
    #require(threw, "Expected installFailed")
  }

  @Test
  func testProvisionThrowsOnPollTimeout() async {
    // Force `now()` to advance past the install deadline immediately
    // on the second call, so the poll loop sees one RUNNING reply and
    // then gives up. Verifies the timeout path surfaces the last
    // observed phase + log tail in the error message.
    let runner = FakeBashRunner()
    runner.responder = { command, _ in
      if command.contains("PRESENT") || command.contains("MISSING") {
        return ProcessResult(exitCode: 0, stdout: "MISSING\n", stderr: "")
      }
      if command.contains("base64 -D | sudo tee") || command.contains("launchctl bootstrap system")
      {
        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
      }
      if command.contains("DONE") && command.contains("---LOG_TAIL---") {
        return ProcessResult(
          exitCode: 0,
          stdout: """
            RUNNING
            ---LOG_TAIL---
            Downloading: Command Line Tools for Xcode
            """,
          stderr: ""
        )
      }
      return ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    let baseDate = Date(timeIntervalSince1970: 1_000_000)
    let clock = MutableClock(initial: baseDate)
    var threw = false
    do {
      _ = try await SharedCompassVMDevToolsProvisioner.provision(
        runner: runner,
        progress: { _ in },
        now: { clock.now() },
        // 10 minutes per "sleep" — past the 15-min timeout in 2 ticks.
        sleep: { _ in clock.advance(by: 10 * 60) }
      )
    } catch let error as SharedCompassVMDevToolsProvisioner.ProvisionError {
      threw = true
      guard case .installTimedOut(let phase, let tail) = error else {
        #require(false, "Expected .installTimedOut, got \(error)")
        return
      }
      #require(phase == .downloading)
      #require(tail.contains("Downloading"))
    } catch {
      #require(false, "Unexpected error type: \(error)")
    }
    #require(threw, "Expected installTimedOut")
  }

  @Test
  func testProvisionThrowsOnFinaliseFailure() async {
    let runner = FakeBashRunner()
    runner.responder = { command, _ in
      // Probe says missing the first time.
      if command.contains("PRESENT") || command.contains("MISSING") {
        if runner.callCount == 1 {
          return ProcessResult(exitCode: 0, stdout: "MISSING\n", stderr: "")
        }
        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
      }
      if command.contains("base64 -D | sudo tee") || command.contains("launchctl bootstrap system")
      {
        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
      }
      if command.contains("DONE") && command.contains("---LOG_TAIL---") {
        return ProcessResult(
          exitCode: 0,
          stdout: """
            DONE
            exit=0
            ---LOG_TAIL---
            Done.
            """,
          stderr: ""
        )
      }
      // Finalise — sudo xcode-select -s ; test -x ; xcode-select -p
      // We return nonzero here to simulate the freshly-installed
      // toolchain not actually being usable.
      if command.contains("sudo xcode-select -s") {
        return ProcessResult(
          exitCode: 1, stdout: "", stderr: "xcode-select: no developer dir found")
      }
      return ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
    var threw = false
    do {
      _ = try await SharedCompassVMDevToolsProvisioner.provision(
        runner: runner,
        progress: { _ in },
        now: { Date() },
        sleep: { _ in }
      )
    } catch let error as SharedCompassVMDevToolsProvisioner.ProvisionError {
      threw = true
      guard case .finaliseFailed(let stderr) = error else {
        #require(false, "Expected .finaliseFailed, got \(error)")
        return
      }
      #require(stderr.contains("no developer dir found"))
    } catch {
      #require(false, "Unexpected error type: \(error)")
    }
    #require(threw, "Expected finaliseFailed")
  }
}

// MARK: - Test doubles

/// In-memory `AgentBashRunner` whose responses are driven by a closure.
/// Used by the provisioner tests so the full flow runs without touching
/// a real VM or any subprocess.
private final class FakeBashRunner: AgentBashRunner, @unchecked Sendable {
  var responder: (@Sendable (_ command: String, _ workingDirectory: URL) -> ProcessResult)?
  private(set) var callCount: Int = 0
  private(set) var commands: [String] = []

  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    callCount += 1
    commands.append(command)
    guard let responder else {
      return ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
    return responder(command, workingDirectory)
  }
}

/// Manually-advanceable clock so timeout tests don't depend on real
/// wall-clock time.
private final class MutableClock: @unchecked Sendable {
  private var current: Date

  init(initial: Date) { self.current = initial }

  func now() -> Date { current }

  func advance(by seconds: TimeInterval) {
    current = current.addingTimeInterval(seconds)
  }
}
