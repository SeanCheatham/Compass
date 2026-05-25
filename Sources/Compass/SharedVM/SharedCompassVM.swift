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

/// Singleton host for the Compass shared macOS VM.
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

  @Published private(set) var readiness: SharedCompassVMReadiness = .notProvisioned

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
  fileprivate func transition(to next: SharedCompassVMReadiness) {
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
  @Published private(set) var persistedState: SharedCompassVMBundle.State?

  /// Transient diagnostic about the most-recent `markSetupComplete()` call.
  /// Cleared on the next invocation. Surfacing this in the UI lets the user
  /// tell a "still working on it" attempt apart from a "IP discovery
  /// failed, sshd is probably off" attempt without leaving the readiness
  /// state machine in the absorbing `.error(detail:)` state.
  @Published private(set) var setupFailureMessage: String?

  /// `true` while the host app is tearing down on its way to terminate.
  /// Set by the AppDelegate before it awaits `stop()` so the UI can swap to
  /// a "Shutting down…" view instead of leaving the live workspace frozen
  /// on screen during the up-to-6s VM stop budget. One-way flag: once set,
  /// the process is on its way out and we never clear it.
  @Published private(set) var isShuttingDown: Bool = false

  /// Flips `isShuttingDown` so observers can transition to a shutdown UI
  /// before the synchronous VZ stop work begins. Idempotent.
  func beginShutdown() {
    guard !isShuttingDown else { return }
    isShuttingDown = true
  }

  // MARK: - Owned values

  let bundle: SharedCompassVMBundle

  private let dependencies: Dependencies
  @Published private(set) var virtualMachine: VZVirtualMachine?
  private var sleepObserver: SharedCompassVMSleepObserver?
  private var lastResolvedSSHDestination: String?

  /// Pipe attached to the guest's virtio console port. VZ writes guest serial
  /// output into `consoleOutputPipe.fileHandleForWriting`; the host's read
  /// task drains `consoleOutputPipe.fileHandleForReading`. The host keeps
  /// the pipe alive for the lifetime of the running VM so the buffer is
  /// never closed mid-read. The guest's first-boot script writes its IP as
  /// `COMPASS_GUEST_IP=<addr>\n` for IP discovery; other traffic is dropped.
  private var consoleOutputPipe: Pipe?
  private var consoleReadTask: Task<Void, Never>?

  /// Serializes concurrent `start()` calls so two simultaneous callers cannot
  /// each construct their own `VZVirtualMachine`.
  private var startInFlight: Task<Void, Error>?

  /// Serializes restore-image installation. `VZMacOSInstaller` mutates the
  /// bundle's disk image, auxiliary storage, and platform identity files; only
  /// one caller may touch that state at a time.
  private var provisionInFlight: Task<Void, Error>?

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
  private let fallbackUnavailableReason: String?

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

  /// Downloads the restore image (if needed) and runs `VZMacOSInstaller`.
  /// Pumps progress into `readiness`. Idempotent against re-invocation if
  /// install completed previously.
  func provisionIfNeeded(localIPSWURL: URL? = nil) async throws {
    if let existing = provisionInFlight {
      try await existing.value
      return
    }

    let task = Task { [weak self] () throws -> Void in
      guard let self else { return }
      try await self.performProvisionIfNeeded(localIPSWURL: localIPSWURL)
    }
    provisionInFlight = task
    defer { provisionInFlight = nil }
    try await task.value
  }

  private func performProvisionIfNeeded(localIPSWURL: URL? = nil) async throws {
    if let reason = fallbackUnavailableReason {
      transition(to: .unavailable(reason: reason))
      return
    }
    let availability = dependencies.availability()
    if case .unavailable(let reason) = availability {
      transition(to: .unavailable(reason: reason))
      return
    }

    // Ensure the bundle directory exists and the Compass-owned SSH keypair
    // is generated *before* we kick off the IPSW install. The public half
    // is later planted into the guest's `~/.ssh/authorized_keys` during
    // guest-prep, so it must exist by the time the guest is bootable.
    try bundle.ensureExists(fileManager: dependencies.fileManager)
    do {
      try bundle.ensureSSHKeypair(fileManager: dependencies.fileManager)
    } catch {
      transition(to: .error(detail: SharedCompassVMAvailabilityCheck.describe(error: error)))
      throw error
    }

    // If we already have a disk image and state says ready, skip.
    let state =
      (try? bundle.loadState(fileManager: dependencies.fileManager))
      ?? SharedCompassVMBundle.State()
    if bundle.existsOnDisk(fileManager: dependencies.fileManager), state.provisionStep == .ready {
      return
    }

    // Build progress streams + bridges before the long-running work hops off main.
    let (downloadSink, downloadStream) = SharedCompassVMImageInstaller.ProgressSink.makeStream()
    let (installSink, installStream) = SharedCompassVMImageInstaller.ProgressSink.makeStream()
    let progressTask = Task { [weak self] in
      for await fraction in downloadStream {
        self?.updateDownloadProgress(fraction)
      }
    }
    let installProgressTask = Task { [weak self] in
      for await fraction in installStream {
        self?.updateInstallProgress(fraction)
      }
    }
    defer {
      progressTask.cancel()
      installProgressTask.cancel()
    }

    if localIPSWURL != nil {
      try bundle.mutateState(fileManager: dependencies.fileManager) {
        $0.provisionStep = .installing
      }
      transition(to: .installing(fractionCompleted: 0))
    } else {
      try bundle.mutateState(fileManager: dependencies.fileManager) {
        $0.provisionStep = .downloadingIPSW
      }
      transition(to: .downloadingIPSW(fractionCompleted: 0))
    }

    let installReport: SharedCompassVMImageInstaller.InstallReport
    do {
      installReport = try await dependencies.imageInstaller.install(
        into: bundle,
        localIPSWURL: localIPSWURL,
        downloadProgress: downloadSink,
        installProgress: installSink,
        fileManager: dependencies.fileManager
      )
    } catch {
      transition(to: .error(detail: SharedCompassVMAvailabilityCheck.describeVerbose(error: error)))
      throw error
    }

    // Terminate the lingering `com.apple.Virtualization.Installation`
    // XPC helper before kicking off the headless plant. The helper
    // outlives `VZMacOSInstaller.install`'s success callback and
    // holds APFS-internal locks (not plain fds — `lsof` shows nothing)
    // on the just-installed Data volume, which makes host-side
    // `diskutil mount` fail with "Volume on diskNsM failed to mount
    // (code 1)" forever. The helper does NOT exit on its own — we
    // empirically observed it sitting at 0.0% CPU for 60+s with
    // locks held. Polite SIGTERM first, fallback to SIGKILL.
    // Safe because `install`'s success callback guarantees all
    // critical writes have flushed by the time we reach here.
    await Self.terminateInstallationHelper()

    // Headless first-boot: plant the LaunchDaemon, bootstrap script,
    // sudoers fragment, and supporting payload onto the just-installed
    // Data volume. Removes the need for the user to click through Setup
    // Assistant manually. Failure here is fatal — without the plant,
    // first boot would land at Setup Assistant with no compass user.
    do {
      try await plantHeadlessFirstBoot(installReport: installReport)
    } catch {
      transition(to: .error(detail: SharedCompassVMAvailabilityCheck.describeVerbose(error: error)))
      throw error
    }
    try bundle.mutateState(fileManager: dependencies.fileManager) {
      $0.provisionStep = .guestPrepping
      $0.guestOSVersion = installReport.buildVersion
    }
    transition(to: .guestPrepping)
  }

  /// Renders and plants the headless first-boot payload against the
  /// just-installed disk. The plant runs as root via one
  /// `osascript do shell script with administrator privileges` prompt;
  /// the user authenticates once per provisioning attempt and the
  /// remaining lifecycle is unattended.
  private func plantHeadlessFirstBoot(
    installReport: SharedCompassVMImageInstaller.InstallReport
  ) async throws {
    guard
      let profile = SharedCompassVMHeadlessFirstBoot.Registry.profile(
        forBuildVersion: installReport.buildVersion
      )
    else {
      throw NSError(
        domain: "SharedCompassVM",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Headless first-boot does not know how to handle macOS build \(installReport.buildVersion). Update SharedCompassVMHeadlessFirstBoot.Registry."
        ]
      )
    }

    // Allocate the Keychain credential (re-uses an existing entry if the
    // bundle already has an account string — survives re-provisions of
    // the same bundle without churning the user's keychain).
    var state =
      (try? bundle.loadState(fileManager: dependencies.fileManager))
      ?? SharedCompassVMBundle.State()
    let account: String
    if let existing = state.guestPasswordKeychainAccount {
      account = existing
    } else {
      account = SharedCompassVMGuestCredential.makeAccount()
      state.guestPasswordKeychainAccount = account
      try bundle.saveState(state, fileManager: dependencies.fileManager)
    }
    let credential = try SharedCompassVMGuestCredential.ensure(
      account: account,
      storage: dependencies.credentialStorage
    )

    // Read the Compass-owned SSH public key the bootstrap script will
    // authorise inside the guest. `ensureSSHKeypair` ran earlier in
    // provisionIfNeeded so the file is guaranteed to exist.
    let publicKeyData = try Data(contentsOf: bundle.publicKeyURL)

    // Locate the in-guest agent binary alongside the host executable
    // and load its bytes — the planter ships it onto the guest's
    // /usr/local/libexec/ so the LaunchAgent has something to launch.
    let guestAgentBinaryURL = try locateGuestAgentBinary()
    let guestAgentBinary = try Data(contentsOf: guestAgentBinaryURL)

    let payload = SharedCompassVMHeadlessFirstBoot.renderPayload(
      from: SharedCompassVMHeadlessFirstBoot.RenderInputs.makeStandard(
        profile: profile,
        publicKeyData: publicKeyData,
        generatedPassword: credential.password,
        guestAgentBinary: guestAgentBinary,
        guestUserName: state.guestUserName
      )
    )

    _ = try await dependencies.headlessPlanter.plant(
      payload: payload,
      diskImageURL: bundle.diskImageURL
    )
  }

  /// Returns the on-disk location of the `CompassGuestAgent` executable.
  /// SwiftPM places it as a sibling of the host binary in `.build/<config>/`;
  /// Xcode bundles it next to the host inside `Compass.app/Contents/MacOS/`.
  /// Both layouts put the agent in the same directory as Bundle.main's
  /// executable, so we walk a single set of candidates.
  private func locateGuestAgentBinary() throws -> URL {
    let executableName = "CompassGuestAgent"
    let bundle = Bundle.main
    var candidates: [URL] = []
    if let executable = bundle.executableURL {
      candidates.append(
        executable.deletingLastPathComponent().appendingPathComponent(executableName))
    }
    candidates.append(bundle.bundleURL.appendingPathComponent(executableName))
    candidates.append(bundle.bundleURL.appendingPathComponent("Contents/MacOS/\(executableName)"))
    for url in candidates where dependencies.fileManager.isExecutableFile(atPath: url.path) {
      return url
    }
    throw NSError(
      domain: "SharedCompassVM",
      code: 4,
      userInfo: [
        NSLocalizedDescriptionKey:
          "Could not locate CompassGuestAgent binary alongside the host. Searched: \(candidates.map(\.path).joined(separator: ", "))"
      ]
    )
  }

  /// Removes a failed or stale install so the next provisioning attempt starts
  /// from a clean disk/auxiliary-storage/platform set. The IPSW cache and
  /// Compass SSH keypair are preserved. The auto-generated guest password
  /// is wiped from the host Keychain so the next install issues a fresh
  /// credential instead of inheriting a stale one.
  func resetProvisioningArtifacts() async throws {
    if let existing = provisionInFlight {
      try await existing.value
    }
    await stop()
    // Read the prior state BEFORE wiping so we can clean up the keychain
    // entry that belonged to the install we're about to discard.
    let priorState = try? bundle.loadState(fileManager: dependencies.fileManager)
    if let priorAccount = priorState?.guestPasswordKeychainAccount {
      try? SharedCompassVMGuestCredential.remove(
        account: priorAccount,
        storage: dependencies.credentialStorage
      )
    }
    try bundle.resetInstalledArtifacts(fileManager: dependencies.fileManager)
    persistedState = try? bundle.loadState(fileManager: dependencies.fileManager)
    lastResolvedSSHDestination = nil
    setupFailureMessage = nil
    transition(to: .notProvisioned)
  }

  /// Destructive recovery path for failed installs: clear partial artifacts,
  /// then provision and boot using either the supplied local IPSW or the
  /// standard catalog/download path.
  func rebuild(localIPSWURL: URL? = nil) async throws {
    try await resetProvisioningArtifacts()
    try await provisionIfNeeded(localIPSWURL: localIPSWURL)
    try await start()
  }

  /// Boots (or re-boots) the guest from the currently-installed bundle.
  /// Caller is responsible for first calling `provisionIfNeeded` if the
  /// bundle is empty. Idempotent if the VM is already running.
  ///
  /// Concurrent calls share a single in-flight start so two callers cannot
  /// race to construct two VZVirtualMachine instances.
  func start() async throws {
    if fallbackUnavailableReason != nil { return }
    if let virtualMachine, virtualMachine.state == .running {
      return
    }
    if let existing = startInFlight {
      try await existing.value
      return
    }

    let task = Task { [weak self] () -> Void in
      guard let self else { return }
      try await self.performStart()
    }
    startInFlight = task
    defer { startInFlight = nil }
    do {
      try await task.value
    } catch {
      transition(to: .error(detail: SharedCompassVMAvailabilityCheck.describeVerbose(error: error)))
      throw error
    }
  }

  private func performStart() async throws {
    if let virtualMachine, virtualMachine.state == .running {
      return
    }

    // Generate (or load) a stable MAC for the guest NIC so host-side
    // IP discovery can find this guest across host reboots.
    let macAddress = try? bundle.ensureGuestMACAddress(fileManager: dependencies.fileManager)

    // Compose configuration from on-disk artifacts.
    let inputs = SharedCompassVMConfiguration.Inputs.standard(
      bundle: bundle,
      guestMACAddress: macAddress
    )
    let configuration = try SharedCompassVMConfiguration.makeConfiguration(
      for: inputs,
      fileManager: dependencies.fileManager
    )

    // Attach a host-owned Pipe to the virtio console so first-boot guest
    // scripts can publish `COMPASS_GUEST_IP=<addr>` lines back to us.
    // The hook stays live for the full VM lifetime; the read task drops
    // anything that doesn't match the known prefix.
    attachConsolePipe(to: configuration)

    do {
      try configuration.validate()
    } catch {
      tearDownConsolePipe()
      throw error
    }

    let machine = VZVirtualMachine(configuration: configuration)
    self.virtualMachine = machine

    do {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        machine.start { result in
          switch result {
          case .success:
            continuation.resume(returning: ())
          case .failure(let error):
            continuation.resume(throwing: error)
          }
        }
      }
    } catch {
      self.virtualMachine = nil
      tearDownConsolePipe()
      throw error
    }

    // Headless first-boot follow-up: if we just booted a freshly-planted
    // guest, the LaunchDaemon will spend ~30-60s creating the user,
    // authorising the SSH key, and enabling Remote Login. Kick off a
    // background poller that finalises readiness once SSH responds,
    // so the user never needs to click "Mark setup complete".
    //
    // For subsequent boots (state is already .ready on disk), `warmup()`
    // has held the in-memory readiness at `.guestPrepping`. Probe SSH
    // until the guest's sshd answers, then flip the in-memory state to
    // `.ready` — without touching the persisted state machine.
    let postStartStep = (try? bundle.loadState(fileManager: dependencies.fileManager))?
      .provisionStep
    switch postStartStep {
    case .guestPrepping:
      Task { [weak self] in
        await self?.pollUntilHeadlessGuestReady()
      }
    case .provisioningDevTools:
      // Host crashed (or VM was stopped) mid-CLT-install. Resume
      // where we left off — the provisioner's probe short-circuits
      // when CLT happens to have finished out-of-band, and otherwise
      // re-issues the plant + kickoff (which softwareupdate handles
      // idempotently).
      Task { [weak self] in
        await self?.resumeDevToolsProvisioningAfterBoot()
      }
    case .ready:
      Task { [weak self] in
        await self?.pollSSHAfterBootAndMarkReady()
      }
    default:
      break
    }
  }

  /// Re-enters the dev-tools install path after a fresh boot of a bundle
  /// that was persisted at `.provisioningDevTools`. Mirrors the SSH-probe
  /// leg of `markSetupComplete` (so the live destination is re-resolved),
  /// then hands off to `runDevToolsProvisioner`.
  private func resumeDevToolsProvisioningAfterBoot() async {
    let state =
      (try? bundle.loadState(fileManager: dependencies.fileManager))
      ?? SharedCompassVMBundle.State()
    guard let ip = state.lastKnownGoodIP else {
      transition(to: .error(
        detail: "Resuming dev-tools install: guest IP is not cached. Reset and re-provision."))
      return
    }
    let destination = "\(state.guestUserName)@\(ip)"
    let options = SharedCompassVMGuestBridge.ConnectionOptions(
      identityFile: bundle.privateKeyURL.path,
      knownHostsFile: bundle.knownHostsURL.path,
      connectTimeoutSeconds: 5
    )
    let deadline = Date().addingTimeInterval(300)
    var attemptIntervalNanoseconds: UInt64 = 2_000_000_000
    var probeOK = false
    while Date() < deadline {
      probeOK = await SharedCompassVMGuestBridge.probeSSHAvailable(
        destination: destination,
        options: options,
        timeout: 5
      )
      if probeOK { break }
      try? await Task.sleep(nanoseconds: attemptIntervalNanoseconds)
      attemptIntervalNanoseconds = min(attemptIntervalNanoseconds * 2, 10_000_000_000)
    }
    guard probeOK else {
      transition(to: .error(
        detail: "Resuming dev-tools install: SSH probe to \(destination) timed out."))
      return
    }
    lastResolvedSSHDestination = destination
    transition(to: .provisioningDevTools(fractionCompleted: 0))
    await runDevToolsProvisioner(destination: destination)
  }

  /// Lightweight SSH probe used on subsequent boots when the bundle is
  /// already past first-boot setup. Unlike `pollUntilHeadlessGuestReady`,
  /// this does not mutate persisted state — it only flips the in-memory
  /// readiness to `.ready` once the guest's sshd answers, so the UI
  /// reflects "actually reachable" rather than "previously was reachable".
  private func pollSSHAfterBootAndMarkReady() async {
    let state =
      (try? bundle.loadState(fileManager: dependencies.fileManager))
      ?? SharedCompassVMBundle.State()
    guard let ip = state.lastKnownGoodIP else { return }
    let destination = "\(state.guestUserName)@\(ip)"
    let options = SharedCompassVMGuestBridge.ConnectionOptions(
      identityFile: bundle.privateKeyURL.path,
      knownHostsFile: bundle.knownHostsURL.path,
      connectTimeoutSeconds: 5
    )
    let deadline = Date().addingTimeInterval(300)  // 5 minutes
    var attemptIntervalNanoseconds: UInt64 = 2_000_000_000
    while Date() < deadline {
      let probeOK = await SharedCompassVMGuestBridge.probeSSHAvailable(
        destination: destination,
        options: options,
        timeout: 5
      )
      if probeOK {
        lastResolvedSSHDestination = destination
        await ensureMutationToolsIfNeeded()
        transition(to: .ready(sshDestination: destination))
        return
      }
      try? await Task.sleep(nanoseconds: attemptIntervalNanoseconds)
      // Backoff capped at 10s so the UI doesn't stall after a slow
      // first probe but we still avoid hammering sshd during the boot.
      attemptIntervalNanoseconds = min(attemptIntervalNanoseconds * 2, 10_000_000_000)
    }
  }

  /// Background driver that repeatedly invokes `markSetupComplete()` until
  /// the readiness probe lands on `.ready`, or the overall deadline
  /// expires. Used as the auto-finalisation step after a headless
  /// first-boot plant, where Compass owns the entire boot sequence and
  /// there is nothing for the user to click.
  private func pollUntilHeadlessGuestReady() async {
    let deadline = Date().addingTimeInterval(300)  // 5 minutes
    var attemptIntervalNanoseconds: UInt64 = 5_000_000_000
    while Date() < deadline {
      await markSetupComplete()
      // SSH-probe loop exits as soon as `markSetupComplete` has either
      // landed at .ready or advanced past SSH onto the dev-tools
      // install — beyond that point the provisioner owns the
      // readiness signal and we must not re-invoke setup or we'd
      // race ourselves into multiple concurrent installs.
      if case .ready = readiness { return }
      if case .provisioningDevTools = readiness { return }
      if case .error = readiness { return }
      try? await Task.sleep(nanoseconds: attemptIntervalNanoseconds)
      // Exponential backoff capped at 20s so we don't hammer ssh
      // during the long tail of slow first boots.
      attemptIntervalNanoseconds = min(attemptIntervalNanoseconds * 2, 20_000_000_000)
    }
  }

  /// Pauses the live VM. No-op if no VM is running.
  func pause() {
    guard let machine = virtualMachine, machine.state == .running else { return }
    machine.pause { _ in
      // Result is intentionally ignored — failure to pause is logged at the
      // call site but does not block the host going to sleep.
    }
  }

  /// Resumes the paused VM. No-op if no VM is paused.
  func resume() {
    guard let machine = virtualMachine, machine.state == .paused else { return }
    machine.resume { _ in
      // Ditto pause — wake propagation must not block.
    }
  }

  /// Stops the VM, preferring a graceful guest-driven shutdown over the
  /// forced VZ halt. `requestStop()` sends an ACPI/shutdown signal so macOS
  /// in the guest can flush APFS, terminate services, and halt cleanly;
  /// without it every quit pulls the power cord and the guest accumulates
  /// dirty-bit warnings on the next boot. If the guest does not power down
  /// within a bounded window, we fall back to the forced halt so the host
  /// app still terminates within the AppDelegate's 6s budget.
  func stop() async {
    // Capture the live SSH destination (if any) before we tear the VM
    // down so we can ask any backgrounded SSH control master to exit.
    // Without this teardown, `ControlPersist` leaves the master alive
    // for minutes after the VM is gone, leaking a ssh process and
    // re-establishing dead connections on the next agent call.
    let liveSSHDestination: String?
    if case .ready(let destination) = readiness {
      liveSSHDestination = destination
    } else {
      liveSSHDestination = nil
    }

    defer {
      if let destination = liveSSHDestination {
        let options = SharedCompassVMGuestBridge.ConnectionOptions(
          identityFile: bundle.privateKeyURL.path,
          knownHostsFile: bundle.knownHostsURL.path
        )
        Task.detached {
          await SharedCompassVMGuestBridge.closeControlMaster(
            destination: destination,
            options: options
          )
        }
      }
    }

    guard let machine = virtualMachine else { return }
    if machine.state == .stopped {
      virtualMachine = nil
      tearDownConsolePipe()
      return
    }

    // Phase 1: graceful shutdown. Only valid when the VM is actually
    // running — paused / stopping / starting states reject the request
    // and we'll fall through to the forced halt.
    if machine.state == .running {
      do {
        try machine.requestStop()
      } catch {
        // requestStop throws if VZ refuses the request. Not fatal —
        // we still try the forced halt below.
      }
      // Poll for up to ~4s. A macOS guest typically halts in 2-3s; the
      // 4s ceiling keeps total stop time within the AppDelegate's 6s
      // budget (4s graceful + ≤1s forced fallback + overhead).
      let deadline = Date().addingTimeInterval(4)
      while Date() < deadline, machine.state != .stopped {
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
      }
    }

    // Phase 2: forced halt. Reached when the graceful path was skipped
    // (wrong state), rejected by VZ, or the guest didn't power down in
    // time. Equivalent to pulling the power cord — use only as a last
    // resort.
    if machine.state != .stopped {
      do {
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, Error>) in
          machine.stop { error in
            if let error {
              continuation.resume(throwing: error)
            } else {
              continuation.resume(returning: ())
            }
          }
        }
      } catch {
        // Stop failures are non-fatal; the VM may already be halted.
      }
    }

    virtualMachine = nil
    tearDownConsolePipe()
  }

  /// Marks the user-driven first-boot Setup Assistant as complete.
  /// Transitions readiness to `.guestPrepping` and then to
  /// `.provisioningDevTools` once the SSH probe succeeds, kicking off
  /// the headless CLT install before finally flipping to `.ready`. The
  /// Sandbox view invokes this when the user taps "Mark setup complete";
  /// the headless first-boot driver calls it repeatedly until readiness
  /// leaves `.guestPrepping`.
  func markSetupComplete() async {
    // Clear any prior failure message so the UI shows a fresh attempt.
    setupFailureMessage = nil
    transition(to: .guestPrepping)
    _ = try? bundle.mutateState(fileManager: dependencies.fileManager) {
      $0.provisionStep = .guestPrepping
    }

    var state =
      (try? bundle.loadState(fileManager: dependencies.fileManager))
      ?? SharedCompassVMBundle.State()

    // Resolve guest IP via dhcpd_leases/arp using the pinned MAC if
    // we don't already have one cached. Without this, the readiness
    // pipeline would stall here permanently.
    if state.lastKnownGoodIP == nil, let mac = state.guestMACAddress {
      if let discovered = await SharedCompassVMGuestIPDiscovery.waitForGuestIP(
        macAddress: mac,
        timeout: 60,
        pollInterval: 2
      ) {
        state.lastKnownGoodIP = discovered.ip
        _ = try? bundle.mutateState(fileManager: dependencies.fileManager) {
          $0.lastKnownGoodIP = discovered.ip
        }
      }
    }

    guard let ip = state.lastKnownGoodIP else {
      setupFailureMessage =
        "Could not discover the guest IP. Make sure the VM has finished booting and that the guest has a DHCP lease, then try again."
      return
    }
    let destination = "\(state.guestUserName)@\(ip)"
    let options = SharedCompassVMGuestBridge.ConnectionOptions(
      identityFile: bundle.privateKeyURL.path,
      knownHostsFile: bundle.knownHostsURL.path,
      connectTimeoutSeconds: 5
    )

    // Bootstrap known_hosts via ssh-keyscan before the strict probe.
    // The probe runs with StrictHostKeyChecking=yes and refuses to
    // talk to a host whose key isn't in known_hosts; on a fresh
    // provision that's always the case and the probe would loop
    // forever even with sshd up and authorised. ssh-keyscan TOFU-
    // trusts the freshly-generated host key. Safe because the guest
    // is on a host-local NAT bridge.
    _ = await SharedCompassVMGuestBridge.populateKnownHosts(
      host: ip,
      knownHostsFile: bundle.knownHostsURL.path,
      timeout: 5
    )

    let probeOK = await SharedCompassVMGuestBridge.probeSSHAvailable(
      destination: destination,
      options: options,
      timeout: 5
    )
    guard probeOK else {
      setupFailureMessage =
        "SSH probe to \(destination) failed. Confirm the bootstrap script ran successfully inside the guest (sshd enabled, key authorised)."
      return
    }
    lastResolvedSSHDestination = destination

    // SSH is up — promote to .provisioningDevTools and kick off the
    // in-guest CLT install. We persist this step too so a host crash
    // mid-install resumes here on the next launch rather than thinking
    // the bundle is ready when CLT was never finished.
    _ = try? bundle.mutateState(fileManager: dependencies.fileManager) {
      $0.provisionStep = .provisioningDevTools
    }
    transition(to: .provisioningDevTools(fractionCompleted: 0))

    await runDevToolsProvisioner(destination: destination)
  }

  /// Drives `SharedCompassVMDevToolsProvisioner` and
  /// `SharedCompassVMMutationToolsProvisioner` against the live VM using a
  /// vsock-backed bash runner. Updates readiness with progress while each
  /// install runs, and flips to `.ready` once CLT and Muter verify.
  /// Safe to call when tools are already installed — each provisioner's
  /// probe short-circuits and `progress(1)` fires immediately.
  private func runDevToolsProvisioner(destination: String) async {
    guard let machine = virtualMachine else {
      transition(to: .error(detail: "Shared VM is not running; cannot install developer tools."))
      return
    }
    let client = Self.makeVsockClient(on: machine)
    let host = self
    do {
      _ = try await SharedCompassVMDevToolsProvisioner.provision(
        runner: client,
        progress: { fraction in
          await MainActor.run {
            host.transition(to: .provisioningDevTools(fractionCompleted: fraction * 0.85))
          }
        }
      )
    } catch {
      transition(to: .error(detail: "Developer-tools install failed: \(error)"))
      return
    }

    do {
      _ = try await SharedCompassVMMutationToolsProvisioner.provision(
        runner: client,
        progress: { fraction in
          await MainActor.run {
            host.transition(to: .provisioningDevTools(fractionCompleted: 0.85 + fraction * 0.15))
          }
        }
      )
    } catch {
      transition(to: .error(detail: "Mutation-tools install failed: \(error)"))
      return
    }

    _ = try? bundle.mutateState(fileManager: dependencies.fileManager) {
      $0.provisionStep = .ready
    }
    transition(to: .ready(sshDestination: destination))
  }

  /// Backfills Muter on guests that were provisioned before mutation-tool
  /// install was added. Failures are non-fatal — the VM still becomes ready
  /// and auto mutation testing skips when the runner is missing.
  private func ensureMutationToolsIfNeeded() async {
    guard let machine = virtualMachine else { return }
    let client = Self.makeVsockClient(on: machine)
    do {
      if try await SharedCompassVMMutationToolsProvisioner.probeAlreadyInstalled(runner: client) {
        return
      }
    } catch {
      return
    }

    transition(to: .provisioningDevTools(fractionCompleted: 0.85))
    do {
      _ = try await SharedCompassVMMutationToolsProvisioner.provision(
        runner: client,
        progress: { fraction in
          await MainActor.run {
            self.transition(to: .provisioningDevTools(fractionCompleted: 0.85 + fraction * 0.15))
          }
        }
      )
    } catch {
      // Non-fatal: older guests can still run Develop/Verify; mutation
      // auto-loop treats a missing runner as a skip until reprovision.
    }
  }

  /// Builds a vsock-backed agent client that opens a fresh
  /// `VZVirtioSocketConnection` per RPC against the supplied VM.
  ///
  /// This is the canonical factory for the in-guest RPC client. Callers
  /// (Develop loops, worktree sync, dev-tools provisioner) go through
  /// it so the connect-and-write path stays in one place — anything
  /// outside SharedVM should treat the returned value as an
  /// `AgentFilesystem & AgentBashRunner` pair, not as a vsock-specific
  /// type.
  static func makeVsockClient(on machine: VZVirtualMachine) -> AgentVsockClient {
    AgentVsockClient(
      transportFactory: {
        let connection = try await SharedCompassVMVsock.connect(on: machine)
        return VZVirtioSocketTransport(connection: connection)
      }
    )
  }

  /// Convenience facade for non-VM callers (AppModel, executor wiring)
  /// that need the host-or-guest filesystem + bash pair but don't want
  /// to know whether the run will route through the VM.
  ///
  /// - When `vmMachine` is nil, returns the host-direct implementations.
  /// - When `vmMachine` is non-nil, returns a single `AgentVsockClient`
  ///   that conforms to both protocols and shells every operation over
  ///   vsock to the in-guest agent.
  static func agentTransport(
    vmMachine: VZVirtualMachine?
  ) -> (filesystem: AgentFilesystem, bashRunner: AgentBashRunner) {
    if let machine = vmMachine {
      let client = makeVsockClient(on: machine)
      return (client, client)
    }
    return (AgentHostFilesystem(), AgentHostBashRunner())
  }

  // MARK: - Internals

  private func installSleepObserver() {
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

  private func updateDownloadProgress(_ fraction: Double) {
    if case .downloadingIPSW = readiness {
      transition(to: .downloadingIPSW(fractionCompleted: fraction))
    } else if readiness == .notProvisioned {
      transition(to: .downloadingIPSW(fractionCompleted: fraction))
    }
    if fraction >= 1.0 {
      _ = try? bundle.mutateState(fileManager: dependencies.fileManager) {
        $0.provisionStep = .installing
      }
      transition(to: .installing(fractionCompleted: 0))
    }
  }

  private func updateInstallProgress(_ fraction: Double) {
    transition(to: .installing(fractionCompleted: fraction))
  }

  // MARK: - Console pipe (guest IP discovery)

  /// Wires a host-owned `Pipe()` to the virtio console device.
  ///
  /// Per Apple's docs / sample (see `Running Linux in a Virtual Machine`):
  /// `fileHandleForReading` is what VZ reads from (host→guest input) and
  /// `fileHandleForWriting` is what VZ writes guest output to. To capture
  /// guest output only, leave the read side nil and pass the write end of
  /// our pipe for the write side, then read from the matching read end.
  ///
  /// IP discovery itself runs host-side via dhcpd_leases / `arp -an`
  /// keyed on the guest's pinned MAC (`SharedCompassVMGuestIPDiscovery`),
  /// so the guest does not need a serial-reporting agent. The pipe stays
  /// wired so future guest-side telemetry has a place to land; any line
  /// matching `COMPASS_GUEST_IP=<addr>` is still treated as authoritative.
  private func attachConsolePipe(to configuration: VZVirtualMachineConfiguration) {
    let pipe = Pipe()
    let attachment = VZFileHandleSerialPortAttachment(
      fileHandleForReading: nil,
      fileHandleForWriting: pipe.fileHandleForWriting
    )
    do {
      try SharedCompassVMConfiguration.replaceConsoleAttachment(attachment, on: configuration)
    } catch {
      // No console device on this configuration — bail without retaining
      // the pipe. Nothing else relies on it being live.
      return
    }
    self.consoleOutputPipe = pipe

    let readHandle = pipe.fileHandleForReading
    consoleReadTask = Task.detached { [weak self] in
      var buffer = ""
      while !Task.isCancelled {
        let data = readHandle.availableData
        if data.isEmpty {
          // The far side closed; the VM has likely stopped.
          break
        }
        if let chunk = String(data: data, encoding: .utf8) {
          buffer += chunk
          while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[..<newlineRange.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
            await Self.handleConsoleLine(line, host: self)
          }
        }
      }
    }
  }

  private func tearDownConsolePipe() {
    consoleReadTask?.cancel()
    consoleReadTask = nil
    if let pipe = consoleOutputPipe {
      try? pipe.fileHandleForReading.close()
      try? pipe.fileHandleForWriting.close()
    }
    consoleOutputPipe = nil
  }

  @MainActor
  private static func handleConsoleLine(_ line: String, host: SharedCompassVM?) async {
    guard let host else { return }
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("COMPASS_GUEST_IP=") else { return }
    let ip = String(trimmed.dropFirst("COMPASS_GUEST_IP=".count))
    guard !ip.isEmpty else { return }
    _ = try? host.bundle.mutateState(fileManager: host.dependencies.fileManager) {
      $0.lastKnownGoodIP = ip
    }
  }

  /// Reaps every live `com.apple.Virtualization.Installation` XPC
  /// helper process so the just-installed disk image's APFS locks are
  /// released. The helper does not exit on its own after install
  /// completion — it sits idle holding container-level locks that
  /// block host-side `diskutil mount` calls indefinitely.
  ///
  /// Two-phase: SIGTERM first with a 3-second grace window for orderly
  /// shutdown, then SIGKILL anything that's still alive. Idempotent —
  /// safe to call when no helper is alive (pgrep returns no PIDs and
  /// the loops are no-ops).
  static func terminateInstallationHelper() async {
    let pids = installationHelperPIDs()
    guard !pids.isEmpty else { return }
    for pid in pids {
      _ = kill(pid, SIGTERM)
    }
    // Brief poll for graceful exit before escalating.
    let graceDeadline = Date().addingTimeInterval(3)
    while Date() < graceDeadline {
      if installationHelperPIDs().isEmpty { return }
      try? await Task.sleep(nanoseconds: 200_000_000)
    }
    // Stragglers — SIGKILL.
    for pid in installationHelperPIDs() {
      _ = kill(pid, SIGKILL)
    }
    // Final brief settle so subsequent `hdiutil attach` doesn't race
    // the kernel's APFS-container teardown for the killed helper.
    try? await Task.sleep(nanoseconds: 500_000_000)
  }

  /// Returns the PIDs of every live `com.apple.Virtualization.Installation`
  /// XPC helper. Empty array when none are alive.
  private static func installationHelperPIDs() -> [pid_t] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-f", "com.apple.Virtualization.Installation"]
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return []
    }
    guard
      let data = try? stdout.fileHandleForReading.readToEnd(),
      let text = String(data: data, encoding: .utf8)
    else {
      return []
    }
    return
      text
      .split(whereSeparator: { $0.isNewline || $0.isWhitespace })
      .compactMap { pid_t($0) }
  }
}
