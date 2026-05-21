import Foundation

/// Host-driven dev-tools provisioning for the Compass shared VM guest.
///
/// Runs after `SharedCompassVMHeadlessFirstBoot` has brought sshd and the
/// vsock guest agent online. Probes the guest for Xcode Command Line Tools
/// and, if absent, drives a headless `softwareupdate -i` install via the
/// existing bash RPC. Surfaces phase-coarse progress back to the host so
/// the readiness state machine can show the user what's happening during
/// the ~5-minute install.
///
/// The actual `softwareupdate` run executes detached inside the guest so a
/// long-running install does not tie up an RPC connection (the bash RPC
/// has a per-call timeout, and a 5-minute single call would be brittle).
/// The host kicks off a planted script under `nohup`, then polls a sentinel
/// file and tails the install log until exit.
///
/// Everything in this file is pure-ish: the only side effects are bash
/// RPCs issued through an injected `AgentBashRunner`. That makes the whole
/// flow testable with a fake runner — `Phase 4` exercises it without
/// touching a real VM.
enum SharedCompassVMDevToolsProvisioner {
    /// Guest-side path the install script is planted to.
    static let scriptGuestPath = "/usr/local/libexec/compass-install-clt.sh"

    /// Guest-side log the install script tees its output into. The host
    /// tails this to surface progress and to capture the tail in error
    /// messages when the install fails.
    static let logGuestPath = "/var/log/compass-clt-install.log"

    /// Sentinel file the install script writes when it finishes. Contents
    /// are a single `exit=<code>` line; presence signals "done", regardless
    /// of success.
    static let doneSentinelGuestPath = "/var/log/compass-clt-install.done"

    /// Canonical CLT toolchain location. `xcode-select` points here once
    /// install completes; the provisioner re-checks this path for the
    /// "already installed" short-circuit.
    static let cltSwiftPath = "/Library/Developer/CommandLineTools/usr/bin/swift"

    /// The well-known sentinel `softwareupdate` looks for to expose CLT
    /// in its catalog without a GUI session. Created by the install script
    /// before listing the catalog; removed after the install attempt.
    static let installRequestSentinelPath = "/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"

    /// LaunchDaemon plist that wraps the install script. Plant + bootstrap
    /// runs the script entirely detached from the bash RPC's lifecycle.
    /// We tried backgrounding the script with `nohup … & disown` from
    /// `/bin/zsh -lc` instead, but that path is unreliable when the parent
    /// shell is spawned via `Foundation.Process()` from a LaunchDaemon
    /// (the in-guest agent) — verified live: identical command runs fine
    /// from ssh, never starts the child from Process(). Using launchctl
    /// sidesteps the entire shell/job-control surface.
    static let installLaunchDaemonLabel = "com.seancheatham.Compass.devtools-install"
    static let installLaunchDaemonPlistGuestPath = "/Library/LaunchDaemons/com.seancheatham.Compass.devtools-install.plist"

    /// Per-call bash RPC timeout for the fast steps (probe, plant, kickoff,
    /// finalise). Long enough to survive a momentary RPC stall, short
    /// enough that a wedged guest surfaces quickly.
    static let shortStepTimeoutSeconds: TimeInterval = 30

    /// Seconds between successive poll RPCs while the install runs. Long
    /// enough that we don't hammer the guest agent during a quiet
    /// download; short enough that progress updates feel responsive.
    static let pollIntervalSeconds: Double = 5

    /// Maximum wall-clock seconds the install may take before the
    /// provisioner gives up. CLT downloads ~700 MiB and runs an installer
    /// pkg; 15 minutes covers the slow tail on a constrained host
    /// without leaving the UI stuck forever on a truly broken guest.
    static let totalInstallTimeoutSeconds: TimeInterval = 15 * 60

    // MARK: - Errors

    enum ProvisionError: Error, CustomStringConvertible, Equatable {
        case probeFailed(stderr: String)
        case scriptPlantFailed(stderr: String)
        case kickoffFailed(stderr: String)
        case installTimedOut(lastPhase: InstallPhase, logTail: String)
        case installFailed(exitCode: Int32, logTail: String)
        case finaliseFailed(stderr: String)

