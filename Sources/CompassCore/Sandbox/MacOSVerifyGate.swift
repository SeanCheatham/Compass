import Foundation

/// The generated-product macOS gate
/// (`GeneratedProjectQuality.macosVerifyCommand`) always runs inside the
/// embedded macOS VM. There is no host-shell fallback: Compass requires
/// the VM for factory verify.
///
/// Primary UI proof is `crates/ui` simulation under Rust `cargo test`.
/// When `COMPASS_MACOS_UI_FIDELITY=1`, Compass repairs graphical auto-login
/// and the guest script runs headed launch + AX + screenshot.
public enum MacOSVerifyGate {
  public struct Outcome: Sendable {
    public var result: ProcessResult
    /// Surfaced in logs/audit artifacts.
    public var runtimeDescription: String
    /// Retained for call-site compatibility; always `nil` now that host
    /// fallback is removed.
    public var fallbackReason: String?

    public init(result: ProcessResult, runtimeDescription: String, fallbackReason: String?) {
      self.result = result
      self.runtimeDescription = runtimeDescription
      self.fallbackReason = fallbackReason
    }
  }

  /// Runs the macOS verify command inside the embedded macOS VM.
  /// VM failures surface as a non-zero `Outcome` rather than falling
  /// back to the host shell.
  public static func run(
    command: String = GeneratedProjectQuality.macosVerifyCommand,
    workingDirectory: URL,
    repoRoot: URL,
    timeout: TimeInterval,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) async -> Outcome {
    let fidelity = MacOSUISmokeSupport.isFidelityEnabled(environment: environment)
    let guestCommand = MacOSUISmokeSupport.verifyCommand(
      base: command,
      environment: environment
    )
    do {
      _ = try await AgentMacOSVMBashRunner.ensureReady()
      if fidelity {
        await MacOSUISmokeSupport.ensureDesktopSessionForVerify()
      }
      let runner = AgentMacOSVMBashRunner(repoRoot: repoRoot, label: "macos-verify")
      let result = try await runner.run(
        command: guestCommand,
        workingDirectory: workingDirectory,
        timeout: timeout
      )
      return Outcome(result: result, runtimeDescription: "macOS VM", fallbackReason: nil)
    } catch {
      return Outcome(
        result: ProcessResult(
          exitCode: -1,
          stdout: "",
          stderr: "macOS VM verify failed: \(error.localizedDescription)"
        ),
        runtimeDescription: "macOS VM",
        fallbackReason: nil
      )
    }
  }
}
