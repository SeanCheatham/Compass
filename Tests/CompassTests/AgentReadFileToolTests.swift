import Foundation
import Testing

@testable import Compass

final class AgentReadFileToolTests {
  private var temporaryDirectory: URL!
  private let tool = AgentReadFileTool()

  init() {
    temporaryDirectory = try! makeTempDir()
  }

  deinit {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
  }

  @Test func testReadsFullFileWithLineNumbers() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("hello.txt")
    try "alpha\nbeta\ngamma".write(to: fileURL, atomically: true, encoding: .utf8)

    let context = AgentToolContext(workingDirectory: temporaryDirectory)
    let result = try await invoke(["path": "hello.txt"], context: context)

    try #require(!result.isError)
    try #require(result.content.contains("     1\talpha"))
    try #require(result.content.contains("     2\tbeta"))
    try #require(result.content.contains("     3\tgamma"))
  }

  @Test func testOffsetAndLimitNarrowTheSlice() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("rows.txt")
    let lines = (1...10).map { "row\($0)" }.joined(separator: "\n")
    try lines.write(to: fileURL, atomically: true, encoding: .utf8)

    let context = AgentToolContext(workingDirectory: temporaryDirectory)
    let result = try await invoke(
      [
        "path": "rows.txt",
        "offset": 3,
        "limit": 2,
      ], context: context)

    try #require(!result.isError)
    try #require(result.content.contains("     3\trow3"))
    try #require(result.content.contains("     4\trow4"))
    try #require(!result.content.contains("row5"))
    try #require(result.content.contains("6 more lines"))
  }

  @Test func testAcceptsCommonPathAndLineAliasesFromLessCapableModels() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("aliases.txt")
    let lines = (1...5).map { "alias\($0)" }.joined(separator: "\n")
    try lines.write(to: fileURL, atomically: true, encoding: .utf8)

    let context = AgentToolContext(workingDirectory: temporaryDirectory)
    let result = try await invoke(
      [
        "file_path": "aliases.txt",
        "start_line": "2",
        "line_count": "2",
      ], context: context)

    try #require(!result.isError)
    try #require(result.content.contains("     2\talias2"))
    try #require(result.content.contains("     3\talias3"))
    try #require(!result.content.contains("alias4"))
  }

  @Test func testMissingPathReportsRepairableFieldName() async throws {
    let context = AgentToolContext(workingDirectory: temporaryDirectory)
    let result = try await invoke([:], context: context)

    try #require(result.isError)
    try #require(result.errorKind == .invalidArguments)
    try #require(result.content.contains("Missing required field `path`"))
  }

  @Test func testRejectsBinaryFiles() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("binary.bin")
    try Data([0x89, 0x00, 0x01, 0xFF, 0x00]).write(to: fileURL)

    let context = AgentToolContext(workingDirectory: temporaryDirectory)
    let result = try await invoke(["path": "binary.bin"], context: context)

    try #require(result.isError)
    try #require(result.content.contains("binary"))
  }

  @Test func testRejectsPathsThatEscapeTheWorkingDirectory() async throws {
    let context = AgentToolContext(workingDirectory: temporaryDirectory)
    let result = try await invoke(["path": "../escape.txt"], context: context)
    try #require(result.isError)
    try #require(result.content.contains("escapes"))
  }

  @Test func testReportsMissingFile() async throws {
    let context = AgentToolContext(workingDirectory: temporaryDirectory)
    let result = try await invoke(["path": "ghost.txt"], context: context)
    try #require(result.isError)
    try #require(result.content.contains("not found"))
  }

  @Test func testOffsetPastEndReturnsFriendlyMessage() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("short.txt")
    try "only".write(to: fileURL, atomically: true, encoding: .utf8)

    let context = AgentToolContext(workingDirectory: temporaryDirectory)
    let result = try await invoke(
      [
        "path": "short.txt",
        "offset": 100,
      ], context: context)

    try #require(!result.isError)
    try #require(result.content.contains("past the end"))
  }

  @Test func testRejectsDirectoryAsRegularFile() async throws {
    let subdir = temporaryDirectory.appendingPathComponent("sub")
    try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: false)

    let context = AgentToolContext(workingDirectory: temporaryDirectory)
    let result = try await invoke(["path": "sub"], context: context)
    try #require(result.isError)
    try #require(result.content.contains("Not a regular file"))
  }

  fileprivate func invoke(_ args: [String: Any], context: AgentToolContext) async throws
    -> AgentToolInvocationResult
  {
    let data = try JSONSerialization.data(withJSONObject: args)
    return try await tool.invoke(arguments: data, context: context)
  }
}
