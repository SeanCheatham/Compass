import Foundation
import XCTest

@testable import Compass

final class AgentLsToolTests: XCTestCase {
  private var temporaryDirectory: URL!
  private let tool = AgentLsTool()

  override func setUpWithError() throws {
    temporaryDirectory = try makeTempDir()
  }

  override func tearDownWithError() throws {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    temporaryDirectory = nil
  }

  func testListsFilesAndDirectoriesWithTrailingSlashOnDirs() async throws {
    try "a".write(
      to: temporaryDirectory.appendingPathComponent("alpha.txt"), atomically: true, encoding: .utf8)
    try "b".write(
      to: temporaryDirectory.appendingPathComponent("beta.txt"), atomically: true, encoding: .utf8)
    let subdir = temporaryDirectory.appendingPathComponent("gamma")
    try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: false)

    let result = try await invoke([:])

    XCTAssertFalse(result.isError)
    let lines = result.content.split(separator: "\n").map(String.init)
    XCTAssertEqual(lines, ["alpha.txt", "beta.txt", "gamma/"])
  }

  func testListsHiddenEntries() async throws {
    try "x".write(
      to: temporaryDirectory.appendingPathComponent(".compass"), atomically: true, encoding: .utf8)
    try "y".write(
      to: temporaryDirectory.appendingPathComponent("visible.txt"), atomically: true,
      encoding: .utf8)

    let result = try await invoke([:])

    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains(".compass"))
    XCTAssertTrue(result.content.contains("visible.txt"))
  }

  func testEmptyDirectoryReportsPlaceholder() async throws {
    let result = try await invoke([:])
    XCTAssertFalse(result.isError)
    XCTAssertEqual(result.content, "(empty directory)")
  }

  func testRejectsPathThatEscapesWorkingDirectory() async throws {
    let result = try await invoke(["path": "../escape"])
    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("escapes"))
  }

  func testRejectsRegularFile() async throws {
    try "x".write(
      to: temporaryDirectory.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
    let result = try await invoke(["path": "file.txt"])
    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("Not a directory"))
  }

  private func invoke(_ args: [String: Any]) async throws -> AgentToolInvocationResult {
    let data = try JSONSerialization.data(withJSONObject: args)
    return try await tool.invoke(
      arguments: data,
      context: AgentToolContext(workingDirectory: temporaryDirectory)
    )
  }
}
