import Foundation

@MainActor
extension SharedCompassVM {
  // MARK: - Lifecycle

  /// Quick "is the host capable + is anything cached?" check. Does NOT start
  /// the VM. Safe to call from `AppModel.bootstrap`.
  func warmup() async throws {
    if let reason = fallbackUnavailableReason {
      transition(to: .unavailable(reason: reason))
      return
    }
    let availability = dependencies.availability()
    if case .unavailable(let reason) = availability {
      transition(to: .unavailable(reason: reason))
      return
    }

    try bundle.ensureExists(fileManager: dependencies.fileManager)
    let state =
      (try? bundle.loadState(fileManager: dependencies.fileManager))
      ?? SharedCompassVMBundle.State()
    persistedState = state

    if bundle.existsOnDisk(fileManager: dependencies.fileManager) {
      switch state.provisionStep {
      case .ready:
        // Persisted "ready" means the bundle was healthy last session,
        // not that the guest's sshd is up *right now*. On app launch
        // the VM has yet to be booted by `start()`, and macOS inside
        // the guest takes several seconds to come back. Hold the
        // in-memory readiness at `.guestPrepping` so the UI doesn't
        // claim the VM is reachable before SSH actually responds —
        // `performStart()` will probe and flip to `.ready` once the
        // guest answers.
        if let ip = state.lastKnownGoodIP {
          lastResolvedSSHDestination = "\(state.guestUserName)@\(ip)"
        }
        transition(to: .guestPrepping)
      case .guestPrepping:
        transition(to: .guestPrepping)
      case .provisioningDevTools:
        transition(to: .provisioningDevTools(fractionCompleted: 0))
      case .installing:
        transition(to: .installing(fractionCompleted: 0))
      case .downloadingIPSW:
        transition(to: .downloadingIPSW(fractionCompleted: 0))
      case .notProvisioned:
        transition(to: .notProvisioned)
      }
    } else {
      transition(to: .notProvisioned)
    }
  }

  /// Guest username + password for the headed Sandbox console. Nil until
  /// provisioning has planted the headless first-boot payload and stored
  /// the generated password in the host Keychain.
  func guestConsoleLogin() -> SharedCompassVMGuestCredential.GuestConsoleLogin? {
    let state =
      persistedState
      ?? (try? bundle.loadState(fileManager: dependencies.fileManager))
    guard let state else { return nil }
    return try? SharedCompassVMGuestCredential.consoleLogin(
      guestUserName: state.guestUserName,
      keychainAccount: state.guestPasswordKeychainAccount,
      storage: dependencies.credentialStorage
    )
  }

  // MARK: - Internals

  func installSleepObserver() {
    sleepObserver = SharedCompassVMSleepObserver(
      willSleep: { [weak self] in
        Task { @MainActor in
          self?.pause()
        }
      },
      didWake: { [weak self] in
        Task { @MainActor in
          self?.resume()
        }
      }
    )
  }
}