        var description: String {
            switch self {
            case .probeFailed(let s):
                return "CLT probe failed: \(s)"
            case .scriptPlantFailed(let s):
                return "Failed to plant CLT install script in guest: \(s)"
            case .kickoffFailed(let s):
                return "Failed to launch CLT install in guest: \(s)"
            case .installTimedOut(let phase, let tail):
                return "CLT install timed out at phase \(phase). Last log tail: \(tail)"
            case .installFailed(let code, let tail):
                return "CLT install exited \(code). Last log tail: \(tail)"
            case .finaliseFailed(let s):
                return "CLT install completed but post-install verification failed: \(s)"
            }
        }
    }

    /// Coarse phase the install passes through. Used both as a progress
    /// signal (`fractionForPhase`) and as a diagnostic label on timeout.
    enum InstallPhase: String, Equatable {
        case kickoff
        case scriptRunning
        case downloading
        case downloaded
        case installing
        case installed
        case done
    }

    struct ProvisionReport: Equatable {
        var alreadyInstalled: Bool
        var logTail: String
    }

    // MARK: - Driver

    /// Runs the full probe → install → poll → finalise flow.
    /// `progress` is invoked with monotone-ish fractions in [0, 1] as the
    /// install advances through its phases.
    static func provision(
        runner: any AgentBashRunner,
        progress: (Double) async -> Void,
        now: @Sendable () -> Date = { Date() },
        sleep: @Sendable (UInt64) async -> Void = { ns in try? await Task.sleep(nanoseconds: ns) }
    ) async throws -> ProvisionReport {
        await progress(0)

        if try await probeAlreadyInstalled(runner: runner) {
            await progress(1)
            return ProvisionReport(alreadyInstalled: true, logTail: "")
        }

        try await plantInstallScript(runner: runner)
        try await kickOffInstall(runner: runner)
        await progress(fractionForPhase(.scriptRunning))

        let report = try await pollUntilDone(
            runner: runner,
            progress: progress,
            now: now,
            sleep: sleep
        )

        try await finalise(runner: runner)
        await progress(1)
        return report
    }

    // MARK: - Steps

    /// Returns true when CLT looks usable in the guest already. Short-circuits
    /// the rest of the flow so a re-provision (or a re-run after the host
    /// crashed mid-install) doesn't re-download. Tolerant of either probe
    /// failing — if `xcode-select` is wedged but the swift binary exists we
    /// still try, and vice-versa.
    static func probeAlreadyInstalled(runner: any AgentBashRunner) async throws -> Bool {
        let result: ProcessResult
        do {
            result = try await runner.run(
                command: """
                set -uo pipefail
                if [ -x \(cltSwiftPath) ] && xcode-select -p >/dev/null 2>&1; then
                  echo PRESENT
                else
                  echo MISSING
                fi
                """,
                workingDirectory: URL(fileURLWithPath: "/"),
                timeout: shortStepTimeoutSeconds
            )
        } catch {
            throw ProvisionError.probeFailed(stderr: "\(error)")
        }
        if result.exitCode != 0 {
            throw ProvisionError.probeFailed(stderr: result.stderr)
        }
        return result.stdout.contains("PRESENT")
    }

