import Foundation

/// Probes and (best-effort) repairs the codex CLI auth state inside the
/// Compass shared VM guest.
///
/// Heuristic:
///   1. Run `command -v codex` over SSH. If codex is missing, the auth check
///      is `indeterminate` (the guest-prep stage installs codex separately).
///   2. Try `codex auth status` and look at exit code + stdout. Codex's CLI
///      surface is a fast-moving target, so we treat `exit 0` as authenticated
///      and `exit != 0` as a signal to fall through to the file heuristic.
///   3. File heuristic: check whether `~/.codex/auth.json` exists and is
///      non-empty on the guest. Codex persists OAuth tokens there.
///
/// This is intentionally conservative — we only report `.authenticated` when
/// we have positive evidence. Anything ambiguous becomes
/// `.indeterminate(detail:)` so the caller (UI) can prompt the user.
enum SharedCompassVMCodexAuthBridge {
    enum CodexAuthState: Equatable {
        case authenticated
        case unauthenticated
        case indeterminate(detail: String)
    }

    /// Checks the guest's codex auth state over SSH.
    ///
    /// The probe is read-only — it never writes to the guest. On any kind of
    /// SSH or command failure that we cannot map to a clean
    /// authenticated/unauthenticated answer, the result is
    /// `.indeterminate(detail:)`. Never throws.
    static func checkGuestCodexAuth(
        destination: String,
        options: SharedCompassVMGuestBridge.ConnectionOptions,
        sshExecutablePath: String = SharedCompassVMGuestBridge.defaultSSHExecutablePath
    ) async -> CodexAuthState {
        // Step 1: verify codex is on PATH inside the guest.
        let presenceProbe = await runRemote(
            "command -v codex",
            destination: destination,
            options: options,
            sshExecutablePath: sshExecutablePath
        )
        switch presenceProbe {
        case .failure(let detail):
            return .indeterminate(detail: detail)
        case .success(let output):
            if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .indeterminate(detail: "codex binary not found inside guest")
            }
        }

        // Step 2: try the structured CLI probe first.
        let statusProbe = await runRemote(
            "codex auth status 2>&1; echo __exit__=$?",
            destination: destination,
            options: options,
            sshExecutablePath: sshExecutablePath
        )
        if case .success(let stdout) = statusProbe {
            let lines = stdout.split(whereSeparator: \.isNewline).map(String.init)
            if let last = lines.last(where: { $0.hasPrefix("__exit__=") }),
               let code = Int(last.dropFirst("__exit__=".count)),
               code == 0 {
                return .authenticated
            }
        }

        // Step 3: fall back to the auth.json file heuristic.
        // Single-quoted to keep the remote shell from glob-expanding ~/.codex.
        let fileProbe = await runRemote(
            "if [ -s \"$HOME/.codex/auth.json\" ]; then echo present; else echo absent; fi",
            destination: destination,
            options: options,
            sshExecutablePath: sshExecutablePath
        )
        switch fileProbe {
        case .failure(let detail):
            return .indeterminate(detail: detail)
        case .success(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "present" {
                return .authenticated
            }
            if trimmed == "absent" {
                return .unauthenticated
            }
            return .indeterminate(detail: "unexpected file probe output: \(trimmed)")
        }
    }

    /// Errors produced by `copyHostCodexCredentialsToGuest`.
    enum CopyError: Error, CustomStringConvertible {
        case hostCredentialsMissing
        case scpUnavailable
        case scpFailed(exitCode: Int32, stderr: String)
        case remoteMkdirFailed(exitCode: Int32, stderr: String)

