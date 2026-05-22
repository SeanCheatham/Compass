import Foundation

/// Streams a host git working tree to the guest (and back) over vsock.
///
/// macOS guests TCC-block `AppleVirtIOFS` reads from every process —
/// including LaunchAgents in the GUI session and even root via
/// LaunchDaemon — so a shared VirtioFS directory is not a viable
/// transport for the agent's file operations. Compass instead keeps a
/// guest-local copy of each repo under
/// `/Users/compass/Compass/Repos/<UUID>/worktree` (allocated by
/// `SharedCompassVMGuestWorkspaceCatalog`) and synchronises via
/// gitignore-aware tar streamed over the existing vsock RPC
/// (`writeFile`, `readFile`, `bash`). No CLT/git is required on the
/// guest because the host owns gitignore filtering on the push side
/// and a small hard-coded exclude list on the pull side covers the
/// heavyweight build dirs (`.build`, `target`, `node_modules`,
/// `build`, `dist`) that dominate working-tree size.
enum SharedCompassVMWorktreeSync {
    /// Maximum bytes a single sync tar may occupy (after base64 in the
    /// JSON frame). The RPC framing caps total frame size at 1.5 GiB
    /// (see `AgentRPCFraming.maxFrameByteCount`); allowing ~1 GiB of
    /// binary tar leaves room for base64 inflation (1.33×) and JSON
    /// envelope overhead. Repos pushing past this need the chunked
    /// transfer path (tracked separately) — failing loudly here beats
    /// truncating a real repo into something the guest agent then
    /// tries to operate on.
    static let maxTarByteCount = 1024 * 1024 * 1024

    /// Directory names skipped when packaging the guest's working tree
    /// on the pull side. The host's push tar is already gitignore-aware
    /// (via `git ls-files`); these excludes cover the heavyweight
    /// dirs an agent's `bash` calls might create in the guest
    /// (`swift build`, `cargo build`, `npm install`).
    static let pullSideExcludeDirs: [String] = [
        ".git", ".build", "target", "node_modules", "build", "dist", ".swiftpm"
    ]

    enum SyncError: LocalizedError, CustomStringConvertible {
        case hostListFailed(stderr: String)
        case hostTarFailed(stderr: String)
        case hostExtractFailed(stderr: String)
        case guestExtractFailed(exitCode: Int32, stderr: String)
        case guestTarFailed(exitCode: Int32, stderr: String)
        case missingHostWorktree(URL)
        case tarTooLarge(byteCount: Int)
        case invalidGuestPath(String)

        var description: String {
            switch self {
            case .hostListFailed(let s): return "host git ls-files failed: \(s)"
            case .hostTarFailed(let s): return "host tar failed: \(s)"
            case .hostExtractFailed(let s): return "host tar extract failed: \(s)"
            case .guestExtractFailed(let code, let s): return "guest extract failed (exit \(code)): \(s)"
            case .guestTarFailed(let code, let s): return "guest tar failed (exit \(code)): \(s)"
            case .missingHostWorktree(let url): return "host worktree does not exist: \(url.path)"
            case .tarTooLarge(let n): return "sync tar exceeded \(maxTarByteCount) bytes (got \(n))"
            case .invalidGuestPath(let p): return "refusing to sync into suspicious guest path: \(p)"
            }
        }

        // LocalizedError — surfaces the actual reason in `localizedDescription`
        // (and therefore in NSError-style UI alerts) instead of the
        // unhelpful "The operation couldn't be completed. (… error N.)"
        // default that bridges in when only `Error` is conformed.
        var errorDescription: String? { description }
    }

    // MARK: - Push (host -> guest)

    /// Wipes (or creates) the guest worktree at `guestWorktreePath` and
    /// re-populates it from a gitignore-aware tar of `hostWorktreeURL`.
    /// Requires the guest agent to be running and the host worktree to
    /// be a git working tree.
    static func push(
        hostWorktreeURL: URL,
        guestWorktreePath: String,
        client: AgentVsockClient
    ) async throws {
        try validateGuestPath(guestWorktreePath)
        let host = hostWorktreeURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: host.path) else {
            throw SyncError.missingHostWorktree(host)
        }

