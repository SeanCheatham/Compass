import Foundation
@testable import Compass
import XCTest

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
final class SharedCompassVMDevToolsProvisionerTests: XCTestCase {

    // MARK: - Rendered install script

    func testRenderedInstallScriptStartsWithBashShebang() {
        let script = SharedCompassVMDevToolsProvisioner.renderInstallScript()
        XCTAssertTrue(script.hasPrefix("#!/bin/bash"))
    }

    func testRenderedInstallScriptTouchesAppleSoftwareupdateSentinel() {
        let script = SharedCompassVMDevToolsProvisioner.renderInstallScript()
        // The well-known sentinel softwareupdate looks for to expose CLT
        // in its catalog without a GUI session. Bytes pinned because Apple
        // sometimes changes the path across majors — diverging silently
        // would break headless install on the new major with no error.
        XCTAssertTrue(
            script.contains("touch \"$SENTINEL\""),
            "Script must touch the softwareupdate CLT request sentinel"
        )
        XCTAssertTrue(
            script.contains("/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"),
            "Script must reference Apple's documented CLT-install sentinel path"
        )
    }

    func testRenderedInstallScriptPicksLatestCLTLabel() {
        let script = SharedCompassVMDevToolsProvisioner.renderInstallScript()
        // Pick by `tail -n1` of the catalog entries whose lines start
        // with `* Label: Command Line Tools`. Apple sometimes ships
        // multiple labels (different Xcode majors); newest one wins.
        // The `^\* Label:` anchor matters — on macOS 26+ each Label
        // entry is followed by an indented `Title: Command Line Tools …`
        // line that the older un-anchored matcher would also pick up
        // (producing an empty label string and breaking install).
        XCTAssertTrue(script.contains("softwareupdate -l"))
        XCTAssertTrue(
            script.contains("'^\\* Label: Command Line Tools'"),
            "Label selector must anchor on the '* Label:' line, not match any 'Command Line Tools' substring"
        )
        XCTAssertTrue(script.contains("tail -n1"))
    }

    func testRenderedInstallScriptInvokesSoftwareupdateVerbose() {
        let script = SharedCompassVMDevToolsProvisioner.renderInstallScript()
        XCTAssertTrue(
            script.contains("softwareupdate -i \"$LABEL\" --verbose"),
            "Must use --verbose so the host can parse progress phases out of the log"
        )
    }

    func testRenderedInstallScriptActivatesCLTAfterSuccess() {
        let script = SharedCompassVMDevToolsProvisioner.renderInstallScript()
        XCTAssertTrue(
            script.contains("xcode-select -s /Library/Developer/CommandLineTools"),
            "Successful install must promote CLT to active developer dir so subsequent calls (swift, clang) work without xcode-select"
        )
    }

    func testRenderedInstallScriptWritesDoneSentinelInAllExitPaths() {
        let script = SharedCompassVMDevToolsProvisioner.renderInstallScript()
        // Two exit paths: missing label (rc=2) and softwareupdate completion
        // (rc=whatever). Both must touch the done-sentinel or the host's
        // pollUntilDone loop will hang to the timeout.
        XCTAssertTrue(script.contains("echo \"exit=2\" > \"$DONE_PATH\""))
        XCTAssertTrue(script.contains("echo \"exit=$rc\" > \"$DONE_PATH\""))
    }

    func testRenderedInstallScriptRemovesSentinelOnAllExitPaths() {
        let script = SharedCompassVMDevToolsProvisioner.renderInstallScript()
        // Both early-exit (missing label) and the post-install path must
        // remove the in-progress sentinel; leaving it behind on the guest
        // would confuse future softwareupdate calls (some Apple tooling
        // refuses to re-list CLT when the sentinel is stuck).
        let occurrences = script.components(separatedBy: "rm -f \"$SENTINEL\"").count - 1
        XCTAssertGreaterThanOrEqual(occurrences, 2, "Sentinel must be cleared on both exit paths")
    }

    // MARK: - LaunchDaemon plist

