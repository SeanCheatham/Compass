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

    init(
        bundle: SharedCompassVMBundle,
        workspacesRootURL: URL,
        dependencies: Dependencies = .live()
    ) {
        self.bundle = bundle
        self.workspacesRootURL = workspacesRootURL.standardizedFileURL
        self.dependencies = dependencies
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
        let availability = dependencies.availability()
        if case .unavailable(let reason) = availability {
            readiness = .unavailable(reason: reason)
            return
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
}
