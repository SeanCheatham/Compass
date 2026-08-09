import Darwin
import Foundation

@MainActor
extension SharedCompassVM {
  /// Downloads the restore image (if needed) and runs `VZMacOSInstaller`.
  /// Pumps progress into `readiness`. Idempotent against re-invocation if
  /// install completed previously.
  public func provisionIfNeeded(localIPSWURL: URL? = nil) async throws {
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
    if bundle.existsOnDisk(fileManager: dependencies.fileManager) {
      switch state.provisionStep {
      case .ready, .guestPrepping, .provisioningDevTools:
        // Past the install phase — re-running VZMacOSInstaller would
        // wipe a healthy guest over a recoverable dev-tools failure.
        // Return here and let `start()` resume first-boot / dev-tools
        // provisioning from the persisted step.
        return
      case .notProvisioned, .downloadingIPSW, .installing:
        break
      }
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
      let diskSize = preferredDiskCapacityBytes
      installReport = try await dependencies.imageInstaller.install(
        into: bundle,
        localIPSWURL: localIPSWURL,
        diskSizeInBytes: diskSize,
        downloadProgress: downloadSink,
        installProgress: installSink,
        fileManager: dependencies.fileManager
      )
      try bundle.mutateState(fileManager: dependencies.fileManager) {
        $0.lastBundleSize = diskSize
      }
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
    // /usr/local/libexec/ so the LaunchDaemon has something to launch.
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
  public func resetProvisioningArtifacts() async throws {
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
    stopDiagnosticLogTail()
    clearDiagnostics()
    transition(to: .notProvisioned)
  }

  /// Destructive recovery path for failed installs: clear partial artifacts,
  /// then provision and boot using either the supplied local IPSW or the
  /// standard catalog/download path.
  public func rebuild(localIPSWURL: URL? = nil) async throws {
    try await resetProvisioningArtifacts()
    try await provisionIfNeeded(localIPSWURL: localIPSWURL)
    try await start()
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
  /// XPC helper. Empty array when none are alive. Candidates from pgrep are
  /// cross-checked against their executable path so an unrelated process
  /// whose command line merely mentions the helper name is never killed.
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
      .filter { pid in
        guard let executable = executablePath(of: pid) else { return false }
        return executable.hasSuffix("com.apple.Virtualization.Installation")
      }
  }

  /// Resolves a PID's executable path via `ps -o comm=`. Nil on failure.
  private static func executablePath(of pid: pid_t) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-p", String(pid), "-o", "comm="]
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return nil
    }
    guard
      let data = try? stdout.fileHandleForReading.readToEnd(),
      let text = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
