import Foundation

/// Execution backend for `AgentBashTool`. Today the only concrete runner is
/// host-side; the Shared VM transport will land alongside the vsock guest
/// agent (see Sources/Compass/SharedVM/README.md) and conform to this same
/// protocol so the tool layer above doesn't have to learn about it.
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
