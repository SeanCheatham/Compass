import AppKit
import Combine
import Foundation
import SwiftUI
import Virtualization
import os

extension OSLog {
  /// Category we point at the first-boot pipeline so the flow is easy to
  /// filter in Console.app:
  ///     log stream --predicate 'subsystem == "com.seancheatham.Compass" AND category == "GuestProvision"'
  fileprivate static let guestProvision = OSLog(
    subsystem: "com.seancheatham.Compass", category: "GuestProvision")
}

/// Singleton host for the Compass Shared VM.
///
/// The current implementation hosts the macOS guest. Callers outside this
/// module should depend on the Shared VM route contract rather than reaching
/// into macOS-only guest paths.
///
/// Threading model: **all VZ API calls live on `@MainActor`.** Long-running
/// work (IPSW download, install) is dispatched via `Task.detached` and
/// re-enters main when interacting with VZ objects or publishing readiness.
/// The class is intentionally `final` to discourage subclass-based test
/// doubles — for testing, inject the `SharedCompassVMImageInstaller`,
/// `RestoreImageFetcher`, etc. via the `Dependencies` struct.
@MainActor
final class SharedCompassVM: ObservableObject {
  // MARK: - Published state

  @Published var readiness: SharedCompassVMReadiness = .notProvisioned

  /// Single chokepoint for `readiness` mutations. Every code path inside
  /// `SharedCompassVM` flows readiness changes through this method so:
  /// - The current → next transition is auditable in one place (handy
  ///   for debugging the multi-step provisioning flow).
  /// - Future invariants (e.g. "once `.unavailable`, never leave",
  ///   "progress-bearing states can only feed back into themselves or
  ///   into `.ready` / `.error`") can be enforced here without hunting
  ///   down 30+ scattered call sites.
  /// - The legal-transition table lives next to the chokepoint and the
  ///   state-machine tests (see `SharedCompassVMTransitionTests`) exercise
  ///   it directly.
  ///
  /// Repeated assignments of the same state are a no-op so callers can
  /// idempotently nudge the state machine without producing churn on
  /// `@Published` subscribers.
  func transition(to next: SharedCompassVMReadiness) {
    let current = readiness
    guard Self.isLegalTransition(from: current, to: next) else {
      assertionFailure(
        "Illegal readiness transition: \(Self.transitionLabel(current)) → \(Self.transitionLabel(next))"
      )
      readiness = next
      return
    }
    if current == next { return }
    readiness = next
  }

  /// Whether `next` is a permitted successor of `current`. The matrix is
  /// intentionally generous: every state can return to `.error`,
  /// `.unavailable`, or `.notProvisioned` (cancellation / teardown
  /// paths), and `.ready` can drop back to a re-provisioning prefix
  /// when the user requests a re-install. Tightening further would
  /// require lifecycle plumbing that doesn't pay for itself yet.
  static func isLegalTransition(
    from current: SharedCompassVMReadiness,
    to next: SharedCompassVMReadiness
  ) -> Bool {
    // Same-state nudges (e.g. progress fractions ticking up) are always
    // legal and the chokepoint folds them into a no-op above.
    if current == next { return true }

    // Absorbing-style terminal/initial states can always be entered.
    switch next {
    case .error, .unavailable, .notProvisioned:
      return true
    default:
      break
    }

    // From here we judge the legality of forward progress.
    switch (current, next) {
    case (.unavailable, _):
      // `.unavailable` only releases on a re-evaluation that produces
      // `.notProvisioned`, which is handled above.
      return false
    case (.notProvisioned, .downloadingIPSW),
      (.notProvisioned, .installing),
      (.notProvisioned, .guestPrepping),
      (.notProvisioned, .provisioningDevTools),
      (.notProvisioned, .ready):
      return true
    case (.downloadingIPSW, .downloadingIPSW),
      (.downloadingIPSW, .installing):
      return true
    case (.installing, .installing),
      (.installing, .guestPrepping):
      return true
    case (.guestPrepping, .guestPrepping),
      (.guestPrepping, .provisioningDevTools),
      (.guestPrepping, .ready):
      return true
    case (.provisioningDevTools, .provisioningDevTools),
      (.provisioningDevTools, .ready):
      return true
    case (.ready, .guestPrepping),
      (.ready, .provisioningDevTools),
      (.ready, .ready):
      // Re-warming an already-booted VM after a stop, or re-running
      // dev-tools provisioning.
      return true
    default:
      return false
    }
  }

  /// Short, log-friendly label for a state. Strips the associated
  /// values so a transition log line stays readable.
  private static func transitionLabel(_ state: SharedCompassVMReadiness) -> String {
    switch state {
    case .unavailable: return "unavailable"
    case .notProvisioned: return "notProvisioned"
    case .downloadingIPSW: return "downloadingIPSW"
    case .installing: return "installing"
    case .guestPrepping: return "guestPrepping"
    case .provisioningDevTools: return "provisioningDevTools"
    case .ready: return "ready"
    case .error: return "error"
    }
  }

  /// Snapshot of the most recent persisted state document. Updated whenever
  /// `readiness` is recomputed from disk.
  @Published var persistedState: SharedCompassVMBundle.State?

