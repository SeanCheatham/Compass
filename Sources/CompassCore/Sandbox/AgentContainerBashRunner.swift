import CompassSandbox
import Foundation

struct AgentContainerBashRunner: AgentBashRunner {
  var sandbox: ContainerizedLinuxSandbox
  var repoRoot: URL
  var label: String

  init(
    sandbox: ContainerizedLinuxSandbox = .shared,
    repoRoot: URL,
    label: String = "agent"
  ) {
    self.sandbox = sandbox
    self.repoRoot = repoRoot.standardizedFileURL
    self.label = label
  }

  func run(
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
