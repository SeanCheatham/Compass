import Foundation

/// SSH helpers for the Compass shared VM guest.
///
/// This type does NOT spawn processes itself — it builds the argument vectors
/// that the existing Compass process plumbing (`CodexExecutor.runCodex`) will
/// feed to `/usr/bin/ssh`. The probe helper (`probeSSHAvailable`) uses a tiny
/// `Process` wrapper internally for the readiness gate; that is the only
/// `Process` use in this file.
///
/// Building argv at this layer keeps `codexInvocation(...)` for `.sharedVM`
/// out of the SSH-options business.
struct SharedCompassVMGuestBridge {
    /// Where Compass-managed `ssh` binaries / config live by default.
    static let defaultSSHExecutablePath = "/usr/bin/ssh"

    /// Tuneable options that affect every ssh invocation Compass makes.
    struct ConnectionOptions: Equatable {
        var executablePath: String
        var identityFile: String?
        var knownHostsFile: String?
        var strictHostKeyChecking: Bool
        var batchMode: Bool
        /// Disables PTY allocation (-T). Always set for non-interactive codex execs.
        var disablePseudoTerminal: Bool
        /// Optional ConnectTimeout (seconds). Used for probes.
        var connectTimeoutSeconds: Int?

        init(
            executablePath: String = SharedCompassVMGuestBridge.defaultSSHExecutablePath,
            identityFile: String? = nil,
            knownHostsFile: String? = nil,
            strictHostKeyChecking: Bool = true,
            batchMode: Bool = true,
            disablePseudoTerminal: Bool = true,
            connectTimeoutSeconds: Int? = nil
        ) {
            self.executablePath = executablePath
            self.identityFile = identityFile
            self.knownHostsFile = knownHostsFile
            self.strictHostKeyChecking = strictHostKeyChecking
            self.batchMode = batchMode
            self.disablePseudoTerminal = disablePseudoTerminal
            self.connectTimeoutSeconds = connectTimeoutSeconds
        }
    }

    /// Builds the `[String]` argv to invoke a remote command on the guest.
    ///
    /// Result is the argument vector NOT including the executable. The
    /// `Process.executableURL` should be set to `options.executablePath`.
    ///
    /// Layout:
    ///   `[-i <identity>] [-o UserKnownHostsFile=<...>] [-o StrictHostKeyChecking=yes]`
    ///   `[-o BatchMode=yes] [-o ConnectTimeout=N] [-T] <destination> <remoteCommand>`
    static func sshArguments(
        destination: String,
        remoteCommand: String,
        options: ConnectionOptions = ConnectionOptions()
    ) -> [String] {
        var arguments: [String] = []
        if let identity = options.identityFile, !identity.isEmpty {
            arguments.append(contentsOf: ["-i", identity])
        }
        if let knownHosts = options.knownHostsFile, !knownHosts.isEmpty {
            arguments.append(contentsOf: ["-o", "UserKnownHostsFile=\(knownHosts)"])
        }
        arguments.append(contentsOf: [
            "-o", "StrictHostKeyChecking=\(options.strictHostKeyChecking ? "yes" : "no")"
        ])
        if options.batchMode {
            arguments.append(contentsOf: ["-o", "BatchMode=yes"])
        }
        if let timeout = options.connectTimeoutSeconds {
            arguments.append(contentsOf: ["-o", "ConnectTimeout=\(timeout)"])
        }
        if options.disablePseudoTerminal {
            arguments.append("-T")
        }
        arguments.append(destination)
        arguments.append(remoteCommand)
        return arguments
    }

    /// Builds the remote command segment that runs codex inside the guest.
    /// Encapsulates the `cd <workspace> && env VAR=val ... <codexPath> <args...>`
    /// shape so callers don't have to repeat shell quoting rules.
    ///
    /// `codexArguments` are quoted with single-quote-safe POSIX rules.
    static func buildRemoteCodexCommand(
        guestWorkspacePath: String,
        guestCodexPath: String,
        environmentVariables: [String: String],
        codexArguments: [String]
    ) -> String {
        let workspaceQuoted = posixQuote(guestWorkspacePath)
        let codexQuoted = posixQuote(guestCodexPath)
        var envPrefix = ""
        if !environmentVariables.isEmpty {
            let envParts = environmentVariables
                .sorted(by: { $0.key < $1.key })
                .map { "\(posixQuote($0.key))=\(posixQuote($0.value))" }
            envPrefix = "env \(envParts.joined(separator: " ")) "
        }
        let argsQuoted = codexArguments.map(posixQuote).joined(separator: " ")
        return "cd \(workspaceQuoted) && \(envPrefix)\(codexQuoted) \(argsQuoted)"
    }

    /// POSIX-safe single-quote escaping. Wraps any string in single quotes and
    /// emits the well-known `'\''` escape for embedded single quotes.
    static func posixQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        // Fast path: safe identifier characters need no quoting.
        let safeCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "._-/=@:%+,"))
        if value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return value
        }
        var escaped = "'"
        for ch in value {
            if ch == "'" {
                escaped.append("'\\''")
            } else {
                escaped.append(ch)
            }
        }
        escaped.append("'")
        return escaped
    }

    // MARK: - SSH probe

    /// Lightweight readiness probe. Returns `true` if `ssh <host> true` exits 0
    /// within `timeout` seconds; otherwise returns `false`. Never throws.
    ///
    /// Used by the first-boot gate. The probe is deliberately bounded — it does
    /// not retry internally; callers wrap it in a loop with their own budget.
    static func probeSSHAvailable(
        destination: String,
        options: ConnectionOptions,
        timeout: TimeInterval = 5
    ) async -> Bool {
        var probeOptions = options
        probeOptions.connectTimeoutSeconds = max(1, Int(timeout.rounded(.up)))
        let arguments = sshArguments(
            destination: destination,
            remoteCommand: "true",
            options: probeOptions
        )
        return await Task.detached { () -> Bool in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: probeOptions.executablePath)
            process.arguments = arguments
            let devNull = FileHandle.nullDevice
            process.standardOutput = devNull
            process.standardError = devNull
            process.standardInput = devNull
            do {
                try process.run()
            } catch {
                return false
            }
            // Bound the wait to the supplied timeout.
            let deadline = Date().addingTimeInterval(timeout + 1)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if process.isRunning {
                process.terminate()
                return false
            }
            return process.terminationStatus == 0
        }.value
    }
}
