import Foundation

/// Host-driven Swift mutation-tool provisioning for the Compass shared VM guest.
///
/// Runs after `SharedCompassVMDevToolsProvisioner` has brought Command Line
/// Tools online. Builds a pinned Muter release with the guest `swift` toolchain
/// and installs it to `/usr/local/bin/muter` so Develop/Verify/Mutation all
/// share the same execution environment.
///
/// Also bootstraps Homebrew under the compass user (if not already present)
/// and installs `ripgrep`, symlinked to `/usr/local/bin/rg` so it picks up
/// via the existing path_helper-driven `~/.zshenv`. Agent searches inside
/// the guest use `rg` because naive `grep -r` walks the SPM `.build` tree
/// and times out (verified live — challenge-mode iteration died on a 30s
/// `grep` over the project root).
enum SharedCompassVMMutationToolsProvisioner {
  static let muterReleaseTag = "16"
  static let muterInstallPath = "/usr/local/bin/muter"
  static let ripgrepInstallPath = "/usr/local/bin/rg"
  static let brewInstallPath = "/opt/homebrew/bin/brew"
  static let scriptGuestPath = "/usr/local/libexec/compass-install-muter.sh"
  static let logGuestPath = "/var/log/compass-muter-install.log"
  static let doneSentinelGuestPath = "/var/log/compass-muter-install.done"
  static let installLaunchDaemonLabel = "com.seancheatham.Compass.muter-install"
  static let installLaunchDaemonPlistGuestPath =
    "/Library/LaunchDaemons/com.seancheatham.Compass.muter-install.plist"
  static let cltSwiftPath = SharedCompassVMDevToolsProvisioner.cltSwiftPath

