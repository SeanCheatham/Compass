import Foundation

@MainActor
extension SharedCompassVM {
  // MARK: - Lifecycle

  /// Quick "is the host capable + is anything cached?" check. Does NOT start
  /// the VM. Safe to call from `AppModel.bootstrap`.
  public func warmup() async throws {
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
        // not that anything is running *right now* — on app launch no
        // VM has been booted yet. Report `.stopped` so the UI reflects
        // reality; `start()` boots the guest and flips to `.ready` once
        // SSH actually answers.
        //
        // Critical: `ensureReady()` / the runtime view call `warmup()`
        // while a guest may already be running. Never demote a live VM
        // to `.stopped` — `start()` no-ops when VZ is up and will not
        // re-kick the SSH poll, which leaves bash hung and the UI stuck
        // on Stopped.
        if let ip = state.lastKnownGoodIP {
          lastResolvedSSHDestination = "\(state.guestUserName)@\(ip)"
        }
        if virtualMachine == nil {
          transition(to: .stopped)
        }
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
  public func guestConsoleLogin() -> SharedCompassVMGuestCredential.GuestConsoleLogin? {
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
