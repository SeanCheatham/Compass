import Foundation

/// Execution backend for `AgentBashTool`. Lets us swap host-side
/// `/bin/zsh -lc` for an SSH bridge into the Shared VM without the tool
/// itself knowing the difference.
protocol AgentBashRunner: Sendable {
    func run(
        command: String,
        workingDirectory: URL,
        timeout: TimeInterval
    ) async throws -> ProcessResult
}

/// Runs the command in a `/bin/zsh -lc` subshell on the host, in the given
/// working directory.
struct AgentHostBashRunner: AgentBashRunner {
    let shellPath: String

    init(shellPath: String = "/bin/zsh") {
        self.shellPath = shellPath
    }

    func run(
        command: String,
        workingDirectory: URL,
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        try await ProcessRunner.run(
            executable: shellPath,
            arguments: ["-lc", command],
            workingDirectory: workingDirectory,
            timeout: timeout
        )
    }
}

/// Runs the command inside the Shared VM guest by SSH-invoking `zsh -lc` at
/// the supplied working directory, which must already be a guest-namespace
/// path (the agent context's `workingDirectory` is set to the guest workspace
/// URL when the Shared VM route is active, so all `cwd` paths the model
/// supplies — or that the agent resolves through `context.resolvePath` —
/// are already in the right namespace).
struct AgentSharedVMBashRunner: AgentBashRunner {
    let route: SharedVMRoute
    let sshExecutablePath: String

    init(
        route: SharedVMRoute,
        sshExecutablePath: String = SharedCompassVMGuestBridge.defaultSSHExecutablePath
    ) {
        self.route = route
        self.sshExecutablePath = sshExecutablePath
    }

    func run(
        command: String,
        workingDirectory: URL,
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        let remoteCommand = Self.buildRemoteCommand(
            guestPath: workingDirectory.path,
            command: command,
            environmentVariables: route.environmentVariables
        )
        let options = SharedCompassVMGuestBridge.ConnectionOptions(
            executablePath: sshExecutablePath,
            identityFile: route.identityFile,
            knownHostsFile: route.knownHostsFile
        )
        let arguments = SharedCompassVMGuestBridge.sshArguments(
            destination: route.sshDestination,
            remoteCommand: remoteCommand,
            options: options
        )
        return try await ProcessRunner.run(
            executable: options.executablePath,
            arguments: arguments,
            timeout: timeout
        )
    }

    /// Build the remote-shell payload. `cd <guestPath> && [env …] /bin/zsh -lc <quoted command>`.
    /// Mirrors `AgentExecutionLaunchPlan.shellInvocation` so the wire format
    /// stays consistent with the existing SSH bridge.
    static func buildRemoteCommand(
        guestPath: String,
        command: String,
        environmentVariables: [String: String] = [:]
    ) -> String {
        let workspaceQuoted = SharedCompassVMGuestBridge.posixQuote(guestPath)
        var envPrefix = ""
        if !environmentVariables.isEmpty {
            let envParts = environmentVariables
                .sorted(by: { $0.key < $1.key })
                .map { "\(SharedCompassVMGuestBridge.posixQuote($0.key))=\(SharedCompassVMGuestBridge.posixQuote($0.value))" }
            envPrefix = "env \(envParts.joined(separator: " ")) "
        }
        let commandQuoted = SharedCompassVMGuestBridge.posixQuote(command)
        return "cd \(workspaceQuoted) && \(envPrefix)/bin/zsh -lc \(commandQuoted)"
    }
}