    /// Writes the install script + LaunchDaemon plist to their guest-side
    /// locations with the correct permissions. Uses base64 so both
    /// payloads can contain arbitrary metacharacters without any escaping
    /// risk on the bash RPC's `-c` boundary.
    ///
    /// Also explicitly `launchctl bootout`s any previous instance of the
    /// daemon — `bootstrap` rejects a label that is already loaded with
    /// a `Bootstrap failed: 37: The specified service did not pass
    /// validation` error, which would otherwise stall reruns after a
    /// partial install.
    static func plantInstallScript(runner: any AgentBashRunner) async throws {
        let scriptEncoded = Data(renderInstallScript().utf8).base64EncodedString()
        let plistEncoded = Data(renderInstallLaunchDaemonPlist().utf8).base64EncodedString()
        let command = """
        set -euo pipefail
        echo \(scriptEncoded) | base64 -D | sudo tee \(scriptGuestPath) > /dev/null
        sudo chmod 0755 \(scriptGuestPath)
        sudo chown root:wheel \(scriptGuestPath)
        echo \(plistEncoded) | base64 -D | sudo tee \(installLaunchDaemonPlistGuestPath) > /dev/null
        sudo chmod 0644 \(installLaunchDaemonPlistGuestPath)
        sudo chown root:wheel \(installLaunchDaemonPlistGuestPath)
        sudo rm -f \(doneSentinelGuestPath) \(logGuestPath)
        sudo launchctl bootout system \(installLaunchDaemonPlistGuestPath) 2>/dev/null || true
        """
        let result: ProcessResult
        do {
            result = try await runner.run(
                command: command,
                workingDirectory: URL(fileURLWithPath: "/"),
                timeout: shortStepTimeoutSeconds
            )
        } catch {
            throw ProvisionError.scriptPlantFailed(stderr: "\(error)")
        }
        if result.exitCode != 0 {
            throw ProvisionError.scriptPlantFailed(stderr: result.stderr)
        }
    }

    /// Bootstraps the install LaunchDaemon. launchd takes ownership of
    /// the script's lifecycle from here — the bash RPC returns as soon
    /// as launchctl confirms the load. The script then runs entirely
    /// independently of any subsequent RPC, ssh session, or host
    /// process state.
    static func kickOffInstall(runner: any AgentBashRunner) async throws {
        let result: ProcessResult
        do {
            result = try await runner.run(
                command: """
                set -euo pipefail
                sudo launchctl bootstrap system \(installLaunchDaemonPlistGuestPath)
                """,
                workingDirectory: URL(fileURLWithPath: "/"),
                timeout: shortStepTimeoutSeconds
            )
        } catch {
            throw ProvisionError.kickoffFailed(stderr: "\(error)")
        }
        if result.exitCode != 0 {
            throw ProvisionError.kickoffFailed(stderr: result.stderr)
        }
    }

    /// Polls until either the install script writes its done-sentinel or
    /// the overall timeout elapses. Surfaces phase-coarse progress along
    /// the way by parsing the install log tail.
    static func pollUntilDone(
        runner: any AgentBashRunner,
        progress: (Double) async -> Void,
        now: @Sendable () -> Date,
        sleep: @Sendable (UInt64) async -> Void
    ) async throws -> ProvisionReport {
        let deadline = now().addingTimeInterval(totalInstallTimeoutSeconds)
        var lastPhase: InstallPhase = .scriptRunning

        while now() < deadline {
            await sleep(UInt64(pollIntervalSeconds * 1_000_000_000))

            let snapshot = try await pollOnce(runner: runner)
            let phase = parsePhase(fromLogTail: snapshot.logTail) ?? lastPhase
            if phase != lastPhase {
                lastPhase = phase
                await progress(fractionForPhase(phase))
            }
            if let exitCode = snapshot.exitCode {
                if exitCode == 0 {
                    return ProvisionReport(alreadyInstalled: false, logTail: snapshot.logTail)
                }
                throw ProvisionError.installFailed(exitCode: exitCode, logTail: snapshot.logTail)
            }
        }

        let finalSnapshot = try await pollOnce(runner: runner)
        throw ProvisionError.installTimedOut(lastPhase: lastPhase, logTail: finalSnapshot.logTail)
    }

    /// Reads the current log tail and looks for the done-sentinel in one
    /// RPC. Combines both into a single bash invocation so polling cost
    /// is one round-trip per interval.
    static func pollOnce(runner: any AgentBashRunner) async throws -> PollSnapshot {
        let result: ProcessResult
        do {
            result = try await runner.run(
                command: """
                set -uo pipefail
                if [ -f \(doneSentinelGuestPath) ]; then
                  echo DONE
                  cat \(doneSentinelGuestPath)
                else
                  echo RUNNING
                fi
                echo ---LOG_TAIL---
                if [ -f \(logGuestPath) ]; then
                  tail -n 40 \(logGuestPath) 2>/dev/null || true
                fi
                """,
                workingDirectory: URL(fileURLWithPath: "/"),
                timeout: shortStepTimeoutSeconds
            )
        } catch {
            throw ProvisionError.probeFailed(stderr: "\(error)")
        }
        return PollSnapshot(parsing: result.stdout)
    }

