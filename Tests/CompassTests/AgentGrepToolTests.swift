import Foundation
import XCTest

@testable import Compass

final class AgentGrepToolTests: XCTestCase {
  private var temporaryDirectory: URL!
  private let tool = AgentGrepTool()
  // Force BSD grep so tests don't depend on the developer having ripgrep
  // installed. Both backends are exercised in the locator unit tests.
  private let filesystem = AgentHostFilesystem(grepExecutable: .grep("/usr/bin/grep"))

  override func setUpWithError() throws {
    temporaryDirectory = try makeTempDir()
  }

  override func tearDownWithError() throws {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    temporaryDirectory = nil
  }

  func testFindsMatchesAcrossFiles() async throws {
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

    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("a.txt:1:needle here"))
    XCTAssertTrue(result.content.contains("b.txt:2:needle in haystack"))
  }

  func testReportsNoMatchesWhenPatternMissing() async throws {
    try "alpha".write(
      to: temporaryDirectory.appendingPathComponent("only.txt"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await invoke(["pattern": "zeta"])
    XCTAssertFalse(result.isError)
    XCTAssertEqual(result.content, "(no matches)")
  }

  func testCaseInsensitiveSearchIsRespected() async throws {
    try "FOO\nfoo\nbar".write(
      to: temporaryDirectory.appendingPathComponent("mix.txt"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await invoke([
      "pattern": "foo",
      "caseInsensitive": true,
    ])

    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("FOO"))
    XCTAssertTrue(result.content.contains("foo"))
  }

  func testGlobRestrictsFiles() async throws {
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

    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("kept.swift"))
    XCTAssertFalse(result.content.contains("ignored.txt"))
  }

  func testEmptyPatternFails() async throws {
    let result = try await invoke(["pattern": "   "])
    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("pattern is empty"))
  }

  func testRejectsPathThatEscapesWorkingDirectory() async throws {
    let result = try await invoke([
      "pattern": "x",
      "path": "../escape",
    ])
    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("escapes"))
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
