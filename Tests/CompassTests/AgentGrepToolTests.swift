import Foundation
import Testing

@testable import Compass

final class AgentGrepToolTests {
  private var temporaryDirectory: URL!
  private let tool = AgentGrepTool()
  // Force BSD grep so tests don't depend on the developer having ripgrep
  // installed. Both backends are exercised in the locator unit tests.
  private let filesystem = AgentHostFilesystem(grepExecutable: .grep("/usr/bin/grep"))

  init() {
    temporaryDirectory = try! makeTempDir()
  }

  deinit {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
  }

  @Test func testFindsMatchesAcrossFiles() async throws {
    try "needle here\nother".write(
      to: temporaryDirectory.appendingPathComponent("a.txt"),
      atomically: true,
      encoding: .utf8
    )
    try "hay\nneedle in haystack".write(
      to: temporaryDirectory.appendingPathComponent("b.txt"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await invoke(["pattern": "needle"])

    #require(!result.isError)
    #require(result.content.contains("a.txt:1:needle here"))
    #require(result.content.contains("b.txt:2:needle in haystack"))
  }

  @Test func testReportsNoMatchesWhenPatternMissing() async throws {
    try "alpha".write(
      to: temporaryDirectory.appendingPathComponent("only.txt"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await invoke(["pattern": "zeta"])
    #require(!result.isError)
    #require(result.content == "(no matches)")
  }

  @Test func testCaseInsensitiveSearchIsRespected() async throws {
    try "FOO\nfoo\nbar".write(
      to: temporaryDirectory.appendingPathComponent("mix.txt"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await invoke([
      "pattern": "foo",
      "caseInsensitive": true,
    ])

    #require(!result.isError)
    #require(result.content.contains("FOO"))
    #require(result.content.contains("foo"))
  }

  @Test func testGlobRestrictsFiles() async throws {
    try "match".write(
      to: temporaryDirectory.appendingPathComponent("kept.swift"),
      atomically: true,
      encoding: .utf8
    )
    try "match".write(
      to: temporaryDirectory.appendingPathComponent("ignored.txt"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await invoke([
      "pattern": "match",
      "glob": "*.swift",
    ])

    #require(!result.isError)
    #require(result.content.contains("kept.swift"))
    #require(!result.content.contains("ignored.txt"))
  }

  @Test func testEmptyPatternFails() async throws {
    let result = try await invoke(["pattern": "   "])
    #require(result.isError)
    #require(result.content.contains("pattern is empty"))
  }

  @Test func testRejectsPathThatEscapesWorkingDirectory() async throws {
    let result = try await invoke([
      "pattern": "x",
      "path": "../escape",
    ])
    #require(result.isError)
    #require(result.content.contains("escapes"))
  }

  private func invoke(_ args: [String: Any]) async throws -> AgentToolInvocationResult {
    let data = try JSONSerialization.data(withJSONObject: args)
    return try await tool.invoke(
      arguments: data,
      context: AgentToolContext(
        workingDirectory: temporaryDirectory,
        filesystem: filesystem
      )
    )
  }
}
