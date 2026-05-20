import Foundation

/// Host-side disk planter for the Compass shared VM's headless first-boot
/// pipeline.
///
/// Runs **once** between `VZMacOSInstaller.install` completing and the very
/// first `VZVirtualMachine.start` call. Mounts the just-installed Disk.img
/// on the host, writes the LaunchDaemon plist + bootstrap script + sudoers
/// fragment + supporting payload into the Data volume, then unmounts. The
/// guest's first boot then runs the planted LaunchDaemon, which creates the
/// `compass` admin user, authorises Compass's SSH key, and enables sshd —
/// all without Setup Assistant ever appearing.
///
/// Architecture:
///   * `Planter.plant(...)` is the imperative entry point invoked from
///     `SharedCompassVM.provisionIfNeeded`.
///   * Discovery (find the Data volume devnode inside the disk image) runs
///     **unprivileged** — `hdiutil attach -nomount` and `diskutil apfs list`
///     don't need root.
///   * Mounting + writing root-owned files runs **once-elevated** via a
///     single `osascript do shell script ... with administrator privileges`
///     prompt. The user sees one Mac authentication dialog per install.
///   * The elevated portion is a small bash script (rendered by
///     `renderElevatedScript`) so the privileged step set is reviewable
///     and unit-testable.
enum SharedCompassVMHeadlessPlanter {
    // MARK: - Stage names

    /// Filenames Compass writes into the host staging directory. The
    /// elevated script reads them by these well-known names; renaming any
    /// of them breaks both sides in lockstep.
    enum StagedFile {
        static let launchDaemonPlist = "launchd.plist"
        static let bootstrapScript = "bootstrap.sh"
        static let sudoersFragment = "sudoers"
        static let appleSetupDoneMarker = "apple-setup-done"
        static let publicKey = "id_ed25519.pub"
        static let passwordFile = "user.password"
        static let codexBinary = "codex"
        static let elevatedScript = "planter.sh"
    }

    // MARK: - Errors

    enum Error: Swift.Error, CustomStringConvertible {
        case toolMissing(path: String)
        case toolFailed(tool: String, exitCode: Int32, output: String)
        case dataVolumeNotFound(diagnostics: String)
        case attachOutputUnparseable(detail: String)
        case userCancelledElevation
        case elevationFailed(detail: String)

        var description: String {
            switch self {
            case let .toolMissing(path):
                return "Required host tool is missing: \(path)"
            case let .toolFailed(tool, code, output):
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(tool) exited \(code): \(trimmed)"
            case let .dataVolumeNotFound(diagnostics):
                return "Could not locate the Data APFS volume in the attached disk image. \(diagnostics)"
            case let .attachOutputUnparseable(detail):
                return "hdiutil attach output could not be parsed: \(detail)"
            case .userCancelledElevation:
                return "The macOS administrator-authentication prompt was dismissed; headless first-boot was not planted."
            case let .elevationFailed(detail):
                return "Elevated planter script failed: \(detail)"
            }
        }
    }

    // MARK: - Public API

    struct Report: Equatable {
        var dataVolumeDeviceNode: String
        var stagingDirectoryURL: URL
        var elevatedScriptOutput: String
    }