    func testRenderedLaunchDaemonPlistIsValid() throws {
        let plist = SharedCompassVMDevToolsProvisioner.renderInstallLaunchDaemonPlist()
        let parsed = try PropertyListSerialization.propertyList(
            from: Data(plist.utf8),
            options: [],
            format: nil
        ) as? [String: Any]
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?["Label"] as? String, "com.seancheatham.Compass.devtools-install")
        XCTAssertEqual(parsed?["RunAtLoad"] as? Bool, true)
        // KeepAlive must be false so the script runs once and exits;
        // KeepAlive=true would have launchd restart softwareupdate after
        // it succeeds, looping forever.
        XCTAssertEqual(parsed?["KeepAlive"] as? Bool, false)
        XCTAssertEqual(parsed?["LaunchOnlyOnce"] as? Bool, true)
        let args = parsed?["ProgramArguments"] as? [String]
        XCTAssertEqual(args, ["/usr/local/libexec/compass-install-clt.sh"])
    }

    // MARK: - Phase parsing

    func testParsePhaseFromLogTailRecognisesScriptStart() {
        let tail = "[compass-clt] 2026-05-21T17:00:00Z starting"
        XCTAssertEqual(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail), .scriptRunning)
    }

    func testParsePhaseFromLogTailRecognisesDownloading() {
        let tail = """
        [compass-clt] selected label: Command Line Tools for Xcode-15.2
        Downloading: Command Line Tools for Xcode
        """
        XCTAssertEqual(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail), .downloading)
    }

    func testParsePhaseFromLogTailRecognisesDownloadingMacOS26Form() {
        // macOS 26's softwareupdate --verbose drops the trailing colon
        // we used to key on. Confirmed live against a Sequoia successor
        // guest: "Downloading Command Line Tools for Xcode 26.5".
        let tail = "Downloading Command Line Tools for Xcode 26.5"
        XCTAssertEqual(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail), .downloading)
    }

    func testParsePhaseFromLogTailRecognisesDownloaded() {
        let tail = "Downloaded: Command Line Tools for Xcode"
        XCTAssertEqual(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail), .downloaded)
    }

    func testParsePhaseFromLogTailRecognisesDownloadedMacOS26Form() {
        let tail = "Downloaded Command Line Tools for Xcode 26.5"
        XCTAssertEqual(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail), .downloaded)
    }

    func testParsePhaseFromLogTailRecognisesInstalling() {
        let tail = "Installing: Command Line Tools for Xcode"
        XCTAssertEqual(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail), .installing)
    }

    func testParsePhaseFromLogTailRecognisesInstallingMacOS26Form() {
        let tail = "Installing Command Line Tools for Xcode 26.5"
        XCTAssertEqual(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail), .installing)
    }

    func testParsePhaseFromLogTailRecognisesInstalled() {
        let tail = "Installed: Command Line Tools for Xcode"
        XCTAssertEqual(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail), .installed)
    }

    func testParsePhaseFromLogTailRecognisesInstalledMacOS26Form() {
        let tail = "Installed Command Line Tools for Xcode 26.5"
        XCTAssertEqual(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail), .installed)
    }

    func testParsePhaseFromLogTailRecognisesDone() {
        let tail = """
        Installed: Command Line Tools for Xcode
        Done.
        [compass-clt] softwareupdate exit=0
        """
        XCTAssertEqual(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: tail), .done)
    }

    func testParsePhaseFromLogTailReturnsNilForNoise() {
        XCTAssertNil(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: ""))
        XCTAssertNil(SharedCompassVMDevToolsProvisioner.parsePhase(fromLogTail: "no markers here"))
    }

    func testFractionForPhaseIsMonotone() {
        let order: [SharedCompassVMDevToolsProvisioner.InstallPhase] = [
            .kickoff, .scriptRunning, .downloading, .downloaded, .installing, .installed, .done
        ]
        let fractions = order.map(SharedCompassVMDevToolsProvisioner.fractionForPhase)
        for i in 1..<fractions.count {
            XCTAssertGreaterThan(
                fractions[i], fractions[i - 1],
                "Fraction for \(order[i]) must be strictly greater than for \(order[i - 1])"
            )
        }
        XCTAssertEqual(fractions.last, 1.0)
    }

    // MARK: - Poll snapshot parsing

    func testPollSnapshotParsesRunningWhenSentinelAbsent() {
        let raw = """
        RUNNING
        ---LOG_TAIL---
        Downloading: Command Line Tools for Xcode
        """
        let snapshot = SharedCompassVMDevToolsProvisioner.PollSnapshot(parsing: raw)
        XCTAssertNil(snapshot.exitCode)
        XCTAssertTrue(snapshot.logTail.contains("Downloading"))
    }

    func testPollSnapshotParsesSuccessExit() {
        let raw = """
        DONE
        exit=0
        ---LOG_TAIL---
        Done.
        """
        let snapshot = SharedCompassVMDevToolsProvisioner.PollSnapshot(parsing: raw)
        XCTAssertEqual(snapshot.exitCode, 0)
        XCTAssertTrue(snapshot.logTail.contains("Done."))
    }

    func testPollSnapshotParsesFailureExit() {
        let raw = """
        DONE
        exit=2
        ---LOG_TAIL---
        ERROR: no Command Line Tools label found
        """
        let snapshot = SharedCompassVMDevToolsProvisioner.PollSnapshot(parsing: raw)
        XCTAssertEqual(snapshot.exitCode, 2)
    }

    func testPollSnapshotTreatsMissingExitLineAsFailure() {
        // Defensive: if the cat-of-sentinel got truncated, we must NOT
        // hang waiting for a clean exit code — treat as failure so the
        // caller surfaces the issue.
        let raw = """
        DONE
        ---LOG_TAIL---
        """
        let snapshot = SharedCompassVMDevToolsProvisioner.PollSnapshot(parsing: raw)
        XCTAssertEqual(snapshot.exitCode, -1)
    }

    // MARK: - Full provisioner flow with a fake runner

    func testProvisionShortCircuitsWhenCLTAlreadyInstalled() async throws {
        let runner = FakeBashRunner()
        runner.responder = { command, _ in
            if command.contains("PRESENT") || command.contains("MISSING") {
                return ProcessResult(exitCode: 0, stdout: "PRESENT\n", stderr: "")
            }
            XCTFail("Provisioner should short-circuit before any other RPC. Got: \(command)")
            return ProcessResult(exitCode: 1, stdout: "", stderr: "unexpected")
        }
        var progressUpdates: [Double] = []
        let report = try await SharedCompassVMDevToolsProvisioner.provision(
            runner: runner,
            progress: { progressUpdates.append($0) }
        )
        XCTAssertTrue(report.alreadyInstalled)
        XCTAssertEqual(runner.callCount, 1)
        XCTAssertEqual(progressUpdates.first, 0)
        XCTAssertEqual(progressUpdates.last, 1)
    }

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
                return ProcessResult(exitCode: 0, stdout: "/Library/Developer/CommandLineTools\n", stderr: "")
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
                return ProcessResult(exitCode: 0, stdout: "/Library/Developer/CommandLineTools\n", stderr: "")
            }
            XCTFail("Unexpected RPC: \(command)")
            return ProcessResult(exitCode: 1, stdout: "", stderr: "unexpected")
        }

        var progressUpdates: [Double] = []
        let report = try await SharedCompassVMDevToolsProvisioner.provision(
            runner: runner,
            progress: { progressUpdates.append($0) },
            now: { Date() },
            sleep: { _ in } // Drive the poll loop without real waits.
        )

        XCTAssertFalse(report.alreadyInstalled)
        XCTAssertGreaterThanOrEqual(pollCount, 3)
        XCTAssertEqual(progressUpdates.first, 0)
        XCTAssertEqual(progressUpdates.last, 1)
        // Monotone — once we've seen a higher fraction we must never go
        // back. UI would otherwise flicker backwards.
        for i in 1..<progressUpdates.count {
            XCTAssertGreaterThanOrEqual(progressUpdates[i], progressUpdates[i - 1])
        }
    }

    func testProvisionThrowsOnInstallFailure() async {
        let runner = FakeBashRunner()
        runner.responder = { command, _ in
            if command.contains("PRESENT") || command.contains("MISSING") {
                return ProcessResult(exitCode: 0, stdout: "MISSING\n", stderr: "")
            }
            if command.contains("base64 -D | sudo tee") || command.contains("launchctl bootstrap system") {
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
        do {
            _ = try await SharedCompassVMDevToolsProvisioner.provision(
                runner: runner,
                progress: { _ in },
                now: { Date() },
                sleep: { _ in }
            )
            XCTFail("Expected installFailed")
        } catch let error as SharedCompassVMDevToolsProvisioner.ProvisionError {
            guard case let .installFailed(code, tail) = error else {
                XCTFail("Expected .installFailed, got \(error)")
                return
            }
            XCTAssertEqual(code, 2)
            XCTAssertTrue(tail.contains("no Command Line Tools label"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

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
            if command.contains("base64 -D | sudo tee") || command.contains("launchctl bootstrap system") {
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
        do {
            _ = try await SharedCompassVMDevToolsProvisioner.provision(
                runner: runner,
                progress: { _ in },
                now: { clock.now() },
                sleep: { _ in clock.advance(by: 10 * 60) } // 10 minutes per "sleep" — past the 15-min timeout in 2 ticks
            )
            XCTFail("Expected installTimedOut")
        } catch let error as SharedCompassVMDevToolsProvisioner.ProvisionError {
            guard case let .installTimedOut(phase, tail) = error else {
                XCTFail("Expected .installTimedOut, got \(error)")
                return
            }
            XCTAssertEqual(phase, .downloading)
            XCTAssertTrue(tail.contains("Downloading"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

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
            if command.contains("base64 -D | sudo tee") || command.contains("launchctl bootstrap system") {
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
                return ProcessResult(exitCode: 1, stdout: "", stderr: "xcode-select: no developer dir found")
            }
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        do {
            _ = try await SharedCompassVMDevToolsProvisioner.provision(
                runner: runner,
                progress: { _ in },
                now: { Date() },
                sleep: { _ in }
            )
            XCTFail("Expected finaliseFailed")
        } catch let error as SharedCompassVMDevToolsProvisioner.ProvisionError {
            guard case let .finaliseFailed(stderr) = error else {
                XCTFail("Expected .finaliseFailed, got \(error)")
                return
            }
            XCTAssertTrue(stderr.contains("no developer dir found"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
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
