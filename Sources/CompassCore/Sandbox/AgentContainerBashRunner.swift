import CompassSandbox
import Foundation

package struct AgentContainerBashRunner: AgentBashRunner {
  package var sandbox: ContainerizedLinuxSandbox
  package var repoRoot: URL
  package var label: String

  package init(
    sandbox: ContainerizedLinuxSandbox = .shared,
    repoRoot: URL,
    label: String = "agent"
  ) {
    self.sandbox = sandbox
    self.repoRoot = repoRoot.standardizedFileURL
    self.label = label
  }

  package func run(
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
