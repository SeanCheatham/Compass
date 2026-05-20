import AppKit
import Combine
import Foundation
import SwiftUI
import Virtualization

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

    /// Snapshot of the most recent persisted state document. Updated whenever
    /// `readiness` is recomputed from disk.
    @Published private(set) var persistedState: SharedCompassVMBundle.State?

    /// Transient diagnostic about the most-recent `markSetupComplete()` call.
    /// Cleared on the next invocation. Surfacing this in the UI lets the user
    /// tell a "still working on it" attempt apart from a "IP discovery
    /// failed, sshd is probably off" attempt without leaving the readiness
    /// state machine in the absorbing `.error(detail:)` state.
    @Published private(set) var setupFailureMessage: String?

    // MARK: - Owned values

    let bundle: SharedCompassVMBundle

    /// Host-side root that backs the `compass-workspaces` VirtioFS device.
    /// Worktrees for individual Develop iterations are subdirectories of this.
    let workspacesRootURL: URL

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
                bundle: SharedCompassVMBundle(rootURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("compass-shared-vm-fallback", isDirectory: true)),
                workspacesRootURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("compass-shared-vm-workspaces", isDirectory: true),
                fallbackUnavailableReason: "Shared VM bundle could not be initialised: \(detail)"
            )
        }
    }()

    // MARK: - Dependencies (injection seam)

    struct Dependencies {
        var imageInstaller: SharedCompassVMImageInstaller
        var fileManager: FileManager
        var availability: @MainActor () -> SharedCompassVMAvailability

        static func live() -> Dependencies {
            Dependencies(
                imageInstaller: SharedCompassVMImageInstaller(),
                fileManager: .default,
                availability: { SharedCompassVMAvailabilityCheck.evaluate() }
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
        workspacesRootURL: URL,
        dependencies: Dependencies = .live(),
        fallbackUnavailableReason: String? = nil
    ) {
        self.bundle = bundle
        self.workspacesRootURL = workspacesRootURL.standardizedFileURL
        self.dependencies = dependencies
        self.fallbackUnavailableReason = fallbackUnavailableReason
        if let reason = fallbackUnavailableReason {
            readiness = .unavailable(reason: reason)
        }
        installSleepObserver()
    }

    /// Convenience constructor that wires the canonical bundle location and
    /// the canonical worktree root (`~/Library/Caches/Compass/Worktrees/`).
    static func makeDefault() throws -> SharedCompassVM {
        let bundle = try SharedCompassVMBundle.defaultBundle()
        let fileManager = FileManager.default
        let cachesRoot = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let worktreesRoot = cachesRoot
            .appendingPathComponent("Compass", isDirectory: true)
            .appendingPathComponent("Worktrees", isDirectory: true)
        try fileManager.createDirectory(at: worktreesRoot, withIntermediateDirectories: true)
        return SharedCompassVM(bundle: bundle, workspacesRootURL: worktreesRoot)
    }

    // MARK: - Lifecycle

    /// Quick "is the host capable + is anything cached?" check. Does NOT start
    /// the VM. Safe to call from `AppModel.bootstrap`.
    func warmup() async throws {
        if let reason = fallbackUnavailableReason {
            readiness = .unavailable(reason: reason)
            return
        }
        let availability = dependencies.availability()
        if case .unavailable(let reason) = availability {
            readiness = .unavailable(reason: reason)
            return
        }

        try bundle.ensureExists(fileManager: dependencies.fileManager)
        let state = (try? bundle.loadState(fileManager: dependencies.fileManager)) ?? SharedCompassVMBundle.State()
        persistedState = state

        if bundle.existsOnDisk(fileManager: dependencies.fileManager) {
            switch state.provisionStep {
            case .ready where state.codexLoginCompleted:
                if let ip = state.lastKnownGoodIP {
                    let destination = "\(state.guestUserName)@\(ip)"
                    lastResolvedSSHDestination = destination
                    readiness = .ready(sshDestination: destination)
                } else {
                    readiness = .guestPrepping
                }
            case .ready:
                readiness = .codexLoginPending
            case .firstBootPending:
                readiness = .firstBootPending
            case .guestPrepping:
                readiness = .guestPrepping
            case .installing:
                readiness = .installing(fractionCompleted: 0)
            case .downloadingIPSW:
                readiness = .downloadingIPSW(fractionCompleted: 0)
            case .notProvisioned:
                readiness = .notProvisioned
            }
        } else {
            readiness = .notProvisioned
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
            readiness = .unavailable(reason: reason)
            return
        }
        let availability = dependencies.availability()
        if case .unavailable(let reason) = availability {
            readiness = .unavailable(reason: reason)
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
            readiness = .error(detail: SharedCompassVMAvailabilityCheck.describe(error: error))
            throw error
        }

        // If we already have a disk image and state says ready, skip.
        let state = (try? bundle.loadState(fileManager: dependencies.fileManager)) ?? SharedCompassVMBundle.State()
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
            readiness = .installing(fractionCompleted: 0)
        } else {
            try bundle.mutateState(fileManager: dependencies.fileManager) {
                $0.provisionStep = .downloadingIPSW
            }
            readiness = .downloadingIPSW(fractionCompleted: 0)
        }

        do {
            try await dependencies.imageInstaller.install(
                into: bundle,
                localIPSWURL: localIPSWURL,
                downloadProgress: downloadSink,
                installProgress: installSink,
                fileManager: dependencies.fileManager
            )
        } catch {
            readiness = .error(detail: SharedCompassVMAvailabilityCheck.describeVerbose(error: error))
            throw error
        }

        try bundle.mutateState(fileManager: dependencies.fileManager) {
            $0.provisionStep = .firstBootPending
        }
        // Drop the bootstrap script + public key into the VirtioFS share so
        // the user can run it from Terminal.app on first boot. The codex
        // binary is staged separately by `refreshFirstBootArtifacts`
        // (AppModel calls in with the user-facing codexBinary path so the
        // script can include the codex copy step).
        refreshFirstBootArtifacts(codexBinaryPath: nil)
        readiness = .firstBootPending
    }

    /// Removes a failed or stale install so the next provisioning attempt starts
    /// from a clean disk/auxiliary-storage/platform set. The IPSW cache and
    /// Compass SSH keypair are preserved.
    func resetProvisioningArtifacts() async throws {
        if let existing = provisionInFlight {
            try await existing.value
        }
        await stop()
        try bundle.resetInstalledArtifacts(fileManager: dependencies.fileManager)
        persistedState = try? bundle.loadState(fileManager: dependencies.fileManager)
        lastResolvedSSHDestination = nil
        setupFailureMessage = nil
        readiness = .notProvisioned
    }

    /// Destructive recovery path for failed installs: clear partial artifacts,
    /// then provision and boot using either the supplied local IPSW or the
    /// standard catalog/download path.
    func rebuild(localIPSWURL: URL? = nil) async throws {
        try await resetProvisioningArtifacts()
        try await provisionIfNeeded(localIPSWURL: localIPSWURL)
        try await start()
    }

    /// Re-materializes the first-boot script + public key + codex copy.
    /// Safe to call at any time; the script is idempotent so callers can
    /// re-invoke when the user changes the codex binary or after a fresh
    /// install. Best-effort: failures are swallowed because the readiness
    /// state machine is unaffected and the user will see a clear error
    /// inside the guest if the artifacts are missing.
    func refreshFirstBootArtifacts(codexBinaryPath: String?) {
        _ = try? SharedCompassVMFirstBootScript.materialize(
            workspacesRootURL: workspacesRootURL,
            publicKeyURL: bundle.publicKeyURL,
            codexBinaryPath: codexBinaryPath,
            fileManager: dependencies.fileManager
        )
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
            readiness = .error(detail: SharedCompassVMAvailabilityCheck.describeVerbose(error: error))
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
            workspacesRootURL: workspacesRootURL,
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

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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
            tearDownConsolePipe()
            throw error
        }

        self.virtualMachine = machine
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

    /// Requests a graceful stop. Awaits stop completion.
    func stop() async {
        guard let machine = virtualMachine else { return }
        if machine.state == .stopped {
            virtualMachine = nil
            tearDownConsolePipe()
            return
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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
        virtualMachine = nil
        tearDownConsolePipe()
    }

    /// Marks the user-driven first-boot Setup Assistant as complete.
    /// Transitions readiness to `.guestPrepping` and then to `.ready` once
    /// the SSH probe succeeds. The Sandbox view invokes this when the user
    /// taps "Mark setup complete".
    func markSetupComplete() async {
        // Clear any prior failure message so the UI shows a fresh attempt.
        setupFailureMessage = nil
        readiness = .guestPrepping
        _ = try? bundle.mutateState(fileManager: dependencies.fileManager) {
            $0.provisionStep = .guestPrepping
        }

        var state = (try? bundle.loadState(fileManager: dependencies.fileManager)) ?? SharedCompassVMBundle.State()

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
            setupFailureMessage = "Could not discover the guest IP. Make sure the VM has finished booting and that the guest has a DHCP lease, then try again."
            return
        }
        let destination = "\(state.guestUserName)@\(ip)"
        let options = SharedCompassVMGuestBridge.ConnectionOptions(
            identityFile: bundle.privateKeyURL.path,
            knownHostsFile: bundle.knownHostsURL.path,
            connectTimeoutSeconds: 5
        )
        let probeOK = await SharedCompassVMGuestBridge.probeSSHAvailable(
            destination: destination,
            options: options,
            timeout: 5
        )
        guard probeOK else {
            setupFailureMessage = "SSH probe to \(destination) failed. Confirm the bootstrap script ran successfully inside the guest (sshd enabled, key authorised)."
            return
        }
        _ = try? bundle.mutateState(fileManager: dependencies.fileManager) {
            $0.provisionStep = .ready
        }
        lastResolvedSSHDestination = destination
        if state.codexLoginCompleted {
            readiness = .ready(sshDestination: destination)
            return
        }

        // First-run codex auth: probe the guest, fall back to copying the
        // host's ~/.codex if the guest is unauthenticated. Lands at .ready
        // on success or .codexLoginPending (with a clear failure message)
        // if the user still needs to run `codex login` inside the guest.
        readiness = .codexLoginPending
        await ensureCodexAuthenticated()
    }

    /// Records that the user has completed `codex login` inside the guest.
    /// Persisted so we don't re-prompt on subsequent app launches.
    func markCodexLoginComplete() {
        _ = try? bundle.mutateState(fileManager: dependencies.fileManager) {
            $0.codexLoginCompleted = true
        }
        setupFailureMessage = nil
        if let destination = lastResolvedSSHDestination {
            readiness = .ready(sshDestination: destination)
        }
    }

    /// Post-setup hook: probes the guest's codex CLI auth state and (if
    /// unauthenticated) copies the host's `~/.codex` directory across as a
    /// best-effort fallback. Re-probes; if still not authenticated, transitions
    /// readiness to `.codexLoginPending` so the UI can prompt the user.
    ///
    /// Intended to be called after `markSetupComplete()` reports SSH is up.
    /// Safe to call multiple times — it never overwrites an already-good
    /// credential set on the guest (scp will refresh files in place, which is
    /// the desired behaviour when host credentials are newer).
    func ensureCodexAuthenticated() async {
        if fallbackUnavailableReason != nil { return }
        guard let destination = lastResolvedSSHDestination else {
            // We can't probe without an SSH destination. Surface as a soft
            // failure (.codexLoginPending) and let the caller try again.
            readiness = .codexLoginPending
            return
        }
        let options = SharedCompassVMGuestBridge.ConnectionOptions(
            identityFile: bundle.privateKeyURL.path,
            knownHostsFile: bundle.knownHostsURL.path,
            connectTimeoutSeconds: 5
        )

        let initialState = await SharedCompassVMCodexAuthBridge.checkGuestCodexAuth(
            destination: destination,
            options: options
        )
        switch initialState {
        case .authenticated:
            markCodexLoginComplete()
            return
        case let .indeterminate(detail):
            readiness = .codexLoginPending
            setupFailureMessage = "Could not determine codex auth state inside the guest (\(detail)). Run `codex login` in the guest's Terminal."
            return
        case .unauthenticated:
            break
        }

        do {
            try await SharedCompassVMCodexAuthBridge.copyHostCodexCredentialsToGuest(
                destination: destination,
                options: options
            )
        } catch {
            readiness = .codexLoginPending
            let detail = (error as? SharedCompassVMCodexAuthBridge.CopyError)?.description
                ?? error.localizedDescription
            setupFailureMessage = "Could not copy host ~/.codex into the guest (\(detail)). Run `codex login` in the guest's Terminal."
            return
        }

        let recheck = await SharedCompassVMCodexAuthBridge.checkGuestCodexAuth(
            destination: destination,
            options: options
        )
        switch recheck {
        case .authenticated:
            markCodexLoginComplete()
        case .unauthenticated, .indeterminate:
            readiness = .codexLoginPending
            setupFailureMessage = "Copied host ~/.codex to the guest but it still isn't authenticated. Run `codex login` in the guest's Terminal."
        }
    }

    /// Hook for future per-project ephemeral mounts. The parent
    /// `compass-workspaces` share is permanent and host-managed
    /// subdirectories suffice, so this is a no-op today. Validates the tag
    /// up-front so callers get the same error surface they would once
    /// real attach/detach exists.
    func attachWorkspace(at hostURL: URL, tag: String) throws {
        _ = try SharedCompassVMFileShare.ensureValidTag(tag)
        _ = hostURL
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
            readiness = .downloadingIPSW(fractionCompleted: fraction)
        } else if readiness == .notProvisioned {
            readiness = .downloadingIPSW(fractionCompleted: fraction)
        }
        if fraction >= 1.0 {
            _ = try? bundle.mutateState(fileManager: dependencies.fileManager) {
                $0.provisionStep = .installing
            }
            readiness = .installing(fractionCompleted: 0)
        }
    }

    private func updateInstallProgress(_ fraction: Double) {
        readiness = .installing(fractionCompleted: fraction)
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
}
