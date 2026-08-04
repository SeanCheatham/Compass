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
  /// No VM is running, but the bundle on disk may be at any provision
  /// step. Entered from the live states via `stop()` and used by
  /// `warmup()` as the launch-time placeholder for a persisted `.ready`
  /// bundle (nothing has booted yet, so claiming guest prep is underway
  /// would be misleading). Re-enter the forward states via `start()`.
  /// Only valid when `virtualMachine == nil` — never demote a live guest
  /// to `.stopped` (that leaves bash/`ensureReady` waiting for a poll
  /// `start()` will not re-kick).
  case stopped
  /// Guest VZ machine is up (or boot was just requested) and the host is
  /// waiting for SSH + guest-agent before publishing `.ready`. Used for
  /// subsequent boots of an already-provisioned bundle so the UI does not
  /// claim "Stopped" while the post-boot poll runs.
  case starting

  public var isReady: Bool {
    if case .ready = self { return true }
    return false
  }

  public var isUnavailable: Bool {
    if case .unavailable = self { return true }
    return false
  }
}
