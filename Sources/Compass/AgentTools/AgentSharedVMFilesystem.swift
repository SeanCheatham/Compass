import Foundation

/// Filesystem implementation that talks to the Compass Shared VM guest over
/// SSH. Every op is a single `ssh user@host '<remote-script>'` invocation;
/// the underlying TCP/SSH session is multiplexed by `ControlMaster=auto`
/// (wired in `SharedCompassVMGuestBridge.sshArguments`) so the per-call cost
/// is a new channel, not a fresh handshake.
///
/// Paths handed to this filesystem must already be in the guest's namespace
/// (e.g. `/opt/compass/workspaces/.../worktree/Sources/Foo.swift`). The
/// caller wires `AgentToolContext.workingDirectory` to a URL pointing at the
/// guest workspace root so `resolvePath` returns guest-absolute URLs.
struct AgentSharedVMFilesystem: AgentFilesystem {
    /// Exit codes the inline remote scripts use so the Swift side can
    /// translate ssh's exit status into a typed `AgentFilesystemError`.
    /// Values chosen in the 64–78 range (BSD sysexits) so they don't
    /// collide with ssh's own 255 ("transport error") or common 0/1/2.
    enum RemoteExitCode {
        static let notFound: Int32 = 64
        static let notRegularFile: Int32 = 65
        static let notDirectory: Int32 = 66
        static let sshTransportFailure: Int32 = 255
    }

    /// Runs the ssh argv, optionally with stdin, and returns a ProcessResult.
    /// Injected so tests can swap in a stub without spawning `/usr/bin/ssh`.
    typealias RemoteRunner = @Sendable (
        _ arguments: [String],
        _ stdin: String?,
        _ timeout: TimeInterval
    ) async throws -> ProcessResult

    let route: SharedVMRoute
    let sshExecutablePath: String
    let perCallTimeout: TimeInterval
    let remoteRunner: RemoteRunner

    init(
        route: SharedVMRoute,
        sshExecutablePath: String = SharedCompassVMGuestBridge.defaultSSHExecutablePath,
        perCallTimeout: TimeInterval = 60,
        remoteRunner: RemoteRunner? = nil
    ) {
        self.route = route
        self.sshExecutablePath = sshExecutablePath
        self.perCallTimeout = perCallTimeout
        if let remoteRunner {
            self.remoteRunner = remoteRunner
        } else {
            let executable = sshExecutablePath
            self.remoteRunner = { arguments, stdin, timeout in
                try await ProcessRunner.run(
                    executable: executable,
                    arguments: arguments,
                    input: stdin,
                    timeout: timeout
                )
            }
        }
    }

    // MARK: - AgentFilesystem

    func readFile(at url: URL) async throws -> Data {
        let path = url.path
        let script = """
        set -u
        p=\(quote(path))
        if [ ! -e "$p" ]; then exit \(RemoteExitCode.notFound); fi
        if [ -d "$p" ]; then exit \(RemoteExitCode.notRegularFile); fi
        base64 < "$p"
        """
        let result = try await runRemote(script: script)
        switch result.exitCode {
        case 0:
            let cleaned = result.stdout.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
            guard let data = Data(base64Encoded: String(String.UnicodeScalarView(cleaned))) else {
                throw AgentFilesystemError.ioFailure("base64 decode failed for \(path)")
            }
            return data
        case RemoteExitCode.notFound:
            throw AgentFilesystemError.notFound(url)
        case RemoteExitCode.notRegularFile:
            throw AgentFilesystemError.notRegularFile(url)
        case RemoteExitCode.sshTransportFailure:
            throw AgentFilesystemError.transportFailure(trimStderr(result.stderr))
        default:
            throw AgentFilesystemError.ioFailure(trimStderr(result.stderr).nonEmptyOrFallback("readFile exited \(result.exitCode)"))
        }
    }

    func writeFile(_ data: Data, at url: URL) async throws {
        let path = url.path
        // Atomic write: stage into a sibling tempfile, fsync via `mv`. The
        // EXIT/INT/TERM trap cleans up the temp if base64 or mv fails so
        // we never leave a half-written sibling next to the target.
        let script = """
        set -u
        p=\(quote(path))
        if [ -d "$p" ]; then exit \(RemoteExitCode.notRegularFile); fi
        parent=$(dirname -- "$p")
        mkdir -p -- "$parent" || exit 70
        tmp="$p.compass-tmp.$$"
        trap 'rm -f -- "$tmp"' EXIT INT TERM
        base64 -d > "$tmp" || exit 71
        mv -- "$tmp" "$p" || exit 72
        trap - EXIT INT TERM
        """
        let base64 = data.base64EncodedString()
        let result = try await runRemote(script: script, stdin: base64)
        switch result.exitCode {
        case 0:
            return
        case RemoteExitCode.notRegularFile:
            throw AgentFilesystemError.notRegularFile(url)
        case RemoteExitCode.sshTransportFailure:
            throw AgentFilesystemError.transportFailure(trimStderr(result.stderr))
        default:
            throw AgentFilesystemError.ioFailure(trimStderr(result.stderr).nonEmptyOrFallback("writeFile exited \(result.exitCode)"))
        }
    }

