import Foundation

/// Execution backend for `AgentBashTool`.
protocol AgentBashRunner: Sendable {
  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult
}

/// Runs the command in a `/bin/zsh -lc` subshell on the host, in the given
/// working directory. Agent phases use `AgentContainerBashRunner`; this
/// remains for host-side maintenance probes.
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
