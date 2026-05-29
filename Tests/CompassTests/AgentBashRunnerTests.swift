import Foundation
import Testing

@testable import Compass

struct AgentBashRunnerTests {

  // MARK: - HostBashRunner

  @Test
  func testHostBashRunnerExecutesCommandInWorkingDirectory() async throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    try "marker".write(
      to: tempDir.appendingPathComponent("flag.txt"),
      atomically: true,
      encoding: .utf8
    )
    let runner = AgentHostBashRunner()
    let result = try await runner.run(
      command: "cat flag.txt",
      workingDirectory: tempDir,
      timeout: 10
    )
    try #require(result.exitCode == 0)
    try #require(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "marker")
  }

  // MARK: - AgentBashTool wires the runner

  @Test
  func testAgentBashToolDispatchesThroughInjectedRunner() async throws {
    final class RecordingRunner: AgentBashRunner, @unchecked Sendable {
      var lastCommand: String?
      var lastWorkingDirectory: URL?
      var lastTimeout: TimeInterval?
      func run(command: String, workingDirectory: URL, timeout: TimeInterval) async throws
        -> ProcessResult
      {
        lastCommand = command
        lastWorkingDirectory = workingDirectory
        lastTimeout = timeout
        return ProcessResult(exitCode: 0, stdout: "from-runner", stderr: "")
      }
    }
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let runner = RecordingRunner()
    let context = AgentToolContext(workingDirectory: tempDir, bashRunner: runner)
    let tool = AgentBashTool()
    let args = try JSONSerialization.data(withJSONObject: [
      "command": "echo hello",
      "timeoutMs": 5000,
    ])
    let result = try await tool.invoke(arguments: args, context: context)
    try #require(!result.isError)
    try #require(result.content.contains("from-runner"))
    try #require(runner.lastCommand == "echo hello")
    try #require(runner.lastWorkingDirectory?.standardizedFileURL == tempDir.standardizedFileURL)
    try #require(runner.lastTimeout == 5)
  }

  // MARK: - Helper

  private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
  }
}
