import Foundation

/// Execution backend for `AgentBashTool`.
public protocol AgentBashRunner: Sendable {
  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult
}

/// Runs the command in a `/bin/zsh -lc` subshell on the host, in the given
/// working directory. Used only for host-side maintenance (codemap listing,
/// preflight commit). Factory phases always use `AgentMacOSVMBashRunner`.
public struct AgentHostBashRunner: AgentBashRunner {
  public let shellPath: String

  public init(shellPath: String = "/bin/zsh") {
    self.shellPath = shellPath
  }

  public func run(
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