        let tarData = try buildHostTar(at: host)
        guard tarData.count <= maxTarByteCount else {
            throw SyncError.tarTooLarge(byteCount: tarData.count)
        }

        let tmp = "/tmp/compass-sync-in-\(UUID().uuidString).tar"
        try await client.writeFile(tarData, at: URL(fileURLWithPath: tmp))

        let script = """
            set -e
            mkdir -p '\(guestWorktreePath)'.stage
            rm -rf '\(guestWorktreePath)'.stage
            mkdir -p '\(guestWorktreePath)'.stage
            /usr/bin/tar -xf '\(tmp)' -C '\(guestWorktreePath)'.stage
            rm -rf '\(guestWorktreePath)'
            mkdir -p "$(dirname '\(guestWorktreePath)')"
            mv '\(guestWorktreePath)'.stage '\(guestWorktreePath)'
            rm -f '\(tmp)'
            """
        let result = try await client.run(
            command: script,
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            timeout: 180
        )
        if result.exitCode != 0 {
            throw SyncError.guestExtractFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    // MARK: - Pull (guest -> host)

    /// Captures the guest worktree's current state (filtering out
    /// well-known build directories) and applies it onto the host
    /// worktree, deleting files that were on the host before push
    /// but are no longer present in the guest.
    static func pull(
        hostWorktreeURL: URL,
        guestWorktreePath: String,
        client: AgentVsockClient
    ) async throws {
        try validateGuestPath(guestWorktreePath)
        let host = hostWorktreeURL.standardizedFileURL

        let suffix = UUID().uuidString
        let tarTmp = "/tmp/compass-sync-out-\(suffix).tar"
        let listTmp = "/tmp/compass-sync-out-\(suffix).list"

        let findPredicates = pullSideExcludeDirs
            .map { "-name '\($0)'" }
            .joined(separator: " -o ")
        let script = """
            set -e
            cd '\(guestWorktreePath)'
            find . -type d \\( \(findPredicates) \\) -prune -o -type f -print0 > '\(listTmp)'
            < '\(listTmp)' /usr/bin/tar --null -T - -cf '\(tarTmp)'
            """
        let result = try await client.run(
            command: script,
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            timeout: 180
        )
        if result.exitCode != 0 {
            throw SyncError.guestTarFailed(exitCode: result.exitCode, stderr: result.stderr)
        }

        let tarData = try await client.readFile(at: URL(fileURLWithPath: tarTmp))
        let listData = try await client.readFile(at: URL(fileURLWithPath: listTmp))

        _ = try await client.run(
            command: "rm -f '\(tarTmp)' '\(listTmp)'",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            timeout: 30
        )

        let guestRelativePaths = parseFindNullList(listData)
        let hostRelativePaths = (try? gitTrackedAndUntracked(in: host)) ?? []
        let deletions = hostRelativePaths.subtracting(guestRelativePaths)
        for relative in deletions {
            let url = host.appendingPathComponent(relative)
            try? FileManager.default.removeItem(at: url)
        }

        try extractTarOnHost(tarData, into: host)
    }

    // MARK: - Internals

    /// Allow-listed guest-side prefixes Compass is willing to sync into.
    /// The sync script's `rm -rf` is wrapped in `validateGuestPath` so
    /// this list is the security boundary — anything not under one of
    /// these roots gets rejected before any guest-side mutation happens.
    ///
    /// Today this is just the persistent per-repo root used by
    /// `SharedCompassVMGuestWorkspaceCatalog`. The legacy
    /// `/Users/compass/Compass/Worktrees` per-iteration root was
    /// dropped along with the host-side worktree machinery.
    static let allowedGuestPathPrefixes: [String] = [
        SharedCompassVMGuestWorkspaceCatalog.guestReposRoot
    ]

    /// Validates that the guest worktree path is under one of the
    /// allow-listed guest workspaces roots. Defence in depth: prevents
    /// a malformed path from causing the sync script's `rm -rf` to wipe
    /// the wrong directory in the guest.
    private static func validateGuestPath(_ path: String) throws {
        let standardized = (path as NSString).standardizingPath
        guard !standardized.contains("..") else {
            throw SyncError.invalidGuestPath(path)
        }
        for root in allowedGuestPathPrefixes {
            let prefix = root.hasSuffix("/") ? root : root + "/"
            if standardized.hasPrefix(prefix) {
                return
            }
        }
        throw SyncError.invalidGuestPath(path)
    }

    /// Tars the host's tracked + untracked-not-ignored files into a
    /// single in-memory `Data`. Filters out paths that don't currently
    /// exist on disk (e.g. deleted-but-still-staged entries) so tar
    /// doesn't bail with `No such file or directory`.
    private static func buildHostTar(at worktree: URL) throws -> Data {
        let files = try gitTrackedAndUntracked(in: worktree)
        let existing = files.filter { relative in
            FileManager.default.fileExists(atPath: worktree.appendingPathComponent(relative).path)
        }

        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["--null", "-T", "-", "-cf", "-"]
        tar.currentDirectoryURL = worktree
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        tar.standardInput = stdin
        tar.standardOutput = stdout
        tar.standardError = stderr

        try tar.run()

        // Feed the NUL-separated relative paths to tar's --null -T -.
        // Writing on a background thread isn't necessary here because
        // tar buffers in libarchive's internal queue and the path list
        // is small even for huge worktrees.
        let listData = existing
            .map { Data(($0).utf8) + Data([0]) }
            .reduce(Data(), +)
        do {
            try stdin.fileHandleForWriting.write(contentsOf: listData)
            try stdin.fileHandleForWriting.close()
        } catch {
            tar.terminate()
            tar.waitUntilExit()
            throw SyncError.hostTarFailed(stderr: error.localizedDescription)
        }

        let tarData = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
        let errData = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
        tar.waitUntilExit()
        if tar.terminationStatus != 0 {
            throw SyncError.hostTarFailed(stderr: String(decoding: errData, as: UTF8.self))
        }
        return tarData
    }

    /// Runs `git ls-files --cached --others --exclude-standard -z`
    /// in the host worktree and returns the (gitignore-respecting)
    /// path set as relative paths.
    private static func gitTrackedAndUntracked(in worktree: URL) throws -> Set<String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "-C", worktree.path,
            "ls-files",
            "--cached", "--others",
            "--exclude-standard",
            "-z"
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let outData = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
        let errData = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw SyncError.hostListFailed(stderr: String(decoding: errData, as: UTF8.self))
        }
        let text = String(decoding: outData, as: UTF8.self)
        let parts = text.split(separator: "\0", omittingEmptySubsequences: true)
        return Set(parts.map(String.init))
    }

    /// Parses the NUL-separated `find ... -print0` output emitted by
    /// the guest's pull script. Paths come in as `./<relative>` form;
    /// the leading `./` is stripped before returning.
    private static func parseFindNullList(_ data: Data) -> Set<String> {
        let text = String(decoding: data, as: UTF8.self)
        let parts = text.split(separator: "\0", omittingEmptySubsequences: true)
        return Set(parts.map { raw -> String in
            let s = String(raw)
            if s.hasPrefix("./") { return String(s.dropFirst(2)) }
            return s
        })
    }

    /// Writes the supplied tar bytes to a temp file and runs `tar -xf`
    /// rooted at `target`, overwriting any existing files. The caller
    /// is responsible for having pre-deleted host files that the
    /// guest no longer has.
    private static func extractTarOnHost(_ data: Data, into target: URL) throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("compass-sync-pull-\(UUID().uuidString).tar")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xf", tempURL.path, "-C", target.path]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        let errData = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw SyncError.hostExtractFailed(stderr: String(decoding: errData, as: UTF8.self))
        }
    }
}