    /// Sets the freshly-installed CLT as the active developer directory,
    /// re-runs the probe to confirm the install actually produced a
    /// usable toolchain, and tears down the install LaunchDaemon so a
    /// reboot doesn't try to re-run it. The script also runs
    /// `xcode-select -s` but does not have a way to fail the install if
    /// the switch silently no-ops, so we verify here.
    static func finalise(runner: any AgentBashRunner) async throws {
        let result: ProcessResult
        do {
            result = try await runner.run(
                command: """
                set -euo pipefail
                sudo xcode-select -s /Library/Developer/CommandLineTools
                test -x \(cltSwiftPath)
                xcode-select -p
                sudo launchctl bootout system \(installLaunchDaemonPlistGuestPath) 2>/dev/null || true
                sudo rm -f \(installLaunchDaemonPlistGuestPath)
                """,
                workingDirectory: URL(fileURLWithPath: "/"),
                timeout: shortStepTimeoutSeconds
            )
        } catch {
            throw ProvisionError.finaliseFailed(stderr: "\(error)")
        }
        if result.exitCode != 0 {
            throw ProvisionError.finaliseFailed(stderr: result.stderr)
        }
    }

    // MARK: - Pure helpers

    /// Parse output produced by `pollOnce`. Pure so unit tests can lock
    /// down the wire-to-state mapping without running anything.
    struct PollSnapshot: Equatable {
        var exitCode: Int32?
        var logTail: String

        init(parsing raw: String) {
            let separator = "---LOG_TAIL---"
            let parts = raw.components(separatedBy: separator)
            let head = (parts.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let tail: String
            if parts.count > 1 {
                tail = parts.dropFirst().joined(separator: separator)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                tail = ""
            }
            if head.hasPrefix("DONE") {
                // After the DONE line, the script prints `cat done_sentinel`
                // which is a single `exit=<n>` line.
                let lines = head.split(separator: "\n").map(String.init)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if let value = trimmed.split(separator: "=").last, trimmed.hasPrefix("exit=") {
                        self.exitCode = Int32(value) ?? -1
                    }
                }
                // Edge: DONE present but exit= line absent (truncated read).
                // Treat as failure-with-unknown-code so the caller doesn't
                // hang waiting for a clean exit that already happened.
                if self.exitCode == nil {
                    self.exitCode = -1
                }
            } else {
                self.exitCode = nil
            }
            self.logTail = tail
        }

        init(exitCode: Int32?, logTail: String) {
            self.exitCode = exitCode
            self.logTail = logTail
        }
    }

    /// Translate the last meaningful line of the install log to a coarse
    /// install phase. Returns nil when nothing in the tail looks like a
    /// known marker — the caller keeps whatever phase it last saw.
    ///
    /// `softwareupdate --verbose` output drifted between macOS majors:
    ///   * macOS 15 and earlier: `Downloading:`, `Downloaded:`, `Installing:` (with colons)
    ///   * macOS 26+: `Downloading Command Line Tools …` (no colons)
    /// We match both shapes so the UI doesn't get stuck at the previous
    /// phase forever on a healthy install.
    static func parsePhase(fromLogTail tail: String) -> InstallPhase? {
        let lower = tail.lowercased()
        // Check most-advanced markers first so a late "Downloaded" doesn't
        // override a later "Installed".
        if lower.contains("done.") || lower.contains("install complete") || lower.contains("[compass-clt] softwareupdate exit=0") {
            return .done
        }
        if lower.contains("installed:") || lower.contains("installed cli") || lower.contains("installed command line tools") {
            return .installed
        }
        if lower.contains("installing:") || lower.contains("running pre-install") || lower.contains("running install") || lower.contains("installing command line tools") {
            return .installing
        }
        if lower.contains("downloaded:") || lower.contains("downloaded command line tools") {
            return .downloaded
        }
        if lower.contains("downloading:") || lower.contains("download started") || lower.contains("downloading command line tools") {
            return .downloading
        }
        if lower.contains("[compass-clt]") &&
            (lower.contains(" starting") || lower.contains("selected label")) {
            return .scriptRunning
        }
        return nil
    }

