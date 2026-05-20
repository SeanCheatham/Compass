import Foundation

/// On-disk layout for the Compass shared VM bundle.
///
/// All files live under `~/Library/Application Support/Compass/SharedVM/bundle.vmbundle/`.
/// The bundle directory is created lazily by `ensureExists()`; callers should not assume
/// the parent tree exists at init time.
struct SharedCompassVMBundle: Equatable {
    /// Root of the bundle directory (the `.vmbundle` itself).
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    // MARK: Default location

    /// Returns the bundle at the canonical user-domain location:
    /// `~/Library/Application Support/Compass/SharedVM/bundle.vmbundle/`.
    static func defaultBundle(fileManager: FileManager = .default) throws -> SharedCompassVMBundle {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = appSupport
            .appendingPathComponent("Compass", isDirectory: true)
            .appendingPathComponent("SharedVM", isDirectory: true)
            .appendingPathComponent("bundle.vmbundle", isDirectory: true)
        return SharedCompassVMBundle(rootURL: url)
    }

    // MARK: File paths

    /// Sparse APFS disk image backing the guest's primary virtio block device.
    var diskImageURL: URL { rootURL.appendingPathComponent("Disk.img", isDirectory: false) }

    /// `VZMacAuxiliaryStorage` backing file.
    var auxiliaryStorageURL: URL { rootURL.appendingPathComponent("AuxiliaryStorage", isDirectory: false) }

    /// Serialized `VZMacHardwareModel.dataRepresentation` blob.
    var hardwareModelURL: URL { rootURL.appendingPathComponent("HardwareModel", isDirectory: false) }

    /// Serialized `VZMacMachineIdentifier.dataRepresentation` blob.
    var machineIdentifierURL: URL { rootURL.appendingPathComponent("MachineIdentifier", isDirectory: false) }

    /// Compass-owned state document (see `State`).
    var stateURL: URL { rootURL.appendingPathComponent("state.json", isDirectory: false) }

    /// `UserKnownHostsFile` for all SSH invocations targeting the guest.
    var knownHostsURL: URL { rootURL.appendingPathComponent("known_hosts", isDirectory: false) }

    /// Private half of the Compass-owned guest keypair.
    var privateKeyURL: URL { rootURL.appendingPathComponent("id_ed25519", isDirectory: false) }

    /// Public half of the Compass-owned guest keypair.
    var publicKeyURL: URL { rootURL.appendingPathComponent("id_ed25519.pub", isDirectory: false) }

    /// Resumable IPSW cache directory.
    var cacheDirectoryURL: URL { rootURL.appendingPathComponent("cache", isDirectory: true) }

    /// Path for a cached restore image for a given version label (e.g. "26.0.1.23A123").
    func restoreImageURL(forVersion version: String) -> URL {
        cacheDirectoryURL.appendingPathComponent("RestoreImage-\(version).ipsw", isDirectory: false)
    }

    /// Host-side stash for a copy of the user's `~/.codex` directory, used by
    /// the codex-auth fallback path when the guest is not yet authenticated.
    /// The directory is created lazily by the auth bridge; callers should not
    /// assume it exists.
    var codexCredentialsStashURL: URL {
        rootURL.appendingPathComponent("codex-credentials", isDirectory: true)
    }

    // MARK: SSH keypair

    /// Errors produced by `ensureSSHKeypair`.
    enum SSHKeypairError: Error, CustomStringConvertible {
        case sshKeygenMissing
        case sshKeygenFailed(exitCode: Int32, stderr: String)

        var description: String {
            switch self {
            case .sshKeygenMissing:
                return "/usr/bin/ssh-keygen is not available on this host"
            case let .sshKeygenFailed(code, stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return "ssh-keygen exited \(code): \(trimmed)"
            }
        }
    }

    /// Generates the Compass-owned Ed25519 keypair (no passphrase) at
    /// `id_ed25519` / `id_ed25519.pub` if either half is missing. Idempotent:
    /// when both halves already exist this returns without spawning a process.
    ///
    /// Used by `provisionIfNeeded` before the IPSW install so the public key
    /// is on disk by the time the guest is bootable (and ready to be planted
    /// into the guest's `~/.ssh/authorized_keys` during first-boot prep).
    @discardableResult
    func ensureSSHKeypair(fileManager: FileManager = .default) throws -> Bool {
        if fileManager.fileExists(atPath: privateKeyURL.path),
           fileManager.fileExists(atPath: publicKeyURL.path) {
            return false
        }
        try ensureExists(fileManager: fileManager)
        // ssh-keygen refuses to overwrite, so remove any half-generated state.
        try? fileManager.removeItem(at: privateKeyURL)
        try? fileManager.removeItem(at: publicKeyURL)

        let keygenPath = "/usr/bin/ssh-keygen"
        guard fileManager.fileExists(atPath: keygenPath) else {
            throw SSHKeypairError.sshKeygenMissing
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: keygenPath)
        process.arguments = [
            "-t", "ed25519",
            "-N", "",
            "-C", "compass-shared-vm",
            "-f", privateKeyURL.path
        ]
        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            let message = String(data: data, encoding: .utf8) ?? ""
            throw SSHKeypairError.sshKeygenFailed(
                exitCode: process.terminationStatus,
                stderr: message
            )
        }
        return true
    }

    // MARK: Layout materialization

    /// Creates the bundle root and its known subdirectories if absent.
    /// Idempotent.
    func ensureExists(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
    }

