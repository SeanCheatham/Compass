import Foundation
import Testing

@testable import Compass

struct AgentReadFileToolTests {
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

    #require(!result.isError)
    #require(result.content.contains("     1\talpha"))
    #require(result.content.contains("     2\tbeta"))
    #require(result.content.contains("     3\tgamma"))
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

    #require(!result.isError)
    #require(result.content.contains("     3\trow3"))
    #require(result.content.contains("     4\trow4"))
    #require(!result.content.contains("row5"))
    #require(result.content.contains("6 more lines"))
  }

  @Test func testRejectsBinaryFiles() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("binary.bin")
    try Data([0x89, 0x00, 0x01, 0xFF, 0x00]).write(to: fileURL)

    let context = AgentToolContext(workingDirectory: temporaryDirectory)
    let result = try await invoke(["path": "binary.bin"], context: context)

    #require(result.isError)
    #require(result.content.contains("binary"))
  }

  @Test func testRejectsPathsThatEscapeTheWorkingDirectory() async throws {
    let context = AgentToolContext(workingDirectory: temporaryDirectory)
    let result = try await invoke(["path": "../escape.txt"], context: context)
    #require(result.isError)
    #require(result.content.contains("escapes"))
  }

  @Test func testReportsMissingFile() async throws {
    let context = AgentToolContext(workingDirectory: temporaryDirectory)
    let result = try await invoke(["path": "ghost.txt"], context: context)
    #require(result.isError)
    #require(result.content.contains("not found"))
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

    #require(!result.isError)
    #require(result.content.contains("past the end"))
  }

  @Test func testRejectsDirectoryAsRegularFile() async throws {
    let subdir = temporaryDirectory.appendingPathComponent("sub")
    try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: false)

    let context = AgentToolContext(workingDirectory: temporaryDirectory)
    let result = try await invoke(["path": "sub"], context: context)
    #require(result.isError)
    #require(result.content.contains("Not a regular file"))
  }

  fileprivate func invoke(_ args: [String: Any], context: AgentToolContext) async throws
    -> AgentToolInvocationResult
  {
    let data = try JSONSerialization.data(withJSONObject: args)
    return try await tool.invoke(arguments: data, context: context)
  }
}

fileprivate func makeTempDir(file: StaticString = #file, line: UInt = #line) throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("CompassAgentToolTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url.standardizedFileURL
}