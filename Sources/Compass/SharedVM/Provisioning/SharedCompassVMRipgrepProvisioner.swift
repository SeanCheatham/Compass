import Foundation

/// Host-driven ripgrep provisioning for the Compass shared VM guest.
///
/// Runs after `SharedCompassVMDevToolsProvisioner` has brought Command Line
/// Tools online. Bootstraps Homebrew under the compass user (if not already
/// present) and installs `ripgrep`, symlinked to `/usr/local/bin/rg` so it
/// picks up via the existing path_helper-driven `~/.zshenv`. Agent searches
/// inside the guest use `rg` because naive `grep -r` walks the SPM `.build`
/// tree and times out.
enum SharedCompassVMRipgrepProvisioner {
  static let ripgrepInstallPath = "/usr/local/bin/rg"
  static let brewRipgrepPath = "/opt/homebrew/bin/rg"
  static let brewInstallPath = "/opt/homebrew/bin/brew"
  static let scriptGuestPath = "/usr/local/libexec/compass-install-rg.sh"
  static let logGuestPath = "/var/log/compass-rg-install.log"
  static let doneSentinelGuestPath = "/var/log/compass-rg-install.done"
  static let installLaunchDaemonLabel = "com.seancheatham.Compass.rg-install"
  static let installLaunchDaemonPlistGuestPath =
    "/Library/LaunchDaemons/com.seancheatham.Compass.rg-install.plist"

  static let shortStepTimeoutSeconds: TimeInterval = 30
  static let pollIntervalSeconds: Double = 5
  static let totalInstallTimeoutSeconds: TimeInterval = 15 * 60

  enum ProvisionError: Error, CustomStringConvertible, Equatable {
    case probeFailed(stderr: String)
    case scriptPlantFailed(stderr: String)
    case kickoffFailed(stderr: String)
    case installTimedOut(lastPhase: InstallPhase, logTail: String)
    case installFailed(exitCode: Int32, logTail: String)
    case finaliseFailed(stderr: String)

    var description: String {
      switch self {
      case .probeFailed(let stderr):
        return "Ripgrep probe failed: \(stderr)"
      case .scriptPlantFailed(let stderr):
        return "Failed to plant ripgrep install script in guest: \(stderr)"
      case .kickoffFailed(let stderr):
        return "Failed to launch ripgrep install in guest: \(stderr)"
      case .installTimedOut(let phase, let tail):
        return "Ripgrep install timed out at phase \(phase). Last log tail: \(tail)"
      case .installFailed(let code, let tail):
        return "Ripgrep install exited \(code). Last log tail: \(tail)"
      case .finaliseFailed(let stderr):
        return "Ripgrep install completed but post-install verification failed: \(stderr)"
      }
    }
  }

  enum InstallPhase: String, Equatable {
    case kickoff
    case bootstrappingHomebrew
    case installingRipgrep
    case done
  }

  struct ProvisionReport: Equatable {
    var alreadyInstalled: Bool
    var logTail: String
  }

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
        let lines = head.split(separator: "\n").map(String.init)
        var parsedExit: Int32?
        for line in lines {
          let trimmed = line.trimmingCharacters(in: .whitespaces)
          if trimmed.hasPrefix("exit="),
            let value = trimmed.split(separator: "=").last
          {
            parsedExit = Int32(value) ?? -1
          }
        }
        exitCode = parsedExit ?? -1
      } else {
        exitCode = nil
      }
      logTail = tail
    }

    init(exitCode: Int32?, logTail: String) {
      self.exitCode = exitCode
      self.logTail = logTail
    }
  }

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
    await progress(fractionForPhase(.bootstrappingHomebrew))

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

  static func probeAlreadyInstalled(runner: any AgentBashRunner) async throws -> Bool {
    let result: ProcessResult
    do {
      result = try await runner.run(
        command: """
          set -uo pipefail
          if [ -x \(ripgrepInstallPath) ]; then
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

  static func renderInstallScript() -> String {
    """
    #!/bin/bash
    # Compass ripgrep installer for the shared VM guest.
    set -euo pipefail
    umask 022

    LOG_PATH="\(logGuestPath)"
    DONE_PATH="\(doneSentinelGuestPath)"
    RG_BIN="\(ripgrepInstallPath)"
    BREW_RG="\(brewRipgrepPath)"
    BREW_BIN="\(brewInstallPath)"
    GUEST_USER="\(SharedCompassVMBundle.State.defaultGuestUserName)"

    fail() {
      local code="$1"
      shift
      echo "[compass-rg] ERROR: $*"
      echo "exit=$code" > "$DONE_PATH"
      exit "$code"
    }

    exec > "$LOG_PATH" 2>&1
    echo "[compass-rg] $(date -u '+%Y-%m-%dT%H:%M:%SZ') starting"

    if [ -x "$RG_BIN" ]; then
      echo "[compass-rg] already installed"
    else
      if [ ! -x "$BREW_BIN" ]; then
        echo "[compass-rg] bootstrapping Homebrew as $GUEST_USER"
        su - "$GUEST_USER" -c 'NONINTERACTIVE=1 CI=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' \\
          || fail 2 "Homebrew bootstrap failed"
      fi
      echo "[compass-rg] brew install ripgrep"
      su - "$GUEST_USER" -c "'$BREW_BIN' install ripgrep" \\
        || fail 3 "brew install ripgrep failed"
      [ -x "$BREW_RG" ] || fail 4 "ripgrep missing at $BREW_RG after brew install"
      install -d -o root -g wheel -m 0755 "$(dirname "$RG_BIN")"
      ln -sf "$BREW_RG" "$RG_BIN"
      [ -x "$RG_BIN" ] || fail 5 "ripgrep symlink verification failed at $RG_BIN"
      echo "[compass-rg] installed $RG_BIN"
    fi

    echo "exit=0" > "$DONE_PATH"
    exit 0
    """
  }

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

  static func parsePhase(fromLogTail tail: String) -> InstallPhase? {
    let lower = tail.lowercased()
    if lower.contains("exit=0") {
      return .done
    }
    if lower.contains("[compass-rg] installed") || lower.contains("[compass-rg] brew install") {
      return .installingRipgrep
    }
    if lower.contains("[compass-rg] bootstrapping homebrew") {
      return .bootstrappingHomebrew
    }
    if lower.contains("[compass-rg] starting") {
      return .kickoff
    }
    return nil
  }

  static func fractionForPhase(_ phase: InstallPhase) -> Double {
    switch phase {
    case .kickoff: return 0.1
    case .bootstrappingHomebrew: return 0.35
    case .installingRipgrep: return 0.75
    case .done: return 1.0
    }
  }

  private static func plantInstallScript(runner: any AgentBashRunner) async throws {
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

  private static func kickOffInstall(runner: any AgentBashRunner) async throws {
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

  private static func pollUntilDone(
    runner: any AgentBashRunner,
    progress: (Double) async -> Void,
    now: @Sendable () -> Date,
    sleep: @Sendable (UInt64) async -> Void
  ) async throws -> ProvisionReport {
    let deadline = now().addingTimeInterval(totalInstallTimeoutSeconds)
    var lastPhase: InstallPhase = .bootstrappingHomebrew

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

  private static func pollOnce(runner: any AgentBashRunner) async throws -> PollSnapshot {
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

  private static func finalise(runner: any AgentBashRunner) async throws {
    let result: ProcessResult
    do {
      result = try await runner.run(
        command: """
          set -euo pipefail
          test -x \(ripgrepInstallPath)
          \(ripgrepInstallPath) --version >/dev/null 2>&1
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
}
