import Foundation

/// Execution backend for `AgentBashTool`.
package protocol AgentBashRunner: Sendable {
  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult
}

/// Runs the command in a `/bin/zsh -lc` subshell on the host, in the given
/// working directory. Agent phases use `AgentContainerBashRunner`; this
/// remains for host-side maintenance probes.
package struct AgentHostBashRunner: AgentBashRunner {
  package let shellPath: String

  package init(shellPath: String = "/bin/zsh") {
    self.shellPath = shellPath
  }

  package func run(
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
