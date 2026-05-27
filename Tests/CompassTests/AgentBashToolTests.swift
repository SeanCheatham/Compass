import Foundation
import Testing

@testable import Compass

final class AgentBashToolTests {
  private var temporaryDirectory: URL!
  private let tool = AgentBashTool()

  init() {
    temporaryDirectory = try! makeTempDir()
  }

  deinit {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
  }

  @Test func testCommandSucceedsAndReportsStdoutAndExit() async throws {
    let result = try await invoke(["command": "echo hello"])
    #require(!result.isError)
    #require(result.content.contains("[stdout]\nhello"))
    #require(result.content.contains("[exit 0]"))
    #require(!result.content.contains("[stderr]"))
  }

  @Test func testCommandStderrIsCapturedSeparately() async throws {
    let result = try await invoke(["command": "echo out; echo err 1>&2; exit 0"])
    #require(!result.isError)
    #require(result.content.contains("[stdout]\nout"))
    #require(result.content.contains("[stderr]\nerr"))
    #require(result.content.contains("[exit 0]"))
  }

  @Test func testNonZeroExitIsReported() async throws {
    let result = try await invoke(["command": "exit 7"])
    #require(!result.isError)
    #require(result.content.contains("[exit 7]"))
  }

  @Test func testCommandRunsInsideWorkingDirectory() async throws {
    try "marker".write(
      to: temporaryDirectory.appendingPathComponent("ping.txt"),
      atomically: true,
      encoding: .utf8
    )
    let result = try await invoke(["command": "cat ping.txt"])
    #require(!result.isError)
    #require(result.content.contains("marker"))
  }

  @Test func testCwdMustResolveInsideWorkingDirectory() async throws {
    let result = try await invoke([
      "command": "pwd",
      "cwd": "../escape",
    ])
    #require(result.isError)
    #require(result.content.contains("escapes"))
  }

  @Test func testCwdSubdirectoryIsHonored() async throws {
    let subdir = temporaryDirectory.appendingPathComponent("inner")
    try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: false)
    try "deep".write(
      to: subdir.appendingPathComponent("file.txt"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await invoke([
      "command": "cat file.txt",
      "cwd": "inner",
    ])
    #require(!result.isError)
    #require(result.content.contains("deep"))
  }

  @Test func testTimeoutTerminatesLongRunningCommand() async throws {
    let result = try await invoke([
      "command": "sleep 5",
      "timeoutMs": 500,
    ])
    #require(!result.isError)
    #require(result.content.contains("timed out"))
  }

  @Test func testEmptyCommandFails() async throws {
    let result = try await invoke(["command": "   "])
    #require(result.isError)
    #require(result.content.contains("command is empty"))
  }

  private func invoke(_ args: [String: Any]) async throws -> AgentToolInvocationResult {
    let data = try JSONSerialization.data(withJSONObject: args)
    return try await tool.invoke(
      arguments: data,
      context: AgentToolContext(workingDirectory: temporaryDirectory)
    )
  }
}