  /// Transient diagnostic about the most-recent `markSetupComplete()` call.
  /// Cleared on the next invocation. Surfacing this in the UI lets the user
  /// tell a "still working on it" attempt apart from a "IP discovery
  /// failed, sshd is probably off" attempt without leaving the readiness
  /// state machine in the absorbing `.error(detail:)` state.
  @Published var setupFailureMessage: String?

  /// `true` while the host app is tearing down on its way to terminate.
  /// Set by the AppDelegate before it awaits `stop()` so the UI can swap to
  /// a "Shutting down…" view instead of leaving the live workspace frozen
  /// on screen during the up-to-6s VM stop budget. One-way flag: once set,
  /// the process is on its way out and we never clear it.
  @Published var isShuttingDown: Bool = false

  /// Flips `isShuttingDown` so observers can transition to a shutdown UI
  /// before the synchronous VZ stop work begins. Idempotent.
  func beginShutdown() {
    guard !isShuttingDown else { return }
    isShuttingDown = true
  }

  // MARK: - Owned values

  let bundle: SharedCompassVMBundle

  let dependencies: Dependencies
  @Published var virtualMachine: VZVirtualMachine?
  var sleepObserver: SharedCompassVMSleepObserver?
  var lastResolvedSSHDestination: String?

  /// Pipe attached to the guest's virtio console port. VZ writes guest serial
  /// output into `consoleOutputPipe.fileHandleForWriting`; the host's read
  /// task drains `consoleOutputPipe.fileHandleForReading`. The host keeps
  /// the pipe alive for the lifetime of the running VM so the buffer is
  /// never closed mid-read. The guest's first-boot script writes its IP as
  /// `COMPASS_GUEST_IP=<addr>\n` for IP discovery; other traffic is dropped.
  var consoleOutputPipe: Pipe?
  var consoleReadTask: Task<Void, Never>?

  /// Serializes concurrent `start()` calls so two simultaneous callers cannot
  /// each construct their own `VZVirtualMachine`.
  var startInFlight: Task<Void, Error>?

  /// Serializes restore-image installation. `VZMacOSInstaller` mutates the
  /// bundle's disk image, auxiliary storage, and platform identity files; only
  /// one caller may touch that state at a time.
  var provisionInFlight: Task<Void, Error>?

  // MARK: - Shared singleton

  /// Process-wide host instance. AppModel binds to this so the launch-plan
  /// integration can reach the same readiness state from any call site.
  /// `makeDefault()` returns nil if its dependencies (e.g. Application
  /// Support / Caches directory creation) cannot be satisfied — in that case
  /// `shared.readiness` reports `.unavailable(...)` and downstream callers
  /// fall back to host execution.
  static let shared: SharedCompassVM = {
    do {
      return try SharedCompassVM.makeDefault()
    } catch {
      let detail = SharedCompassVMAvailabilityCheck.describe(error: error)
      return SharedCompassVM(
        bundle: SharedCompassVMBundle(
          rootURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("compass-shared-vm-fallback", isDirectory: true)),
        fallbackUnavailableReason: "Shared VM bundle could not be initialised: \(detail)"
      )
    }
  }()

  // MARK: - Dependencies (injection seam)

  struct Dependencies {
    var imageInstaller: SharedCompassVMImageInstaller
    var fileManager: FileManager
    var availability: @MainActor () -> SharedCompassVMAvailability
    /// Plants the headless first-boot artefacts onto the installed disk.
    /// Injectable so tests can substitute a no-op (real planting needs
    /// `osascript` + an admin auth prompt and is unsuited to unit tests).
    var headlessPlanter: HeadlessPlanterRunning
    /// Keychain (or in-memory) backing for the guest's auto-generated
    /// admin password.
    var credentialStorage: SharedCompassVMGuestCredential.Storage

    static func live() -> Dependencies {
      Dependencies(
        imageInstaller: SharedCompassVMImageInstaller(),
        fileManager: .default,
        availability: { SharedCompassVMAvailabilityCheck.evaluate() },
        headlessPlanter: DefaultHeadlessPlanter(),
        credentialStorage: SharedCompassVMGuestCredential.KeychainStorage()
      )
    }
  }

  // MARK: - Init

  /// When non-nil, every lifecycle method is short-circuited and `readiness`
  /// reports `.unavailable(reason:)`. Used by `SharedCompassVM.shared` when
  /// even constructing the canonical bundle fails (e.g. unwritable home).
  let fallbackUnavailableReason: String?

  init(
    bundle: SharedCompassVMBundle,
    dependencies: Dependencies = .live(),
    fallbackUnavailableReason: String? = nil
  ) {
    self.bundle = bundle
    self.dependencies = dependencies
    self.fallbackUnavailableReason = fallbackUnavailableReason
    if let reason = fallbackUnavailableReason {
      transition(to: .unavailable(reason: reason))
    }
    installSleepObserver()
  }

  /// Convenience constructor that wires the canonical bundle
  /// location. The VM has no host-side workspaces share anymore —
  /// the agent operates in the per-repo guest workspace allocated
  /// by `SharedCompassVMGuestWorkspaceCatalog` and host↔guest sync
  /// flows over vsock (see `SharedCompassVMWorktreeSync`).
  static func makeDefault() throws -> SharedCompassVM {
    let bundle = try SharedCompassVMBundle.defaultBundle()
    return SharedCompassVM(bundle: bundle)
  }

}
