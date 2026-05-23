import Foundation
import XCTest

@testable import Compass

final class AgentBashRunnerTests: XCTestCase {

  // MARK: - HostBashRunner

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
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(result.stdout, "marker")
  }

  // MARK: - AgentBashTool wires the runner

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
    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("from-runner"))
    XCTAssertEqual(runner.lastCommand, "echo hello")
    XCTAssertEqual(runner.lastWorkingDirectory?.standardizedFileURL, tempDir)
    XCTAssertEqual(runner.lastTimeout, 5)
  }
}