    static func fractionForPhase(_ phase: InstallPhase) -> Double {
        switch phase {
        case .kickoff: return 0.02
        case .scriptRunning: return 0.10
        case .downloading: return 0.30
        case .downloaded: return 0.65
        case .installing: return 0.80
        case .installed: return 0.95
        case .done: return 1.0
        }
    }

    /// LaunchDaemon plist that wraps the install script. `LaunchOnlyOnce`
    /// + `KeepAlive=false` so a one-shot run is exactly what we get; the
    /// daemon stays loaded (in a `not running` state) after the script
    /// exits, ready for `finalise` to bootout. Stdout/stderr land in the
    /// install log alongside whatever the script `exec >`s, so a launchd
    /// crash before the script's own redirect still leaves diagnostics.
    static func renderInstallLaunchDaemonPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTD/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(installLaunchDaemonLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(scriptGuestPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>LaunchOnlyOnce</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(logGuestPath)</string>
            <key>StandardErrorPath</key>
            <string>\(logGuestPath)</string>
        </dict>
        </plist>
        """
    }

    /// The bash script planted onto the guest. Public so phase-4 tests can
    /// lock down its bytes — Apple has historically changed `softwareupdate`
    /// behaviour across major macOS releases, and a silent regression would
    /// break the entire dev-tools provisioning flow.
    static func renderInstallScript() -> String {
        """
        #!/bin/bash
        # Compass Xcode Command Line Tools installer.
        # Planted by SharedCompassVMDevToolsProvisioner over vsock and invoked
        # under sudo nohup from the host. Idempotent — if CLT is already
        # installed, softwareupdate just no-ops.
        set -uo pipefail
        umask 022

        LOG_PATH="\(logGuestPath)"
        DONE_PATH="\(doneSentinelGuestPath)"
        SENTINEL="\(installRequestSentinelPath)"

        exec > "$LOG_PATH" 2>&1
        echo "[compass-clt] $(date -u '+%Y-%m-%dT%H:%M:%SZ') starting"

        # softwareupdate hides CLT from its catalog unless this magic file
        # exists. The path is an Apple implementation detail but has been
        # stable since at least macOS Mojave; it's the documented headless
        # workaround in every shell-provisioning tool that targets macOS.
        touch "$SENTINEL"

        # Pick the most recently-published CLT label. Apple sometimes ships
        # multiple labels (different Xcode majors); `tail -n1` picks the
        # newest one in the catalog ordering.
        #
        # Filter on the literal `* Label:` prefix so we don't accidentally
        # match the indented `Title: Command Line Tools …` line that follows
        # each Label entry on macOS 26+ (which would split to an empty
        # field under the original awk-on-"Label: " approach).
        LABEL="$(softwareupdate -l 2>&1 \
            | grep -E '^\\* Label: Command Line Tools' \
            | sed 's/^\\* Label: //' \
            | tail -n1 \
            | sed 's/[[:space:]]*$//')"
        if [ -z "$LABEL" ]; then
          echo "[compass-clt] ERROR: no Command Line Tools label found in softwareupdate catalog"
          softwareupdate -l 2>&1 || true
          rm -f "$SENTINEL"
          echo "exit=2" > "$DONE_PATH"
          exit 2
        fi
        echo "[compass-clt] selected label: $LABEL"

        softwareupdate -i "$LABEL" --verbose
        rc=$?
        echo "[compass-clt] softwareupdate exit=$rc"

        rm -f "$SENTINEL"

        if [ "$rc" -eq 0 ]; then
          # Activate the freshly-installed toolchain. Safe to retry — the
          # command is idempotent and silently no-ops on the second run.
          xcode-select -s /Library/Developer/CommandLineTools 2>&1 || true
        fi

        echo "exit=$rc" > "$DONE_PATH"
        exit "$rc"
        """
    }
}
