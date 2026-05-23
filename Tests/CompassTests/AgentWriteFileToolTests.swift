import Foundation
import XCTest

@testable import Compass

final class AgentWriteFileToolTests: XCTestCase {
  private var temporaryDirectory: URL!
  private let tool = AgentWriteFileTool()

  override func setUpWithError() throws {
    temporaryDirectory = try makeTempDir()
  }

  override func tearDownWithError() throws {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    temporaryDirectory = nil
  }

  func testCreatesNewFile() async throws {
    let result = try await invoke([
      "path": "fresh.txt",
      "content": "hello world",
    ])

    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("wrote 11 bytes to fresh.txt"))
    let written = try String(
      contentsOf: temporaryDirectory.appendingPathComponent("fresh.txt"), encoding: .utf8)
    XCTAssertEqual(written, "hello world")
  }

  func testOverwritesExistingFile() async throws {
    let url = temporaryDirectory.appendingPathComponent("existing.txt")
    try "old".write(to: url, atomically: true, encoding: .utf8)

    let result = try await invoke([
      "path": "existing.txt",
      "content": "new",
    ])

    XCTAssertFalse(result.isError)
    let written = try String(contentsOf: url, encoding: .utf8)
    XCTAssertEqual(written, "new")
  }

  func testCreatesIntermediateDirectories() async throws {
    let result = try await invoke([
      "path": "deep/nested/path/file.txt",
      "content": "hi",
    ])

    XCTAssertFalse(result.isError)
    let url = temporaryDirectory.appendingPathComponent("deep/nested/path/file.txt")
    XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "hi")
  }

  func testRejectsPathThatEscapesWorkingDirectory() async throws {
    let result = try await invoke([
      "path": "../escape.txt",
      "content": "x",
    ])
    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("escapes"))
  }

  func testRejectsExistingDirectory() async throws {
    let subdir = temporaryDirectory.appendingPathComponent("blocked")
    try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: false)

    let result = try await invoke([
      "path": "blocked",
      "content": "x",
    ])
    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("Not a regular file"))
  }

  private func invoke(_ args: [String: Any]) async throws -> AgentToolInvocationResult {
    let data = try JSONSerialization.data(withJSONObject: args)
    return try await tool.invoke(
      arguments: data,
      context: AgentToolContext(workingDirectory: temporaryDirectory)
    )
  }
}
