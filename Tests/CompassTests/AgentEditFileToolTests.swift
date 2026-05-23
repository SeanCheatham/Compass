import Foundation
import XCTest

@testable import Compass

final class AgentEditFileToolTests: XCTestCase {
  private var temporaryDirectory: URL!
  private let tool = AgentEditFileTool()

  override func setUpWithError() throws {
    temporaryDirectory = try makeTempDir()
  }

  override func tearDownWithError() throws {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    temporaryDirectory = nil
  }

  func testReplacesUniqueOccurrence() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
    try "alpha\nbeta\ngamma".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "notes.txt",
        "edits": [["oldString": "beta", "newString": "BETA"]],
      ])

    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("applied 1 edit to notes.txt"))
    XCTAssertTrue(result.content.contains("replaced 1 occurrence"))
    XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "alpha\nBETA\ngamma")
  }

  func testAppliesMultipleEditsInOrder() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
    try "alpha\nbeta\ngamma".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "notes.txt",
        "edits": [
          ["oldString": "alpha", "newString": "ALPHA"],
          ["oldString": "gamma", "newString": "GAMMA"],
        ],
      ])

    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("applied 2 edits to notes.txt"))
    XCTAssertTrue(result.content.contains("replaced 2 occurrences"))
    XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "ALPHA\nbeta\nGAMMA")
  }

  func testLaterEditSeesEarlierEditsResult() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("chain.txt")
    try "one".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "chain.txt",
        "edits": [
          ["oldString": "one", "newString": "two"],
          ["oldString": "two", "newString": "three"],
        ],
      ])

    XCTAssertFalse(result.isError)
    XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "three")
  }

  func testFailingEditLeavesFileUnchanged() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("atomic.txt")
    try "alpha\nbeta".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "atomic.txt",
        "edits": [
          ["oldString": "alpha", "newString": "ALPHA"],
          ["oldString": "missing", "newString": "found"],
        ],
      ])

    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("edits[1]"))
    XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "alpha\nbeta")
  }

  func testFailsWhenOldStringIsAmbiguous() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("dup.txt")
    try "foo\nfoo\nfoo".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "dup.txt",
        "edits": [["oldString": "foo", "newString": "bar"]],
      ])

    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("matches 3 places"))
    XCTAssertTrue(result.content.contains("replaceAll"))
    XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "foo\nfoo\nfoo")
  }

  func testReplaceAllReplacesEveryOccurrence() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("dup.txt")
    try "foo\nfoo\nfoo".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "dup.txt",
        "edits": [["oldString": "foo", "newString": "bar", "replaceAll": true]],
      ])

    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("replaced 3 occurrences"))
    XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "bar\nbar\nbar")
  }

  func testFailsWhenOldStringMissing() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
    try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "notes.txt",
        "edits": [["oldString": "missing", "newString": "found"]],
      ])

    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("not found"))
  }

  func testIncludesNearMissHintsWhenOldStringMissing() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("near.txt")
    try "func helloWorld() { return 1 }\nfunc helloWorld() { return 2 }\nfunc bye() { return 3 }"
      .write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "near.txt",
        "edits": [
          [
            "oldString": "func helloWorld() { return 0 }",
            "newString": "func helloWorld() { return 999 }",
          ]
        ],
      ])

    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("not found"))
    XCTAssertTrue(
      result.content.contains("Lines that look similar"),
      "expected near-miss hints, got: \(result.content)")
    XCTAssertTrue(result.content.contains("line 1"))
    XCTAssertTrue(result.content.contains("line 2"))
  }

  func testFailsWhenStringsAreEqual() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
    try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "notes.txt",
        "edits": [["oldString": "alpha", "newString": "alpha"]],
      ])

    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("identical"))
  }

  func testFailsWhenOldStringIsEmpty() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
    try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "notes.txt",
        "edits": [["oldString": "", "newString": "anything"]],
      ])

    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("write_file"))
  }

  func testFailsWhenEditsArrayIsEmpty() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
    try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "notes.txt",
        "edits": [],
      ])

    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("edits is empty"))
  }

  func testRejectsPathThatEscapesWorkingDirectory() async throws {
    let result = try await invoke(
      [
        "path": "../escape.txt",
        "edits": [["oldString": "a", "newString": "b"]],
      ], context: AgentToolContext(workingDirectory: temporaryDirectory))
    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("escapes"))
  }

  func testFailsWithoutPriorRead() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("unread.txt")
    try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invoke(
      [
        "path": "unread.txt",
        "edits": [["oldString": "alpha", "newString": "ALPHA"]],
      ], context: AgentToolContext(workingDirectory: temporaryDirectory))
    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("requires a prior read_file"))
    XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "alpha")
  }

  func testRejectsMissingFile() async throws {
    let context = AgentToolContext(workingDirectory: temporaryDirectory)
    let ghost = temporaryDirectory.appendingPathComponent("ghost.txt")
    await context.readTracker.markRead(ghost)
    let result = try await invoke(
      [
        "path": "ghost.txt",
        "edits": [["oldString": "a", "newString": "b"]],
      ], context: context)
    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("not found"))
  }

  func testRejectsBinaryFile() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("binary.bin")
    try Data([0x01, 0x00, 0x02, 0x03]).write(to: fileURL)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "binary.bin",
        "edits": [["oldString": "a", "newString": "b"]],
      ])
    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("binary"))
  }

  private func invoke(_ args: [String: Any], context: AgentToolContext) async throws
    -> AgentToolInvocationResult
  {
    let data = try JSONSerialization.data(withJSONObject: args)
    return try await tool.invoke(arguments: data, context: context)
  }

  private func invokeMarkingRead(_ url: URL, args: [String: Any]) async throws
    -> AgentToolInvocationResult
  {
    let context = AgentToolContext(workingDirectory: temporaryDirectory)
    await context.readTracker.markRead(url)
    return try await invoke(args, context: context)
  }
}