    /// Drives the full plant lifecycle for `payload` against `diskImageURL`.
    /// Cleans up the host staging dir before returning. Surfaces a
    /// `Report` describing what landed for diagnostics.
    static func plant(
        payload: SharedCompassVMHeadlessFirstBoot.Payload,
        diskImageURL: URL,
        dependencies: Dependencies = .live(),
        fileManager: FileManager = .default
    ) async throws -> Report {
        // 1. Discover the Data volume devnode (no elevation required).
        let attachment = try await dependencies.diskAttacher.attachWithoutMount(
            diskImageURL: diskImageURL
        )
        defer {
            Task { try? await dependencies.diskAttacher.detach(deviceNode: attachment.containerDeviceNode) }
        }
        let dataVolume = try await dependencies.dataVolumeLocator.locateDataVolume(
            insideContainer: attachment.containerDeviceNode
        )

        // 2. Materialize all the payload artifacts in a host staging dir.
        let stagingDir = try makeStagingDirectory(fileManager: fileManager)
        do {
            try stagePayload(payload, into: stagingDir, fileManager: fileManager)

            // 3. Render + write the elevated planter script.
            let elevatedScript = renderElevatedScript(
                payload: payload,
                stagingDirectoryHostPath: stagingDir.path,
                dataVolumeDeviceNode: dataVolume
            )
            let scriptURL = stagingDir.appendingPathComponent(StagedFile.elevatedScript, isDirectory: false)
            try Data(elevatedScript.utf8).write(to: scriptURL, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            // 4. Run once with administrator privileges. One auth prompt.
            let output = try await dependencies.elevator.runElevatedScript(at: scriptURL)

            try? fileManager.removeItem(at: stagingDir)
            return Report(
                dataVolumeDeviceNode: dataVolume,
                stagingDirectoryURL: stagingDir,
                elevatedScriptOutput: output
            )
        } catch {
            try? fileManager.removeItem(at: stagingDir)
            throw error
        }
    }

    // MARK: - Staging

    /// Allocates a fresh staging directory under `NSTemporaryDirectory()`.
    /// The directory name embeds a UUID so concurrent provisions (which
    /// shouldn't happen in practice) cannot stomp each other.
    static func makeStagingDirectory(fileManager: FileManager = .default) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Compass-HeadlessFirstBoot-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes every payload artifact into `stagingDir` using the well-known
    /// `StagedFile` filenames. The elevated planter script reads them from
    /// these locations.
    static func stagePayload(
        _ payload: SharedCompassVMHeadlessFirstBoot.Payload,
        into stagingDir: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        let writes: [(String, Data)] = [
            (StagedFile.launchDaemonPlist, payload.launchDaemonPlist),
            (StagedFile.bootstrapScript, Data(payload.bootstrapScript.utf8)),
            (StagedFile.sudoersFragment, Data(payload.sudoersFragment.utf8)),
            (StagedFile.appleSetupDoneMarker, Data()),
            (StagedFile.publicKey, payload.stagedPublicKey),
            (StagedFile.passwordFile, Data(payload.stagedPassword.utf8))
        ]
        for (name, contents) in writes {
            let url = stagingDir.appendingPathComponent(name, isDirectory: false)
            try contents.write(to: url, options: [.atomic])
        }

        if let codex = payload.stagedCodexBinary {
            let url = stagingDir.appendingPathComponent(StagedFile.codexBinary, isDirectory: false)
            try codex.write(to: url, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        // Password file mode is tightened both here and by the elevated
        // script when it lands inside the guest. Belt-and-braces.
        let passwordURL = stagingDir.appendingPathComponent(StagedFile.passwordFile, isDirectory: false)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: passwordURL.path)
    }

    // MARK: - Elevated script rendering

    /// Renders the bash script that runs once with administrator privileges.
    /// Pure — exposed for unit tests so the privileged step set can be locked
    /// in without invoking osascript.
    ///
    /// The script:
    ///   1. Mounts the Data volume to a host-private mountpoint.
    ///   2. `install -o root -g wheel -m <mode>` each artifact to its final
    ///      guest path (relative to the mountpoint).
    ///   3. Unmounts the volume.
    ///
    /// Container devnode detach happens in the unprivileged caller (via
    /// `Dependencies.diskAttacher.detach`) so a script failure leaves a
    /// detachable disk rather than a wedged one.
    static func renderElevatedScript(
        payload: SharedCompassVMHeadlessFirstBoot.Payload,
        stagingDirectoryHostPath: String,
        dataVolumeDeviceNode: String
    ) -> String {
        let profile = payload.profile
        return """
        #!/bin/bash
        #
        # Compass headless first-boot planter (elevated portion). Invoked once
        # by SharedCompassVMHeadlessPlanter via osascript with administrator
        # privileges. Mounts the just-installed guest Data volume, plants the
        # first-boot artifacts as root, and unmounts.
        #
        set -euo pipefail

        STAGING_DIR="\(stagingDirectoryHostPath)"
        DATA_DEV="\(dataVolumeDeviceNode)"

        MOUNT_POINT=$(mktemp -d /tmp/compass-firstboot-mount.XXXXXX)
        cleanup() {
          diskutil unmount "$MOUNT_POINT" >/dev/null 2>&1 || true
          rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
        }
        trap cleanup EXIT

        diskutil mount -mountPoint "$MOUNT_POINT" -nobrowse "$DATA_DEV"

        # .AppleSetupDone — empty marker, root:wheel 0644. Skips Setup
        # Assistant on first boot.
        install -d -o root -g wheel -m 0755 "$MOUNT_POINT\(profile.appleSetupDoneGuestPath.directoryComponent)"
        install -o root -g wheel -m 0644 \\
          "$STAGING_DIR/\(StagedFile.appleSetupDoneMarker)" \\
          "$MOUNT_POINT\(profile.appleSetupDoneGuestPath)"

        # LaunchDaemon plist — root:wheel 0644. launchd refuses non-root
        # plists, so ownership is non-negotiable.
        install -d -o root -g wheel -m 0755 "$MOUNT_POINT\(profile.launchDaemonGuestPath.directoryComponent)"
        install -o root -g wheel -m 0644 \\
          "$STAGING_DIR/\(StagedFile.launchDaemonPlist)" \\
          "$MOUNT_POINT\(profile.launchDaemonGuestPath)"

        # Bootstrap script — root:wheel 0755.
        install -d -o root -g wheel -m 0755 "$MOUNT_POINT\(profile.bootstrapScriptGuestPath.directoryComponent)"
        install -o root -g wheel -m 0755 \\
          "$STAGING_DIR/\(StagedFile.bootstrapScript)" \\
          "$MOUNT_POINT\(profile.bootstrapScriptGuestPath)"

        # sudoers fragment — root:wheel 0440. sudo refuses fragments that
        # are group- or world-writable.
        install -d -o root -g wheel -m 0755 "$MOUNT_POINT\(profile.sudoersFragmentGuestPath.directoryComponent)"
        install -o root -g wheel -m 0440 \\
          "$STAGING_DIR/\(StagedFile.sudoersFragment)" \\
          "$MOUNT_POINT\(profile.sudoersFragmentGuestPath)"

        # Staging payload (public key, password file, optional codex binary).
        # Lives under /Users/Shared/compass-firstboot/, root:wheel — the
        # bootstrap script tightens ownership as it consumes each file.
        install -d -o root -g wheel -m 0700 "$MOUNT_POINT\(profile.stagingDirectoryGuestPath)"
        install -o root -g wheel -m 0644 \\
          "$STAGING_DIR/\(StagedFile.publicKey)" \\
          "$MOUNT_POINT\(profile.stagingDirectoryGuestPath)/\(profile.stagedPublicKeyName)"
        install -o root -g wheel -m 0600 \\
          "$STAGING_DIR/\(StagedFile.passwordFile)" \\
          "$MOUNT_POINT\(profile.stagingDirectoryGuestPath)/\(profile.stagedPasswordFileName)"
        if [ -f "$STAGING_DIR/\(StagedFile.codexBinary)" ]; then
          install -o root -g wheel -m 0755 \\
            "$STAGING_DIR/\(StagedFile.codexBinary)" \\
            "$MOUNT_POINT\(profile.stagingDirectoryGuestPath)/\(profile.stagedCodexBinaryName)"
        fi

        sync
        echo "[compass-planter] done."
        """
    }

    // MARK: - Dependencies (injection seam)

    /// Bag of injectable adapters for the three external operations the
    /// planter performs. `Dependencies.live()` returns the production-wired
    /// concrete types; tests substitute fakes.
    struct Dependencies {
        var diskAttacher: HostDiskAttaching
        var dataVolumeLocator: DataVolumeLocating
        var elevator: AdminElevating

        static func live() -> Dependencies {
            Dependencies(
                diskAttacher: HDIUtilDiskAttacher(),
                dataVolumeLocator: DiskUtilDataVolumeLocator(),
                elevator: OSAScriptAdminElevator()
            )
        }
    }
}

// MARK: - Path helper

private extension String {
    /// Returns the directory portion of an absolute file path, e.g.
    /// `/Library/LaunchDaemons/foo.plist` -> `/Library/LaunchDaemons`. Used by
    /// the elevated script renderer to emit `install -d` calls for each
    /// destination's parent dir without paying a runtime `dirname` shell-out.
    var directoryComponent: String {
        (self as NSString).deletingLastPathComponent
    }
}

// MARK: - HostDiskAttaching

/// Wraps `hdiutil attach -nomount` + `hdiutil detach`.
protocol HostDiskAttaching {
    /// Attaches the disk image without mounting any volumes. Returns the
    /// attached devnode (e.g. `/dev/disk5`) plus the raw plist output for
    /// diagnostics.
    func attachWithoutMount(diskImageURL: URL) async throws -> HostDiskAttachment

    /// Detaches the previously-attached device node.
    func detach(deviceNode: String) async throws
}

struct HostDiskAttachment: Equatable {
    /// Top-level container device node, e.g. `/dev/disk5`.
    var containerDeviceNode: String
    /// Full plist payload returned by `hdiutil attach`. Useful in test
    /// failures and rare "no recognised volumes" diagnostics.
    var rawPlist: String
}

struct HDIUtilDiskAttacher: HostDiskAttaching {
    let hdiutilPath: String

    init(hdiutilPath: String = "/usr/bin/hdiutil") {
        self.hdiutilPath = hdiutilPath
    }

    func attachWithoutMount(diskImageURL: URL) async throws -> HostDiskAttachment {
        let result = try await HeadlessPlanterProcessRunner.runCapture(
            executable: hdiutilPath,
            arguments: ["attach", "-nomount", "-plist", "-nobrowse", diskImageURL.path]
        )
        guard result.exitCode == 0 else {
            throw SharedCompassVMHeadlessPlanter.Error.toolFailed(
                tool: "hdiutil attach",
                exitCode: result.exitCode,
                output: result.combinedOutput
            )
        }
        let containerDeviceNode = try Self.parseContainerDeviceNode(fromPlist: result.standardOutput)
        return HostDiskAttachment(
            containerDeviceNode: containerDeviceNode,
            rawPlist: result.standardOutput
        )
    }

    func detach(deviceNode: String) async throws {
        let result = try await HeadlessPlanterProcessRunner.runCapture(
            executable: hdiutilPath,
            arguments: ["detach", deviceNode]
        )
        guard result.exitCode == 0 else {
            throw SharedCompassVMHeadlessPlanter.Error.toolFailed(
                tool: "hdiutil detach",
                exitCode: result.exitCode,
                output: result.combinedOutput
            )
        }
    }

    /// Parses `hdiutil attach -plist` output and returns the first
    /// `dev-entry` whose `content-hint` indicates the whole-disk container.
    /// Falls back to the first numbered `/dev/diskN` entry when no clear
    /// container hint is present (some images are simple single-partition).
    static func parseContainerDeviceNode(fromPlist plistString: String) throws -> String {
        guard let data = plistString.data(using: .utf8) else {
            throw SharedCompassVMHeadlessPlanter.Error.attachOutputUnparseable(detail: "non-UTF8 plist")
        }
        let parsed: Any
        do {
            parsed = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw SharedCompassVMHeadlessPlanter.Error.attachOutputUnparseable(
                detail: "PropertyListSerialization: \(error.localizedDescription)"
            )
        }
        guard
            let root = parsed as? [String: Any],
            let systemEntities = root["system-entities"] as? [[String: Any]],
            !systemEntities.isEmpty
        else {
            throw SharedCompassVMHeadlessPlanter.Error.attachOutputUnparseable(
                detail: "missing or empty system-entities array"
            )
        }
        // Prefer the whole-disk container devnode (path matches /dev/diskN
        // with no trailing slice). The slice entries (e.g. /dev/disk5s1)
        // also appear but we want the parent for detach.
        let entries = systemEntities.compactMap { $0["dev-entry"] as? String }
        let wholeDisk = entries.first { entry in
            entry.range(of: #"^/dev/disk\d+$"#, options: .regularExpression) != nil
        }
        if let wholeDisk { return wholeDisk }
        if let first = entries.first { return first }
        throw SharedCompassVMHeadlessPlanter.Error.attachOutputUnparseable(
            detail: "no dev-entry strings in system-entities"
        )
    }
}

// MARK: - DataVolumeLocating

/// Wraps `diskutil apfs list -plist` and identifies the Data volume by
/// APFS role.
protocol DataVolumeLocating {
    /// Returns the devnode for the Data-role APFS volume inside `container`
    /// (e.g. given `/dev/disk5` returns `/dev/disk5s1`).
    func locateDataVolume(insideContainer container: String) async throws -> String
}

struct DiskUtilDataVolumeLocator: DataVolumeLocating {
    let diskutilPath: String

    init(diskutilPath: String = "/usr/sbin/diskutil") {
        self.diskutilPath = diskutilPath
    }

    func locateDataVolume(insideContainer container: String) async throws -> String {
        let result = try await HeadlessPlanterProcessRunner.runCapture(
            executable: diskutilPath,
            arguments: ["apfs", "list", "-plist", container]
        )
        guard result.exitCode == 0 else {
            throw SharedCompassVMHeadlessPlanter.Error.toolFailed(
                tool: "diskutil apfs list",
                exitCode: result.exitCode,
                output: result.combinedOutput
            )
        }
        return try Self.parseDataVolumeDeviceNode(fromPlist: result.standardOutput)
    }

    /// Walks the `Containers[].Volumes[]` array and returns the devnode of
    /// the first volume whose `Roles` set contains `Data`. Apple's macOS
    /// installer always emits exactly one Data volume per container.
    static func parseDataVolumeDeviceNode(fromPlist plistString: String) throws -> String {
        guard let data = plistString.data(using: .utf8) else {
            throw SharedCompassVMHeadlessPlanter.Error.dataVolumeNotFound(diagnostics: "non-UTF8 plist")
        }
        let parsed: Any
        do {
            parsed = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw SharedCompassVMHeadlessPlanter.Error.dataVolumeNotFound(
                diagnostics: "PropertyListSerialization: \(error.localizedDescription)"
            )
        }
        guard let root = parsed as? [String: Any] else {
            throw SharedCompassVMHeadlessPlanter.Error.dataVolumeNotFound(diagnostics: "root is not a dict")
        }
        let containers = root["Containers"] as? [[String: Any]] ?? []
        for container in containers {
            let volumes = container["Volumes"] as? [[String: Any]] ?? []
            for volume in volumes {
                let roles = volume["Roles"] as? [String] ?? []
                if roles.contains("Data"), let deviceIdentifier = volume["DeviceIdentifier"] as? String {
                    return "/dev/" + deviceIdentifier
                }
            }
        }
        throw SharedCompassVMHeadlessPlanter.Error.dataVolumeNotFound(
            diagnostics: "no APFS volume with Role=Data inside \(containers.count) containers"
        )
    }
}

// MARK: - AdminElevating

/// Wraps the one-time administrator-authentication prompt that runs the
/// elevated planter script.
protocol AdminElevating {
    /// Runs `/bin/bash <scriptURL>` once with administrator privileges and
    /// returns the captured stdout. Throws `userCancelledElevation` if the
    /// user dismisses the auth prompt.
    func runElevatedScript(at scriptURL: URL) async throws -> String
}

/// Production elevator. Invokes NSAppleScript with
/// `do shell script "..." with administrator privileges`. Implementation
/// hops to a detached task because NSAppleScript is synchronous, blocks the
/// calling thread on the auth prompt, and must not be invoked on
/// `@MainActor`.
struct OSAScriptAdminElevator: AdminElevating {
    func runElevatedScript(at scriptURL: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try Self.runSynchronously(scriptPath: scriptURL.path)
        }.value
    }

    private static func runSynchronously(scriptPath: String) throws -> String {
        // The AppleScript here invokes /bin/bash on the rendered planter
        // script. We single-quote the path so spaces or special characters
        // can't break out (the staging dir's UUID component is plain
        // alphanumerics + hyphens, but defence in depth costs nothing).
        let escapedPath = scriptPath.replacingOccurrences(of: "'", with: "'\\''")
        let source = """
        do shell script "/bin/bash '\(escapedPath)' 2>&1" with administrator privileges
        """
        guard let script = NSAppleScript(source: source) else {
            throw SharedCompassVMHeadlessPlanter.Error.elevationFailed(detail: "could not construct NSAppleScript")
        }
        var errorInfo: NSDictionary?
        let output = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            if code == -128 {
                throw SharedCompassVMHeadlessPlanter.Error.userCancelledElevation
            }
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "unknown AppleScript error"
            throw SharedCompassVMHeadlessPlanter.Error.elevationFailed(detail: "\(message) (code \(code))")
        }
        return output.stringValue ?? ""
    }
}

// MARK: - HeadlessPlanterProcessRunner shim

/// Small `Process` wrapper used by the host-side discovery steps. Lives in
/// the planter module rather than reaching for the existing
/// `Compass.ProcessRunner` because that type is shaped for codex execs with
/// streaming behaviour Compass doesn't need here. Disambiguated by name
/// from the codex-flavoured `Compass.ProcessRunner`.
enum HeadlessPlanterProcessRunner {
    struct CaptureResult {
        var exitCode: Int32
        var standardOutput: String
        var standardError: String

        var combinedOutput: String {
            let trimmedOut = standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedErr = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            switch (trimmedOut.isEmpty, trimmedErr.isEmpty) {
            case (true, true):
                return ""
            case (true, false):
                return trimmedErr
            case (false, true):
                return trimmedOut
            case (false, false):
                return trimmedOut + "\n" + trimmedErr
            }
        }
    }

    static func runCapture(executable: String, arguments: [String]) async throws -> CaptureResult {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: executable) else {
            throw SharedCompassVMHeadlessPlanter.Error.toolMissing(path: executable)
        }
        return try await Task.detached(priority: .userInitiated) { () throws -> CaptureResult in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()
            process.waitUntilExit()

            let outData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
            let errData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            return CaptureResult(
                exitCode: process.terminationStatus,
                standardOutput: String(data: outData, encoding: .utf8) ?? "",
                standardError: String(data: errData, encoding: .utf8) ?? ""
            )
        }.value
    }
}