  static let shortStepTimeoutSeconds: TimeInterval = 30
  static let pollIntervalSeconds: Double = 5
  static let totalInstallTimeoutSeconds: TimeInterval = 20 * 60

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
        return "Muter probe failed: \(stderr)"
      case .scriptPlantFailed(let stderr):
        return "Failed to plant Muter install script in guest: \(stderr)"
      case .kickoffFailed(let stderr):
        return "Failed to launch Muter install in guest: \(stderr)"
      case .installTimedOut(let phase, let tail):
        return "Muter install timed out at phase \(phase). Last log tail: \(tail)"
      case .installFailed(let code, let tail):
        return "Muter install exited \(code). Last log tail: \(tail)"
      case .finaliseFailed(let stderr):
        return "Muter install completed but post-install verification failed: \(stderr)"
      }
    }
  }

  enum InstallPhase: String, Equatable {
    case kickoff
    case downloading
    case building
    case installing
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
    await progress(fractionForPhase(.downloading))

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

  /// PRESENT only when both Muter and ripgrep are usable. Either one
  /// missing re-runs the install — the script is idempotent for each
  /// tool, so re-installing one doesn't re-do the other.
  static func probeAlreadyInstalled(runner: any AgentBashRunner) async throws -> Bool {
    let result: ProcessResult
    do {
      result = try await runner.run(
        command: """
          set -uo pipefail
          if [ -x \(muterInstallPath) ] && [ -x \(ripgrepInstallPath) ]; then
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
    # Compass supplemental-tools installer for the shared VM guest.
    # Installs Muter (built from a pinned source release with the guest
    # CLT swift) and ripgrep (via Homebrew, bootstrapped under the
    # compass user since brew refuses to run as root).
    set -uo pipefail
    umask 022

    LOG_PATH="\(logGuestPath)"
    DONE_PATH="\(doneSentinelGuestPath)"
    MUTER_TAG="\(muterReleaseTag)"
    MUTER_BIN="\(muterInstallPath)"
    RG_BIN="\(ripgrepInstallPath)"
    BREW_BIN="\(brewInstallPath)"
    GUEST_USER="\(SharedCompassVMBundle.State.defaultGuestUserName)"
    CLT_SWIFT="\(cltSwiftPath)"

    exec > "$LOG_PATH" 2>&1
    echo "[compass-muter] $(date -u '+%Y-%m-%dT%H:%M:%SZ') starting"

    # --- Muter ---
    if [ -x "$MUTER_BIN" ]; then
      echo "[compass-muter] already installed"
    else
      if [ ! -x "$CLT_SWIFT" ]; then
        echo "[compass-muter] ERROR: Command Line Tools swift missing at $CLT_SWIFT"
        echo "exit=2" > "$DONE_PATH"
        exit 2
      fi

      WORKDIR="$(mktemp -d /tmp/compass-muter.XXXXXX)"
      cleanup() { rm -rf "$WORKDIR"; }
      trap cleanup EXIT

      ARCHIVE="$WORKDIR/muter.tar.gz"
      echo "[compass-muter] downloading release $MUTER_TAG"
      curl -fsSL "https://github.com/muter-mutation-testing/muter/archive/refs/tags/${MUTER_TAG}.tar.gz" -o "$ARCHIVE"
      tar xzf "$ARCHIVE" -C "$WORKDIR"
      SRC="$(find "$WORKDIR" -mindepth 1 -maxdepth 1 -type d | head -1)"
      if [ -z "$SRC" ]; then
        echo "[compass-muter] ERROR: could not locate extracted Muter sources"
        echo "exit=3" > "$DONE_PATH"
        exit 3
      fi

      cd "$SRC"
      echo "[compass-muter] building Muter with guest swift"
      "$CLT_SWIFT" build -c release
      install -m 755 .build/release/muter "$MUTER_BIN"
      echo "[compass-muter] installed $MUTER_BIN"
      cd /
    fi

    # --- ripgrep (via Homebrew) ---
    # Bootstrap Homebrew under the compass user if absent. NONINTERACTIVE=1
    # skips the "press RETURN" prompt; CI=1 silences analytics chatter.
    # The installer uses sudo internally — compass has NOPASSWD sudo from
    # firstboot, so it goes through without a password prompt.
    if [ -x "$RG_BIN" ]; then
      echo "[compass-rg] already installed"
    else
      if [ ! -x "$BREW_BIN" ]; then
        echo "[compass-rg] bootstrapping Homebrew as $GUEST_USER"
        su - "$GUEST_USER" -c 'NONINTERACTIVE=1 CI=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
      fi
      echo "[compass-rg] brew install ripgrep"
      su - "$GUEST_USER" -c "'$BREW_BIN' install ripgrep"
      # Symlink the brew-installed binary into /usr/local/bin so the
      # existing path_helper-based zshenv (planted by firstboot) picks
      # it up. /opt/homebrew/bin is otherwise not on PATH for non-
      # interactive SSH command runs.
      ln -sf /opt/homebrew/bin/rg "$RG_BIN"
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
    // Most-advanced markers first so a late earlier-phase line in the
    // tail doesn't pull the UI backwards.
    if lower.contains("exit=0") {
      return .done
    }
    if lower.contains("[compass-rg] installed") || lower.contains("[compass-rg] brew install") {
      return .installingRipgrep
    }
    if lower.contains("[compass-rg] bootstrapping homebrew") {
      return .bootstrappingHomebrew
    }
    if lower.contains("[compass-muter] installed") {
      return .installing
    }
    if lower.contains("install -m 755") || lower.contains("building release") {
      return .installing
    }
    if lower.contains("building muter") || lower.contains("swift build") {
      return .building
    }
    if lower.contains("downloading release") || lower.contains("curl -fsSL") {
      return .downloading
    }
    if lower.contains("[compass-muter] starting") {
      return .kickoff
    }
    return nil
  }

  static func fractionForPhase(_ phase: InstallPhase) -> Double {
    switch phase {
    case .kickoff: return 0.05
    case .downloading: return 0.15
    case .building: return 0.40
    case .installing: return 0.65
    case .bootstrappingHomebrew: return 0.75
    case .installingRipgrep: return 0.90
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
    var lastPhase: InstallPhase = .downloading

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
          test -x \(muterInstallPath)
          test -x \(ripgrepInstallPath)
          \(muterInstallPath) operator all >/dev/null 2>&1 || true
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
