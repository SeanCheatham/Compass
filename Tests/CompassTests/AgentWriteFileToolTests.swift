import Foundation
import Testing

@testable import Compass

final class AgentWriteFileToolTests {
  private var temporaryDirectory: URL!
  private let tool = AgentWriteFileTool()

  init() {
    temporaryDirectory = try! makeTempDir()
  }

  deinit {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
  }

  @Test func createsNewFile() async throws {
    let result = try await invoke([
      "path": "fresh.txt",
      "content": "hello world",
    ])

    try #require(!result.isError)
    try #require(result.content.contains("wrote 11 bytes to fresh.txt"))
    let written = try String(
      contentsOf: temporaryDirectory.appendingPathComponent("fresh.txt"), encoding: .utf8)
    try #require(written == "hello world")
  }

  @Test func overwritesExistingFileAfterRead() async throws {
    let url = temporaryDirectory.appendingPathComponent("existing.txt")
    try "old".write(to: url, atomically: true, encoding: .utf8)

    let context = AgentToolContext(workingDirectory: temporaryDirectory)
    await context.readTracker.markRead(url)
    let result = try await invoke(
      [
        "path": "existing.txt",
        "content": "new",
      ], context: context)

    try #require(!result.isError)
    let written = try String(contentsOf: url, encoding: .utf8)
    try #require(written == "new")
  }

  @Test func refusesToOverwriteUnreadFile() async throws {
    let url = temporaryDirectory.appendingPathComponent("existing.txt")
    try "old".write(to: url, atomically: true, encoding: .utf8)

    let result = try await invoke([
      "path": "existing.txt",
      "content": "new",
    ])

    try #require(result.isError)
    try #require(result.content.contains("has not been read"))
    try #require(try String(contentsOf: url, encoding: .utf8) == "old")
  }

  @Test func createsIntermediateDirectories() async throws {
    let result = try await invoke([
      "path": "deep/nested/path/file.txt",
      "content": "hi",
    ])

    try #require(!result.isError)
    let url = temporaryDirectory.appendingPathComponent("deep/nested/path/file.txt")
    try #require(try String(contentsOf: url, encoding: .utf8) == "hi")
  }

  @Test func rejectsPathThatEscapesWorkingDirectory() async throws {
    let result = try await invoke([
      "path": "../escape.txt",
      "content": "x",
    ])
    try #require(result.isError)
    try #require(result.content.contains("escapes"))
  }

  @Test func rejectsExistingDirectory() async throws {
    let subdir = temporaryDirectory.appendingPathComponent("blocked")
    try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: false)

    let result = try await invoke([
      "path": "blocked",
      "content": "x",
    ])
    try #require(result.isError)
    try #require(result.content.contains("Not a regular file"))
  }

  private func invoke(
    _ args: [String: Any],
    context: AgentToolContext? = nil
  ) async throws -> AgentToolInvocationResult {
    let data = try JSONSerialization.data(withJSONObject: args)
    return try await tool.invoke(
      arguments: data,
      context: context ?? AgentToolContext(workingDirectory: temporaryDirectory)
    )
  }
}
