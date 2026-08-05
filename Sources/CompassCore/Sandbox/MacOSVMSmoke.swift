import Foundation

/// End-to-end smoke test for the embedded macOS VM route, exposed as
/// `compass-cli vm smoke`. Exercises the full path a real build takes:
/// VM readiness (provisioning if allowed), repo sync into the guest
/// (CAS over vsock with tar fallback), then a bash command inside the
/// guest worktree. First invocation against an unprovisioned bundle
/// downloads the IPSW and requires one admin auth prompt for the
/// headless first-boot plant.
public enum MacOSVMSmoke {
  public static let defaultCommand =
    "sw_vers && uname -m && git --version && cargo --version && rustc --version && swift --version"

  public static func run(
    repoURL: URL,
    command: String?,
    onEvent: @Sendable (HeadlessCompassEvent) -> Void
  ) async -> Bool {
    let smokeCommand = command ?? defaultCommand
    onEvent(
      HeadlessCompassEvent(
        kind: "vm_smoke",
        status: "running",
        phase: "vm",
        message: "Ensuring the macOS VM is ready (first run provisions the guest)."
      )
    )
    do {
      let runner = AgentMacOSVMBashRunner(repoRoot: repoURL, label: "vm-smoke")
      let result = try await runner.run(
        command: smokeCommand,
        workingDirectory: repoURL,
        timeout: 300
      )
      let combined = (result.stdout + "\n" + result.stderr)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard result.exitCode == 0 else {
        onEvent(
          HeadlessCompassEvent(
            kind: "vm_smoke",
            level: "error",
            status: "failed",
            phase: "vm",
            message: "Guest smoke command exited \(result.exitCode).",
            detail: combined
          )
        )
        return false
      }
      onEvent(
        HeadlessCompassEvent(
          kind: "vm_smoke",
          level: "success",
          status: "completed",
          phase: "vm",
          message: "macOS VM smoke test passed.",
          detail: combined
        )
      )
      return true
    } catch {
      onEvent(
        HeadlessCompassEvent(
          kind: "vm_smoke",
          level: "error",
          status: "failed",
          phase: "vm",
          message: "macOS VM smoke test failed: \(error.localizedDescription)"
        )
      )
      return false
    }
  }
}