    func metadata(of url: URL) async throws -> FileMetadata? {
        let path = url.path
        // BSD vs GNU stat have incompatible flags. Try BSD's `-f` first and
        // fall back to GNU's `-c` so this works on both a macOS and a Linux
        // guest. Output is `type|size|mtime-epoch`.
        let script = """
        set -u
        p=\(quote(path))
        if [ ! -e "$p" ]; then exit \(RemoteExitCode.notFound); fi
        if [ -d "$p" ]; then t=d; else t=f; fi
        s=$(stat -f %z "$p" 2>/dev/null) || s=$(stat -c %s "$p" 2>/dev/null) || s=0
        m=$(stat -f %m "$p" 2>/dev/null) || m=$(stat -c %Y "$p" 2>/dev/null) || m=0
        printf '%s|%s|%s\\n' "$t" "$s" "$m"
        """
        let result = try await runRemote(script: script)
        switch result.exitCode {
        case 0:
            let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else {
                throw AgentFilesystemError.ioFailure("stat output malformed: \(trimmed)")
            }
            let isDir = parts[0] == "d"
            let size = Int(parts[1])
            let mtime = Double(parts[2]).map { Date(timeIntervalSince1970: $0) }
            return FileMetadata(
                url: url,
                isDirectory: isDir,
                isRegularFile: !isDir,
                size: size,
                modificationDate: mtime
            )
        case RemoteExitCode.notFound:
            return nil
        case RemoteExitCode.sshTransportFailure:
            throw AgentFilesystemError.transportFailure(trimStderr(result.stderr))
        default:
            throw AgentFilesystemError.ioFailure(trimStderr(result.stderr).nonEmptyOrFallback("metadata exited \(result.exitCode)"))
        }
    }

    func listDirectory(at url: URL) async throws -> [DirectoryEntry] {
        let path = url.path
        // `find -mindepth 1 -maxdepth 1` is portable across BSD + GNU find.
        // We emit two streams (one per type) so the host doesn't need to
        // re-stat anything. NUL-separated so names with spaces survive.
        let script = """
        set -u
        p=\(quote(path))
        if [ ! -e "$p" ]; then exit \(RemoteExitCode.notFound); fi
        if [ ! -d "$p" ]; then exit \(RemoteExitCode.notDirectory); fi
        ( find "$p" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null \
            | awk -v RS='\\0' '{print "d\\t" $0}'
          find "$p" -mindepth 1 -maxdepth 1 ! -type d -print0 2>/dev/null \
            | awk -v RS='\\0' '{print "f\\t" $0}' )
        """
        let result = try await runRemote(script: script)
        switch result.exitCode {
        case 0:
            return parseListing(stdout: result.stdout, parentPath: path)
        case RemoteExitCode.notFound:
            throw AgentFilesystemError.notFound(url)
        case RemoteExitCode.notDirectory:
            throw AgentFilesystemError.notDirectory(url)
        case RemoteExitCode.sshTransportFailure:
            throw AgentFilesystemError.transportFailure(trimStderr(result.stderr))
        default:
            throw AgentFilesystemError.ioFailure(trimStderr(result.stderr).nonEmptyOrFallback("listDirectory exited \(result.exitCode)"))
        }
    }

    func glob(pattern: String, under rootURL: URL, walkCap: Int) async throws -> [GlobMatch] {
        let rootPath = rootURL.path
        // Walk the tree once on the guest, returning `mtime-epoch<TAB>path`
        // lines, capped at walkCap. Glob matching happens on the host so
        // we reuse the exact same `AgentGlobPattern` regex semantics as the
        // host filesystem — no need to bridge POSIX/PCRE regex differences.
        let cap = max(1, walkCap)
        let script = """
        set -u
        p=\(quote(rootPath))
        if [ ! -d "$p" ]; then exit \(RemoteExitCode.notDirectory); fi
        find "$p" -type f -print0 2>/dev/null \
            | xargs -0 stat -f '%m\\t%N' 2>/dev/null \
            | head -n \(cap) \
            || find "$p" -type f -print0 2>/dev/null \
                | xargs -0 stat -c '%Y\\t%n' 2>/dev/null \
                | head -n \(cap)
        """
        let result = try await runRemote(script: script)
        switch result.exitCode {
        case 0:
            return try filterGlobOutput(result.stdout, pattern: pattern, rootPath: rootPath)
        case RemoteExitCode.notDirectory:
            throw AgentFilesystemError.notDirectory(rootURL)
        case RemoteExitCode.sshTransportFailure:
            throw AgentFilesystemError.transportFailure(trimStderr(result.stderr))
        default:
            throw AgentFilesystemError.ioFailure(trimStderr(result.stderr).nonEmptyOrFallback("glob exited \(result.exitCode)"))
        }
    }

