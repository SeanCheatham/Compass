import Foundation

/// Host-side helpers for opt-in headed macOS UI fidelity
/// (`scripts/macos-ui-smoke.sh` when `COMPASS_MACOS_UI_FIDELITY=1`): ensure a
/// headed guest session before verify, and pull `apps/macos/dist/ui-smoke.png`
/// into session audit. Primary UI proof is `crates/ui` simulation under
/// `cargo test` — see `docs/ui-runtime.md`.
public enum MacOSUISmokeSupport {
  public static let screenshotRelativePath = "apps/macos/dist/ui-smoke.png"
  public static let auditArtifactName = "ui-smoke.png"
  public static let fidelityEnvironmentKey = "COMPASS_MACOS_UI_FIDELITY"

  /// True when headed launch + screenshot should run during macOS verify.
  public static func isFidelityEnabled(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Bool {
    let raw =
      environment[fidelityEnvironmentKey]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
    return raw == "1" || raw == "true" || raw == "yes"
  }

  /// Prefixes the guest verify command so fidelity env reaches the script
  /// (vsock bash does not forward the full host environment).
  public static func verifyCommand(
    base: String = GeneratedProjectQuality.macosVerifyCommand,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> String {
    if isFidelityEnabled(environment: environment) {
      return "\(fidelityEnvironmentKey)=1 \(base)"
    }
    return base
  }

  /// Best-effort auto-login repair so AX / screencapture see an Aqua session.
  /// Failures are non-fatal here — the guest script fails closed if `/dev/console`
  /// is still at the login window.
  @MainActor
  public static func ensureDesktopSessionForVerify() async {
    let vm = SharedCompassVM.shared
    let options = AgentMacOSVMBashRunner.sshOptions()
    let destination: String? = {
      if case .ready(let ssh) = vm.readiness { return ssh }
      return vm.lastResolvedSSHDestination
    }()
    guard let destination else { return }

    let active = await SharedCompassVMAutoLoginRepair.isDesktopSessionActive(
      destination: destination,
      options: options
    )
    if active { return }
    _ = await vm.repairAutoLogin(destination: destination)
  }

  /// Reads the guest (or host) UI smoke screenshot if present.
  public static func loadScreenshotData(repoURL: URL) async -> Data? {
    let hostURL = repoURL.appending(path: screenshotRelativePath)
    if let data = try? Data(contentsOf: hostURL), !data.isEmpty {
      return data
    }

    do {
      let ready = try await AgentMacOSVMBashRunner.ensureReady()
      let entry = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(forRepoURL: repoURL)
      let guestPath =
        SharedCompassVMGuestWorkspaceCatalog.guestWorktreePath(forEntry: entry)
        + "/" + screenshotRelativePath
      return try await ready.client.readFile(at: URL(fileURLWithPath: guestPath))
    } catch {
      return nil
    }
  }

  /// Writes the screenshot into the session audit manifest when available.
  @discardableResult
  public static func writeScreenshotAuditArtifact(
    workspace: CompassWorkspace,
    session: Int,
    repoURL: URL
  ) async -> URL? {
    guard let data = await loadScreenshotData(repoURL: repoURL), !data.isEmpty else {
      return nil
    }
    return try? workspace.writeSessionAuditArtifactData(
      session: session,
      name: auditArtifactName,
      kind: "image",
      data: data,
      note: "macOS UI fidelity screenshot (guest macOS app)."
    )
  }
}
