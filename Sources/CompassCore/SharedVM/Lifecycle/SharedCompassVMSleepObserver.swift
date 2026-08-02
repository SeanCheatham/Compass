import AppKit
import Foundation

/// Registers `NSWorkspace` sleep/wake observers so the owning `SharedCompassVM`
/// can pause the guest before the host sleeps (preventing clock skew, expired
/// auth tokens, and dead network sockets) and resume cleanly on wake.
///
/// Observers are torn down in `deinit`. Callers should hold a strong reference
/// for the lifetime of the VM.
final class SharedCompassVMSleepObserver {
  typealias Hook = @Sendable () -> Void

  private let center: NotificationCenter
  private let willSleep: Hook
  private let didWake: Hook
  private var willSleepObserver: NSObjectProtocol?
  private var didWakeObserver: NSObjectProtocol?

  /// `center` defaults to `NSWorkspace.shared.notificationCenter`, which is
  /// where the system actually posts sleep/wake notifications (NOT the
  /// default `NotificationCenter.default`). Injectable for tests.
  init(
    center: NotificationCenter = NSWorkspace.shared.notificationCenter,
    willSleep: @escaping Hook,
    didWake: @escaping Hook
  ) {
    self.center = center
    self.willSleep = willSleep
    self.didWake = didWake
    register()
  }

  deinit {
    if let token = willSleepObserver {
      center.removeObserver(token)
    }
    if let token = didWakeObserver {
      center.removeObserver(token)
    }
  }

  private func register() {
    willSleepObserver = center.addObserver(
      forName: NSWorkspace.willSleepNotification,
      object: nil,
      queue: .main
    ) { [willSleep] _ in
      willSleep()
    }
    didWakeObserver = center.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [didWake] _ in
      didWake()
    }
  }
}
