import Foundation
import Testing

@testable import Compass

struct AgentLsToolTests {
  private var temporaryDirectory: URL!
  private let tool = AgentLsTool()

  private mutating func setUp() {
    temporaryDirectory = try! makeTempDir()
  }

  private mutating func tearDown() {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    temporaryDirectory = nil
  }

  @Test
  func listsFilesAndDirectoriesWithTrailingSlashOnDirs() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try "a".write(
      to: test.temporaryDirectory.appendingPathComponent("alpha.txt"), atomically: true,
      encoding: .utf8)
    try "b".write(
      to: test.temporaryDirectory.appendingPathComponent("beta.txt"), atomically: true,
      encoding: .utf8)
    let subdir = test.temporaryDirectory.appendingPathComponent("gamma")
    try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: false)

    let result = try await test.invoke([:])

    try #require(!result.isError)
    let lines = result.content.split(separator: "\n").map(String.init)
    try #require(lines == ["alpha.txt", "beta.txt", "gamma/"])
  }

  @Test
  func listsHiddenEntries() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try "x".write(
      to: test.temporaryDirectory.appendingPathComponent(".compass"), atomically: true,
      encoding: .utf8)
    try "y".write(
      to: test.temporaryDirectory.appendingPathComponent("visible.txt"), atomically: true,
      encoding: .utf8)

    let result = try await test.invoke([:])

    try #require(!result.isError)
    try #require(result.content.contains(".compass"))
    try #require(result.content.contains("visible.txt"))
  }

  @Test
  func emptyDirectoryReportsPlaceholder() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = try await test.invoke([:])
    try #require(!result.isError)
    try #require(result.content == "(empty directory)")
  }

  @Test
  func rejectsPathThatEscapesWorkingDirectory() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = try await test.invoke(["path": "../escape"])
    try #require(result.isError)
    try #require(result.content.contains("escapes"))
  }

  @Test
  func rejectsRegularFile() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try "x".write(
      to: test.temporaryDirectory.appendingPathComponent("file.txt"), atomically: true,
      encoding: .utf8)
    let result = try await test.invoke(["path": "file.txt"])
    try #require(result.isError)
    try #require(result.content.contains("Not a directory"))
  }

  private func invoke(_ args: [String: Any]) async throws -> AgentToolInvocationResult {
    let data = try JSONSerialization.data(withJSONObject: args)
    return try await tool.invoke(
      arguments: data,
      context: AgentToolContext(workingDirectory: temporaryDirectory)
    )
  }
}