        var description: String {
            switch self {
            case .hostCredentialsMissing:
                return "Host has no ~/.codex directory to copy"
            case .scpUnavailable:
                return "/usr/bin/scp is not available on this host"
            case let .scpFailed(code, stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return "scp exited \(code): \(trimmed)"
            case let .remoteMkdirFailed(code, stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return "remote mkdir exited \(code): \(trimmed)"
            }
        }
    }

    /// Copies the host's `~/.codex/` directory to the guest at
    /// `~/.codex/`. Best-effort fallback when the guest probe reports
    /// `.unauthenticated`. Caller is responsible for re-running
    /// `checkGuestCodexAuth` afterwards to confirm the copy was effective.
    static func copyHostCodexCredentialsToGuest(
        destination: String,
        options: SharedCompassVMGuestBridge.ConnectionOptions,
        fileManager: FileManager = .default,
        homeDirectoryURL: URL? = nil,
        scpExecutablePath: String = "/usr/bin/scp",
        sshExecutablePath: String = SharedCompassVMGuestBridge.defaultSSHExecutablePath
    ) async throws {
        let home = homeDirectoryURL ?? fileManager.homeDirectoryForCurrentUser
        let hostCodex = home.appendingPathComponent(".codex", isDirectory: true)
        guard fileManager.fileExists(atPath: hostCodex.path) else {
            throw CopyError.hostCredentialsMissing
        }
        guard fileManager.fileExists(atPath: scpExecutablePath) else {
            throw CopyError.scpUnavailable
        }

        // Ensure the guest's `~/.codex` exists before scp lands files inside it.
        let mkdirResult = await runRemote(
            "mkdir -p \"$HOME/.codex\" && chmod 700 \"$HOME/.codex\"",
            destination: destination,
            options: options,
            sshExecutablePath: sshExecutablePath
        )
        if case .failure(let detail) = mkdirResult {
            throw CopyError.remoteMkdirFailed(exitCode: -1, stderr: detail)
        }

        // Build scp args mirroring the ssh options so the same identity and
        // known-hosts file are used.
        var scpArguments: [String] = ["-r", "-q", "-B"]
        if let identity = options.identityFile, !identity.isEmpty {
            scpArguments.append(contentsOf: ["-i", identity])
        }
        if let knownHosts = options.knownHostsFile, !knownHosts.isEmpty {
            scpArguments.append(contentsOf: ["-o", "UserKnownHostsFile=\(knownHosts)"])
        }
        scpArguments.append(contentsOf: [
            "-o", "StrictHostKeyChecking=\(options.strictHostKeyChecking ? "yes" : "no")"
        ])
        if options.batchMode {
            scpArguments.append(contentsOf: ["-o", "BatchMode=yes"])
        }
        // scp's destination form: <user@host>:<remote-path>. Use trailing slash
        // on the source so we copy the directory contents into the existing
        // `.codex` directory rather than nesting `.codex/.codex/`.
        scpArguments.append("\(hostCodex.path)/")
        scpArguments.append("\(destination):.codex/")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: scpExecutablePath)
        process.arguments = scpArguments
        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = stdoutPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            let message = String(data: data, encoding: .utf8) ?? ""
            throw CopyError.scpFailed(exitCode: process.terminationStatus, stderr: message)
        }
    }

    // MARK: - Internals

    private enum RemoteResult {
        case success(String)
        case failure(String)
    }

    private static func runRemote(
        _ command: String,
        destination: String,
        options: SharedCompassVMGuestBridge.ConnectionOptions,
        sshExecutablePath: String
    ) async -> RemoteResult {
        let arguments = SharedCompassVMGuestBridge.sshArguments(
            destination: destination,
            remoteCommand: command,
            options: options
        )
        return await Task.detached { () -> RemoteResult in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: sshExecutablePath)
            process.arguments = arguments
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return .failure("ssh launch failed: \(error.localizedDescription)")
            }
            process.waitUntilExit()
            let outData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
            let errData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            if process.terminationStatus != 0 {
                let message = String(data: errData, encoding: .utf8) ?? ""
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure("ssh exited \(process.terminationStatus): \(trimmed.isEmpty ? "(no stderr)" : trimmed)")
            }
            return .success(String(data: outData, encoding: .utf8) ?? "")
        }.value
    }
}
