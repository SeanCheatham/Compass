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

    // MARK: - Owned values

    let bundle: SharedCompassVMBundle

    /// Host-side root that backs the `compass-workspaces` VirtioFS device.
    /// Worktrees for individual Develop iterations are subdirectories of this.
    let workspacesRootURL: URL

    private let dependencies: Dependencies
    private var virtualMachine: VZVirtualMachine?
    private var sleepObserver: SharedCompassVMSleepObserver?
    private var lastResolvedSSHDestination: String?

    /// Pipe attached to the guest's virtio console port. The guest's first-boot
    /// script writes its IP here as `COMPASS_GUEST_IP=<addr>\n`. The host
    /// keeps the pipe alive for the lifetime of the running VM so the buffer
    /// is never closed mid-read. See `attachConsolePipeIfNeeded`.
    private var consolePipe: Pipe?
    private var consoleReadTask: Task<Void, Never>?

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
    func provisionIfNeeded() async throws {
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

        try bundle.mutateState(fileManager: dependencies.fileManager) {
            $0.provisionStep = .downloadingIPSW
        }
        readiness = .downloadingIPSW(fractionCompleted: 0)

        do {
            try await dependencies.imageInstaller.install(
                into: bundle,
                downloadProgress: downloadSink,
                installProgress: installSink,
                fileManager: dependencies.fileManager
            )
        } catch {
            readiness = .error(detail: SharedCompassVMAvailabilityCheck.describe(error: error))
            throw error
        }

        try bundle.mutateState(fileManager: dependencies.fileManager) {
            $0.provisionStep = .firstBootPending
        }
        readiness = .firstBootPending
    }

    /// Boots (or re-boots) the guest from the currently-installed bundle.
    /// Caller is responsible for first calling `provisionIfNeeded` if the
    /// bundle is empty. Idempotent if the VM is already running.
    func start() async throws {
        if fallbackUnavailableReason != nil { return }
        if let virtualMachine, virtualMachine.state == .running {
            return
        }

        // Compose configuration from on-disk artifacts.
        let inputs = SharedCompassVMConfiguration.Inputs.standard(
            bundle: bundle,
            workspacesRootURL: workspacesRootURL
        )
        let configuration = try SharedCompassVMConfiguration.makeConfiguration(
            for: inputs,
            fileManager: dependencies.fileManager
        )

        // Attach a host-owned Pipe to the virtio console so first-boot guest
        // scripts can publish `COMPASS_GUEST_IP=<addr>` lines back to us.
        // Phase 3 keeps this hook live for the full VM lifetime; the read
        // task discards anything that doesn't match the known prefix.
        attachConsolePipe(to: configuration)

        try configuration.validate()

        let machine = VZVirtualMachine(configuration: configuration)
        self.virtualMachine = machine

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

    /// Marks the user-driven first-boot Setup Assistant as complete. Transitions
    /// readiness to `.guestPrepping` and then to `.ready` once the SSH probe
    /// succeeds. Caller (Phase 4 UI) is responsible for invoking this when the
    /// "Mark setup complete" button is pressed.
    func markSetupComplete() async {
        readiness = .guestPrepping
        _ = try? bundle.mutateState(fileManager: dependencies.fileManager) {
            $0.provisionStep = .guestPrepping
        }

        let state = (try? bundle.loadState(fileManager: dependencies.fileManager)) ?? SharedCompassVMBundle.State()
        guard let ip = state.lastKnownGoodIP else {
            // We expect Phase 3's guest-prep stage to discover and persist
            // the guest IP before this is called. If it's still missing, leave
            // readiness in .guestPrepping and let the caller surface a retry.
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
        if probeOK {
            _ = try? bundle.mutateState(fileManager: dependencies.fileManager) {
                $0.provisionStep = .ready
            }
            lastResolvedSSHDestination = destination
            readiness = state.codexLoginCompleted ? .ready(sshDestination: destination) : .codexLoginPending
        }
    }

    /// Records that the user has completed `codex login` inside the guest.
    /// Persisted so we don't re-prompt on subsequent app launches.
    func markCodexLoginComplete() {
        _ = try? bundle.mutateState(fileManager: dependencies.fileManager) {
            $0.codexLoginCompleted = true
        }
        if let destination = lastResolvedSSHDestination {
            readiness = .ready(sshDestination: destination)
        }
    }

    /// Phase 3 post-setup hook: probes the guest's codex CLI auth state and
    /// (if unauthenticated) copies the host's `~/.codex` directory across as a
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
        case .indeterminate:
            // Treat indeterminate as login-pending so the user is prompted.
            readiness = .codexLoginPending
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
        }
    }

    /// Hook for future per-project ephemeral mounts. Today the parent
    /// `compass-workspaces` share is permanent and host-managed subdirectories
    /// suffice, so this is a no-op. Phase 3 callers may invoke it for symmetry.
    func attachWorkspace(at hostURL: URL, tag: String) throws {
        _ = try SharedCompassVMFileShare.ensureValidTag(tag)
        _ = hostURL
        // Intentionally empty — see the doc-comment.
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

    /// Wires a host-owned `Pipe()` to the virtio console device so the guest's
    /// first-boot script can report its IP back to Compass. We hold the pipe
    /// in `self.consolePipe` for the entire VM lifetime; closing it mid-run
    /// would close the read side from under the guest.
    ///
    /// First-boot script contract (delivered into the VirtioFS workspace as a
    /// post-Setup-Assistant prep step — see Phase 4 TODO): the script writes
    /// one line of the form `COMPASS_GUEST_IP=<addr>` to `/dev/cu.virtio-portN`
    /// (`compass.guest.report`). Anything else on the port is ignored. Until
    /// the first-boot script ships, this hook simply discards traffic; the
    /// pipe is still useful for forward-compat readiness and lets us drop the
    /// `port.attachment = nil` placeholder.
    private func attachConsolePipe(to configuration: VZVirtualMachineConfiguration) {
        let pipe = Pipe()
        let attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: pipe.fileHandleForWriting,
            fileHandleForWriting: pipe.fileHandleForReading
        )
        do {
            try SharedCompassVMConfiguration.replaceConsoleAttachment(attachment, on: configuration)
        } catch {
            // No console device on this configuration — bail without retaining
            // the pipe. Nothing else relies on it being live.
            return
        }
        self.consolePipe = pipe

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
        if let pipe = consolePipe {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
        consolePipe = nil
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
