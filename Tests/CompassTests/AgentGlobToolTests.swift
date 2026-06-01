import Foundation
import Testing

@testable import Compass

final class AgentGlobToolTests {
  private var temporaryDirectory: URL!
  private let tool = AgentGlobTool()

  init() {
    temporaryDirectory = try! makeTempDir()
  }

  deinit {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
  }

  @Test func testRecursiveDoubleStarMatchesAllSwiftFiles() async throws {
    try makeTree([
      "a.swift": "x",
      "b.txt": "x",
      "sub/c.swift": "x",
      "sub/d.md": "x",
      "sub/deeper/e.swift": "x",
    ])

    let result = try await invoke(["pattern": "**/*.swift"])

    try #require(!result.isError)
    let lines = Set(result.content.split(separator: "\n").map(String.init))
    try #require(lines == ["a.swift", "sub/c.swift", "sub/deeper/e.swift"])
  }

  @Test func testSingleStarDoesNotCrossDirectoryBoundaries() async throws {
    try makeTree([
      "a.swift": "x",
      "sub/b.swift": "x",
    ])

    let result = try await invoke(["pattern": "*.swift"])

    try #require(!result.isError)
    let lines = Set(result.content.split(separator: "\n").map(String.init))
    try #require(lines == ["a.swift"])
  }

  @Test func testQuestionMarkMatchesSingleCharacter() async throws {
    try makeTree([
      "a.txt": "x",
      "ab.txt": "x",
      "b.txt": "x",
    ])

    let result = try await invoke(["pattern": "?.txt"])

    try #require(!result.isError)
    let lines = Set(result.content.split(separator: "\n").map(String.init))
    try #require(lines == ["a.txt", "b.txt"])
  }

  @Test func testAcceptsCommonPatternAndDirectoryAliasesFromLessCapableModels() async throws {
    try makeTree([
      "Sources/App.swift": "x",
      "Tests/AppTests.swift": "x",
    ])

    let result = try await invoke([
      "glob": "*.swift",
      "directory": "Sources",
    ])

    try #require(!result.isError)
    try #require(result.content == "Sources/App.swift")
  }

  @Test func testReportsNoMatchesWhenEmpty() async throws {
    try makeTree(["a.txt": "x"])
    let result = try await invoke(["pattern": "*.swift"])
    try #require(!result.isError)
    try #require(result.content == "(no matches)")
  }

  @Test func testEmptyPatternFails() async throws {
    let result = try await invoke(["pattern": "   "])
    try #require(result.isError)
    try #require(result.content.contains("pattern is empty"))
  }

  @Test func testMissingPatternReportsRepairableFieldName() async throws {
    let result = try await invoke([:])
    try #require(result.isError)
    try #require(result.errorKind == .invalidArguments)
    try #require(result.content.contains("Missing required field `pattern`"))
  }

  @Test func testRejectsPathThatEscapesWorkingDirectory() async throws {
    let result = try await invoke([
      "pattern": "*.swift",
      "path": "../escape",
    ])
    try #require(result.isError)
    try #require(result.content.contains("escapes"))
  }

  @Test func testResultsAreSortedNewestFirstByModificationTime() async throws {
    let older = temporaryDirectory.appendingPathComponent("old.swift")
    let newer = temporaryDirectory.appendingPathComponent("new.swift")
    try "x".write(to: older, atomically: true, encoding: .utf8)
    try "x".write(to: newer, atomically: true, encoding: .utf8)

    // Backdate the "older" file by a minute so the ordering is unambiguous.
    try FileManager.default.setAttributes(
      [.modificationDate: Date().addingTimeInterval(-60)],
      ofItemAtPath: older.path
    )

    let result = try await invoke(["pattern": "*.swift"])

    try #require(!result.isError)
    let lines = result.content.split(separator: "\n").map(String.init)
    try #require(lines == ["new.swift", "old.swift"])
  }

  private func makeTree(_ files: [String: String]) throws {
    for (relative, contents) in files {
      let fileURL = temporaryDirectory.appendingPathComponent(relative)
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }
  }

  private func invoke(_ args: [String: Any]) async throws -> AgentToolInvocationResult {
    let data = try JSONSerialization.data(withJSONObject: args)
    return try await tool.invoke(
      arguments: data,
      context: AgentToolContext(workingDirectory: temporaryDirectory)
    )
  }
}
