import CompassSandbox
import Foundation

public struct AgentContainerBashRunner: AgentBashRunner {
  public var sandbox: ContainerizedLinuxSandbox
  public var repoRoot: URL
  public var label: String

  public init(
    sandbox: ContainerizedLinuxSandbox = .shared,
    repoRoot: URL,
    label: String = "agent"
  ) {
    self.sandbox = sandbox
    self.repoRoot = repoRoot.standardizedFileURL
    self.label = label
  }

  public func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    let result = try await sandbox.run(
      ContainerSandboxRunRequest(
        command: command,
        hostRepoRoot: repoRoot,
        hostWorkingDirectory: workingDirectory,
        timeout: timeout,
        label: label
      )
    )
    return ProcessResult(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr)
  }
}