    func grep(
        pattern: String,
        in url: URL,
        glob: String?,
        caseInsensitive: Bool,
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        let targetPath = url.path
        // Quote anything the model could've supplied (pattern, glob) so it
        // can't be re-parsed by the remote shell — globs like `*.swift`
        // would otherwise expand against the guest's cwd before ripgrep
        // ever sees them.
        var rgFlags = ["--no-config", "--with-filename", "--line-number", "--color", "never"]
        if caseInsensitive { rgFlags.append("--ignore-case") }
        if let glob, !glob.isEmpty { rgFlags += ["--glob", quote(glob)] }
        var grepFlags = ["-rnE"]
        if caseInsensitive { grepFlags.append("-i") }
        if let glob, !glob.isEmpty { grepFlags += ["--include=\(quote(glob))"] }

        let rgInvocation = (["rg"] + rgFlags + [quote(pattern), quote(targetPath)]).joined(separator: " ")
        let grepInvocation = (["grep"] + grepFlags + ["--", quote(pattern), quote(targetPath)]).joined(separator: " ")

        // Prefer ripgrep when the guest has it; fall back to BSD/GNU grep
        // otherwise. We pass the exit code through unchanged so the calling
        // tool's "exit 1 == no matches" handling keeps working.
        let script = """
        if command -v rg >/dev/null 2>&1; then
          \(rgInvocation)
        else
          \(grepInvocation)
        fi
        """
        return try await runRemote(script: script, timeout: timeout)
    }

    // MARK: - SSH plumbing

    private func runRemote(
        script: String,
        stdin: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        let options = SharedCompassVMGuestBridge.ConnectionOptions(
            executablePath: sshExecutablePath,
            identityFile: route.identityFile,
            knownHostsFile: route.knownHostsFile
        )
        let arguments = SharedCompassVMGuestBridge.sshArguments(
            destination: route.sshDestination,
            remoteCommand: script,
            options: options
        )
        do {
            return try await remoteRunner(arguments, stdin, timeout ?? perCallTimeout)
        } catch {
            throw AgentFilesystemError.transportFailure(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func quote(_ s: String) -> String {
        SharedCompassVMGuestBridge.posixQuote(s)
    }

    private func trimStderr(_ stderr: String) -> String {
        stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseListing(stdout: String, parentPath: String) -> [DirectoryEntry] {
        var entries: [DirectoryEntry] = []
        let parentPrefix = parentPath.hasSuffix("/") ? parentPath : parentPath + "/"
        for line in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let kind = parts[0]
            let absolute = String(parts[1])
            let name: String
            if absolute.hasPrefix(parentPrefix) {
                name = String(absolute.dropFirst(parentPrefix.count))
            } else {
                name = (absolute as NSString).lastPathComponent
            }
            entries.append(DirectoryEntry(
                url: URL(fileURLWithPath: absolute),
                name: name,
                isDirectory: kind == "d"
            ))
        }
        return entries
    }

    private func filterGlobOutput(
        _ stdout: String,
        pattern: String,
        rootPath: String
    ) throws -> [GlobMatch] {
        let regex: NSRegularExpression
        do {
            regex = try AgentGlobPattern.regex(forGlob: pattern)
        } catch {
            throw AgentFilesystemError.ioFailure("invalid glob pattern: \(error.localizedDescription)")
        }
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        var matches: [GlobMatch] = []
        for line in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let mtimeEpoch = Double(parts[0])
            let absolute = String(parts[1])
            let relative: String
            if absolute == rootPath {
                relative = "."
            } else if absolute.hasPrefix(rootPrefix) {
                relative = String(absolute.dropFirst(rootPrefix.count))
            } else {
                relative = absolute
            }
            let nsRelative = relative as NSString
            let range = NSRange(location: 0, length: nsRelative.length)
            if regex.firstMatch(in: relative, options: [], range: range) == nil { continue }
            matches.append(GlobMatch(
                url: URL(fileURLWithPath: absolute),
                modificationDate: mtimeEpoch.map { Date(timeIntervalSince1970: $0) }
            ))
        }
        return matches
    }
}

private extension String {
    func nonEmptyOrFallback(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
