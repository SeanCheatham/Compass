import Foundation

/// Host-side helpers for the generated-product macOS UI smoke
/// (`scripts/macos-ui-smoke.sh`): ensure a headed guest session before
/// verify, and pull `apps/macos/dist/ui-smoke.png` into session audit.
public enum MacOSUISmokeSupport {
  public static let screenshotRelativePath = "apps/macos/dist/ui-smoke.png"
  public static let auditArtifactName = "ui-smoke.png"

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
      note: "macOS UI smoke screenshot (guest GeneratedApp)."
    )
  }
}
