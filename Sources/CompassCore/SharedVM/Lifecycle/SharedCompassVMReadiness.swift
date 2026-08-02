import Foundation

public enum SharedCompassVMReadiness: Equatable, Sendable {
  case unavailable(reason: String)
  case notProvisioned
  case downloadingIPSW(fractionCompleted: Double)
  case installing(fractionCompleted: Double)
  case guestPrepping
  /// Headless install of Xcode Command Line Tools is in progress inside
  /// the guest. Driven over vsock by `SharedCompassVMDevToolsProvisioner`
  /// after sshd/vsock come up. `fractionCompleted` follows
  /// `softwareupdate --verbose` progress when available; before the
  /// installer starts emitting progress it stays at 0.
  case provisioningDevTools(fractionCompleted: Double)
  case ready(sshDestination: String)
  case error(detail: String)

  public var isReady: Bool {
    if case .ready = self { return true }
    return false
  }

  public var isUnavailable: Bool {
    if case .unavailable = self { return true }
    return false
  }
}
