import Foundation

/// Generic LaunchDaemon-driven toolchain installer for the Shared VM guest.
///
/// Parameterized by `SharedVMToolchainDefinition` so homebrew, ripgrep, rust,
/// and other catalog entries share one probe → plant → kickoff → poll →
/// finalise pipeline.
enum SharedCompassVMToolchainProvisioner {
  static let shortStepTimeoutSeconds: TimeInterval = 30
  static let pollIntervalSeconds: Double = 5

  enum ProvisionError: Error, CustomStringConvertible, Equatable {
    case probeFailed(toolchainID: String, stderr: String)
    case scriptPlantFailed(toolchainID: String, stderr: String)
    case kickoffFailed(toolchainID: String, stderr: String)
    case installTimedOut(toolchainID: String, logTail: String)
    case installFailed(toolchainID: String, exitCode: Int32, logTail: String)
    case finaliseFailed(toolchainID: String, stderr: String)

    var description: String {
      switch self {
      case .probeFailed(let id, let stderr):
        return "Toolchain \(id) probe failed: \(stderr)"
      case .scriptPlantFailed(let id, let stderr):
        return "Failed to plant \(id) install script in guest: \(stderr)"
      case .kickoffFailed(let id, let stderr):
        return "Failed to launch \(id) install in guest: \(stderr)"
      case .installTimedOut(let id, let tail):
        return "Toolchain \(id) install timed out. Last log tail: \(tail)"
      case .installFailed(let id, let code, let tail):
        return "Toolchain \(id) install exited \(code). Last log tail: \(tail)"
      case .finaliseFailed(let id, let stderr):
        return "Toolchain \(id) install completed but post-install verification failed: \(stderr)"
      }
    }
  }

  struct ProvisionReport: Equatable {
    var toolchainID: String
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
  }

  static func probe(
    definition: SharedVMToolchainDefinition,
    runner: any AgentBashRunner
  ) async throws -> Bool {
    let result: ProcessResult
    do {
      result = try await runner.run(
        command: """
          set -uo pipefail
          \(definition.probeCommand)
          """,
        workingDirectory: URL(fileURLWithPath: "/"),
        timeout: shortStepTimeoutSeconds
      )
    } catch {
      throw ProvisionError.probeFailed(toolchainID: definition.stringID, stderr: "\(error)")
    }
    if result.exitCode != 0 {
      throw ProvisionError.probeFailed(toolchainID: definition.stringID, stderr: result.stderr)
    }
    return result.stdout.contains("PRESENT")
  }

  static func provision(
    definition: SharedVMToolchainDefinition,
    runner: any AgentBashRunner,
    progress: (Double) async -> Void,
    now: @Sendable () -> Date = { Date() },
    sleep: @Sendable (UInt64) async -> Void = { ns in try? await Task.sleep(nanoseconds: ns) }
  ) async throws -> ProvisionReport {
    precondition(
      definition.installableViaGenericProvisioner,
      "Toolchain \(definition.stringID) is not installable via generic provisioner")

    await progress(0)

    if try await probe(definition: definition, runner: runner) {
      await progress(1)
      return ProvisionReport(toolchainID: definition.stringID, alreadyInstalled: true, logTail: "")
    }

    try await plantInstallScript(definition: definition, runner: runner)
    try await kickOffInstall(definition: definition, runner: runner)
    await progress(0.1)

    let report = try await pollUntilDone(
      definition: definition,
      runner: runner,
      progress: progress,
      now: now,
      sleep: sleep
    )

    try await finalise(definition: definition, runner: runner)
    await progress(1)
    return report
  }

  static func renderInstallLaunchDaemonPlist(definition: SharedVMToolchainDefinition) -> String {
    let id = definition.stringID
    let scriptPath = SharedVMToolchainPaths.scriptGuestPath(id: id)
    let logPath = SharedVMToolchainPaths.logGuestPath(id: id)
    let label = SharedVMToolchainPaths.installLaunchDaemonLabel(id: id)
    return """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTD/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
          <key>Label</key>
          <string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
              <string>\(scriptPath)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <false/>
          <key>LaunchOnlyOnce</key>
          <true/>
          <key>StandardOutPath</key>
          <string>\(logPath)</string>
          <key>StandardErrorPath</key>
          <string>\(logPath)</string>
      </dict>
      </plist>
      """
  }

