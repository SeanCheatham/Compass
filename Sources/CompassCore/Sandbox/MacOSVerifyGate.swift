import Foundation

/// Selects where the generated-product macOS gate
/// (`GeneratedProjectQuality.macosVerifyCommand`) runs.
///
/// `.vm` is the default: the embedded macOS VM gives the gate a real
/// macOS toolchain without depending on whatever the host happens to
/// have installed. When the VM cannot be made ready (not provisioned
/// yet, provisioning failed, host unsupported), callers fall back to
/// the host shell so the gate still produces a signal.
public enum MacOSVerifyRuntime: String, CaseIterable, Sendable {
  case vm
  case host

  public static let defaultsKey = "CompassMacOSVerifyRuntime"
  public static let environmentKey = "COMPASS_MACOS_VERIFY_RUNTIME"

  public static func current(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    defaults: UserDefaults = .standard
  ) -> MacOSVerifyRuntime {
    if let raw = environment[environmentKey]?
      .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      let value = MacOSVerifyRuntime(rawValue: raw)
    {
      return value
    }
    if let raw = defaults.string(forKey: defaultsKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      let value = MacOSVerifyRuntime(rawValue: raw)
    {
      return value
    }
    return .vm
  }
}

public enum MacOSVerifyGate {
  public struct Outcome: Sendable {
    public var result: ProcessResult
    /// "macOS VM" or "host" — surfaced in logs/audit artifacts.
    public var runtimeDescription: String
    /// Set when the VM route was preferred but the gate ran on the host.
    public var fallbackReason: String?

    public init(result: ProcessResult, runtimeDescription: String, fallbackReason: String?) {
      self.result = result
      self.runtimeDescription = runtimeDescription
      self.fallbackReason = fallbackReason
    }
  }

  /// Runs the macOS verify command through the preferred runtime,
  /// falling back to the host shell when the VM route cannot run.
  public static func run(
    command: String = GeneratedProjectQuality.macosVerifyCommand,
    workingDirectory: URL,
    repoRoot: URL,
    timeout: TimeInterval,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) async -> Outcome {
    let preference = MacOSVerifyRuntime.current(environment: environment)
    guard preference == .vm else {
      let result = try? await AgentHostBashRunner().run(
        command: command,
        workingDirectory: workingDirectory,
        timeout: timeout
      )
      if let result {
        return Outcome(result: result, runtimeDescription: "host", fallbackReason: nil)
      }
      return Outcome(
        result: ProcessResult(exitCode: -1, stdout: "", stderr: "host bash failed to launch"),
        runtimeDescription: "host",
        fallbackReason: nil
      )
    }

    do {
      let runner = AgentMacOSVMBashRunner(repoRoot: repoRoot, label: "macos-verify")
      let result = try await runner.run(
        command: command,
        workingDirectory: workingDirectory,
        timeout: timeout
      )
      return Outcome(result: result, runtimeDescription: "macOS VM", fallbackReason: nil)
    } catch {
      let reason = error.localizedDescription
      do {
        let result = try await AgentHostBashRunner().run(
          command: command,
          workingDirectory: workingDirectory,
          timeout: timeout
        )
        return Outcome(
          result: result,
          runtimeDescription: "host",
          fallbackReason: reason
        )
      } catch {
        return Outcome(
          result: ProcessResult(
            exitCode: -1,
            stdout: "",
            stderr: "macOS VM route failed (\(reason)) and host fallback failed to launch"
          ),
          runtimeDescription: "host",
          fallbackReason: reason
        )
      }
    }
  }
}