    /// True iff the disk image plus auxiliary storage exist on disk.
    /// Used as a quick "installed?" probe without parsing `state.json`.
    func existsOnDisk(fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: diskImageURL.path)
            && fileManager.fileExists(atPath: auxiliaryStorageURL.path)
    }

    /// Removes installed/partially-installed VM artifacts while preserving
    /// reusable host-owned assets: the IPSW cache and Compass SSH keypair.
    ///
    /// Use this before retrying a failed `VZMacOSInstaller` run. A failed
    /// install can leave `Disk.img`, `AuxiliaryStorage`, or platform identity
    /// files in an ambiguous state, and reusing them can make the next install
    /// fail for reasons unrelated to the selected restore image.
    func resetInstalledArtifacts(fileManager: FileManager = .default) throws {
        try ensureExists(fileManager: fileManager)
        let existingState = (try? loadState(fileManager: fileManager)) ?? State()
        let artifactsToRemove = [
            diskImageURL,
            auxiliaryStorageURL,
            hardwareModelURL,
            machineIdentifierURL,
            knownHostsURL,
            codexCredentialsStashURL
        ]
        for url in artifactsToRemove where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        let resetState = State(
            provisionStep: .notProvisioned,
            guestUserName: existingState.guestUserName,
            guestMACAddress: existingState.guestMACAddress
        )
        try saveState(resetState, fileManager: fileManager)
    }

    // MARK: State document

    /// Compass-owned bookkeeping persisted alongside the VZ artefacts.
    ///
    /// This document is the source of truth for "where are we in the provisioning
    /// pipeline" — it is consulted at warmup to skip directly to the right
    /// readiness state without re-running the IPSW download or installer.
    struct State: Codable, Equatable {
        enum ProvisionStep: String, Codable, Equatable {
            case notProvisioned
            case downloadingIPSW
            case installing
            case firstBootPending
            case guestPrepping
            case ready
        }

        var provisionStep: ProvisionStep
        var lastKnownGoodIP: String?
        var guestUserName: String
        var guestOSVersion: String?
        var codexLoginCompleted: Bool
        var bootAttemptCounter: Int
        var lastBundleSize: UInt64?
        /// MAC address Compass pinned on the guest's virtio network device.
        /// Persisted so subsequent boots reuse the same address, which lets
        /// `SharedCompassVMGuestIPDiscovery` find the guest's IP across host
        /// reboots via `/var/db/dhcpd_leases` and `arp -an`.
        var guestMACAddress: String?

        static let defaultGuestUserName = "compass"

        init(
            provisionStep: ProvisionStep = .notProvisioned,
            lastKnownGoodIP: String? = nil,
            guestUserName: String = State.defaultGuestUserName,
            guestOSVersion: String? = nil,
            codexLoginCompleted: Bool = false,
            bootAttemptCounter: Int = 0,
            lastBundleSize: UInt64? = nil,
            guestMACAddress: String? = nil
        ) {
            self.provisionStep = provisionStep
            self.lastKnownGoodIP = lastKnownGoodIP
            self.guestUserName = guestUserName
            self.guestOSVersion = guestOSVersion
            self.codexLoginCompleted = codexLoginCompleted
            self.bootAttemptCounter = bootAttemptCounter
            self.lastBundleSize = lastBundleSize
            self.guestMACAddress = guestMACAddress
        }
    }

    /// Returns the persisted guest MAC, or generates one (and persists it)
    /// if none exists yet. Stable across host reboots so dhcpd_leases / arp
    /// lookups can find the guest by MAC.
    @discardableResult
    func ensureGuestMACAddress(fileManager: FileManager = .default) throws -> String {
        var state = try loadState(fileManager: fileManager)
        if let existing = state.guestMACAddress,
           !SharedCompassVMGuestIPDiscovery.canonicalize(mac: existing).isEmpty {
            return SharedCompassVMGuestIPDiscovery.canonicalize(mac: existing)
        }
        let mac = SharedCompassVMBundle.randomGuestMAC()
        state.guestMACAddress = mac
        try saveState(state, fileManager: fileManager)
        return mac
    }

    /// Generates a locally-administered unicast MAC. Sets bit 1 of the first
    /// octet (locally-administered) and clears bit 0 (unicast) so the
    /// address won't collide with manufacturer-assigned MACs and won't be
    /// misinterpreted as multicast.
    static func randomGuestMAC() -> String {
        var octets: [UInt8] = []
        octets.reserveCapacity(6)
        var firstOctet = UInt8.random(in: 0...255)
        firstOctet |= 0b0000_0010 // locally administered
        firstOctet &= 0b1111_1110 // unicast
        octets.append(firstOctet)
        for _ in 1..<6 {
            octets.append(UInt8.random(in: 0...255))
        }
        return octets.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    /// Reads `state.json`. Returns a fresh default state if the file does not exist.
    func loadState(fileManager: FileManager = .default) throws -> State {
        guard fileManager.fileExists(atPath: stateURL.path) else {
            return State()
        }
        let data = try Data(contentsOf: stateURL)
        let decoder = JSONDecoder()
        return try decoder.decode(State.self, from: data)
    }

    /// Atomically writes `state.json`, creating the bundle directory if needed.
    func saveState(_ state: State, fileManager: FileManager = .default) throws {
        try ensureExists(fileManager: fileManager)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: [.atomic])
    }

    /// Mutates the persisted state in place. Useful for ratcheting `bootAttemptCounter`
    /// or flipping `codexLoginCompleted` without ceremony at call sites.
    @discardableResult
    func mutateState(
        fileManager: FileManager = .default,
        _ body: (inout State) -> Void
    ) throws -> State {
        var state = try loadState(fileManager: fileManager)
        body(&state)
        try saveState(state, fileManager: fileManager)
        return state
    }
}