  private static func plantInstallScript(
    definition: SharedVMToolchainDefinition,
    runner: any AgentBashRunner
  ) async throws {
    let id = definition.stringID
    let scriptGuestPath = SharedVMToolchainPaths.scriptGuestPath(id: id)
    let plistGuestPath = SharedVMToolchainPaths.installLaunchDaemonPlistGuestPath(id: id)
    let donePath = SharedVMToolchainPaths.doneSentinelGuestPath(id: id)
    let logPath = SharedVMToolchainPaths.logGuestPath(id: id)
    let scriptEncoded = Data(definition.renderInstallScript().utf8).base64EncodedString()
    let plistEncoded = Data(renderInstallLaunchDaemonPlist(definition: definition).utf8)
      .base64EncodedString()
    let command = """
      set -euo pipefail
      echo \(scriptEncoded) | base64 -D | sudo tee \(scriptGuestPath) > /dev/null
      sudo chmod 0755 \(scriptGuestPath)
      sudo chown root:wheel \(scriptGuestPath)
      echo \(plistEncoded) | base64 -D | sudo tee \(plistGuestPath) > /dev/null
      sudo chmod 0644 \(plistGuestPath)
      sudo chown root:wheel \(plistGuestPath)
      sudo rm -f \(donePath) \(logPath)
      sudo launchctl bootout system \(plistGuestPath) 2>/dev/null || true
      """
    let result: ProcessResult
    do {
      result = try await runner.run(
        command: command,
        workingDirectory: URL(fileURLWithPath: "/"),
        timeout: shortStepTimeoutSeconds
      )
    } catch {
      throw ProvisionError.scriptPlantFailed(toolchainID: id, stderr: "\(error)")
    }
    if result.exitCode != 0 {
      throw ProvisionError.scriptPlantFailed(toolchainID: id, stderr: result.stderr)
    }
  }

  private static func kickOffInstall(
    definition: SharedVMToolchainDefinition,
    runner: any AgentBashRunner
  ) async throws {
    let plistGuestPath = SharedVMToolchainPaths.installLaunchDaemonPlistGuestPath(
      id: definition.stringID)
    let result: ProcessResult
    do {
      result = try await runner.run(
        command: """
          set -euo pipefail
          sudo launchctl bootstrap system \(plistGuestPath)
          """,
        workingDirectory: URL(fileURLWithPath: "/"),
        timeout: shortStepTimeoutSeconds
      )
    } catch {
      throw ProvisionError.kickoffFailed(toolchainID: definition.stringID, stderr: "\(error)")
    }
    if result.exitCode != 0 {
      throw ProvisionError.kickoffFailed(toolchainID: definition.stringID, stderr: result.stderr)
    }
  }

  private static func pollUntilDone(
    definition: SharedVMToolchainDefinition,
    runner: any AgentBashRunner,
    progress: (Double) async -> Void,
    now: @Sendable () -> Date,
    sleep: @Sendable (UInt64) async -> Void
  ) async throws -> ProvisionReport {
    let id = definition.stringID
    let donePath = SharedVMToolchainPaths.doneSentinelGuestPath(id: id)
    let logPath = SharedVMToolchainPaths.logGuestPath(id: id)
    let deadline = now().addingTimeInterval(definition.installTimeout)
    var lastFraction: Double = 0.1

    while now() < deadline {
      await sleep(UInt64(pollIntervalSeconds * 1_000_000_000))

      let snapshot = try await pollOnce(
        donePath: donePath,
        logPath: logPath,
        runner: runner,
        toolchainID: id
      )
      let fraction = definition.parseProgressFraction(fromLogTail: snapshot.logTail)
      if fraction > lastFraction {
        lastFraction = fraction
        await progress(fraction)
      }
      if let exitCode = snapshot.exitCode {
        if exitCode == 0 {
          return ProvisionReport(
            toolchainID: id, alreadyInstalled: false, logTail: snapshot.logTail)
        }
        throw ProvisionError.installFailed(
          toolchainID: id, exitCode: exitCode, logTail: snapshot.logTail)
      }
    }

    let finalSnapshot = try await pollOnce(
      donePath: donePath,
      logPath: logPath,
      runner: runner,
      toolchainID: id
    )
    throw ProvisionError.installTimedOut(toolchainID: id, logTail: finalSnapshot.logTail)
  }

  private static func pollOnce(
    donePath: String,
    logPath: String,
    runner: any AgentBashRunner,
    toolchainID: String
  ) async throws -> PollSnapshot {
    let result: ProcessResult
    do {
      result = try await runner.run(
        command: """
          set -uo pipefail
          if [ -f \(donePath) ]; then
            echo DONE
            cat \(donePath)
          else
            echo RUNNING
          fi
          echo ---LOG_TAIL---
          if [ -f \(logPath) ]; then
            tail -n 40 \(logPath) 2>/dev/null || true
          fi
          """,
        workingDirectory: URL(fileURLWithPath: "/"),
        timeout: shortStepTimeoutSeconds
      )
    } catch {
      throw ProvisionError.probeFailed(toolchainID: toolchainID, stderr: "\(error)")
    }
    return PollSnapshot(parsing: result.stdout)
  }

  private static func finalise(
    definition: SharedVMToolchainDefinition,
    runner: any AgentBashRunner
  ) async throws {
    let id = definition.stringID
    let plistGuestPath = SharedVMToolchainPaths.installLaunchDaemonPlistGuestPath(id: id)
    let result: ProcessResult
    do {
      result = try await runner.run(
        command: """
          set -euo pipefail
          \(definition.finaliseVerificationCommand())
          sudo launchctl bootout system \(plistGuestPath) 2>/dev/null || true
          sudo rm -f \(plistGuestPath)
          """,
        workingDirectory: URL(fileURLWithPath: "/"),
        timeout: shortStepTimeoutSeconds
      )
    } catch {
      throw ProvisionError.finaliseFailed(toolchainID: id, stderr: "\(error)")
    }
    if result.exitCode != 0 {
      throw ProvisionError.finaliseFailed(toolchainID: id, stderr: result.stderr)
    }
  }
}
