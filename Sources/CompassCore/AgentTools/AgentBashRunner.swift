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
/// working directory. Used for host-side maintenance (codemap listing,
/// preflight commit) while factory phases use `AgentContainerBashRunner`.
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
