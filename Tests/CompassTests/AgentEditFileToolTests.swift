import Foundation
import Testing

@testable import Compass

final class AgentEditFileToolTests {
  private var temporaryDirectory: URL!
  private let tool = AgentEditFileTool()

  init() {
    temporaryDirectory = try! makeTempDir()
  }

  deinit {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
  }

  @Test func testReplacesUniqueOccurrence() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
    try "alpha\nbeta\ngamma".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "notes.txt",
        "edits": [["oldString": "beta", "newString": "BETA"]],
      ])

    try #require(!result.isError)
    try #require(result.content.contains("applied 1 edit to notes.txt"))
    try #require(result.content.contains("replaced 1 occurrence"))
    try #require(try String(contentsOf: fileURL, encoding: .utf8) == "alpha\nBETA\ngamma")
  }

  @Test func testAppliesMultipleEditsInOrder() async throws {
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

    try #require(!result.isError)
    try #require(result.content.contains("applied 2 edits to notes.txt"))
    try #require(result.content.contains("replaced 2 occurrences"))
    try #require(try String(contentsOf: fileURL, encoding: .utf8) == "ALPHA\nbeta\nGAMMA")
  }

  @Test func testLaterEditSeesEarlierEditsResult() async throws {
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

    try #require(!result.isError)
    try #require(try String(contentsOf: fileURL, encoding: .utf8) == "three")
  }

  @Test func testFailingEditLeavesFileUnchanged() async throws {
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

    try #require(result.isError)
    try #require(result.content.contains("edits[1]"))
    try #require(try String(contentsOf: fileURL, encoding: .utf8) == "alpha\nbeta")
  }

  @Test func testFailsWhenOldStringIsAmbiguous() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("dup.txt")
    try "foo\nfoo\nfoo".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "dup.txt",
        "edits": [["oldString": "foo", "newString": "bar"]],
      ])

    try #require(result.isError)
    try #require(result.content.contains("matches 3 places"))
    try #require(result.content.contains("replaceAll"))
    try #require(try String(contentsOf: fileURL, encoding: .utf8) == "foo\nfoo\nfoo")
  }

  @Test func testReplaceAllReplacesEveryOccurrence() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("dup.txt")
    try "foo\nfoo\nfoo".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "dup.txt",
        "edits": [["oldString": "foo", "newString": "bar", "replaceAll": true]],
      ])

    try #require(!result.isError)
    try #require(result.content.contains("replaced 3 occurrences"))
    try #require(try String(contentsOf: fileURL, encoding: .utf8) == "bar\nbar\nbar")
  }

  @Test func testFailsWhenOldStringMissing() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
    try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "notes.txt",
        "edits": [["oldString": "missing", "newString": "found"]],
      ])

    try #require(result.isError)
    try #require(result.content.contains("not found"))
  }

  @Test func testIncludesNearMissHintsWhenOldStringMissing() async throws {
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

    try #require(result.isError)
    try #require(result.content.contains("not found"))
    try #require(
      result.content.contains("Lines that look similar"),
      "expected near-miss hints, got: \(result.content)")
    try #require(result.content.contains("line 1"))
    try #require(result.content.contains("line 2"))
  }

  @Test func testFailsWhenStringsAreEqual() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
    try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "notes.txt",
        "edits": [["oldString": "alpha", "newString": "alpha"]],
      ])

    try #require(result.isError)
    try #require(result.content.contains("identical"))
  }

  @Test func testFailsWhenOldStringIsEmpty() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
    try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "notes.txt",
        "edits": [["oldString": "", "newString": "anything"]],
      ])

    try #require(result.isError)
    try #require(result.content.contains("write_file"))
  }

  @Test func testFailsWhenEditsArrayIsEmpty() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
    try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "notes.txt",
        "edits": [],
      ])

    try #require(result.isError)
    try #require(result.content.contains("edits is empty"))
  }

  @Test func testRejectsPathThatEscapesWorkingDirectory() async throws {
    let result = try await invoke(
      [
        "path": "../escape.txt",
        "edits": [["oldString": "a", "newString": "b"]],
      ], context: AgentToolContext(workingDirectory: temporaryDirectory))
    try #require(result.isError)
    try #require(result.content.contains("escapes"))
  }

  @Test func testFailsWithoutPriorRead() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("unread.txt")
    try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invoke(
      [
        "path": "unread.txt",
        "edits": [["oldString": "alpha", "newString": "ALPHA"]],
      ], context: AgentToolContext(workingDirectory: temporaryDirectory))
    try #require(result.isError)
    try #require(result.content.contains("requires a prior read_file"))
    try #require(try String(contentsOf: fileURL, encoding: .utf8) == "alpha")
  }

  @Test func testRejectsMissingFile() async throws {
    let context = AgentToolContext(workingDirectory: temporaryDirectory)
    let ghost = temporaryDirectory.appendingPathComponent("ghost.txt")
    await context.readTracker.markRead(ghost)
    let result = try await invoke(
      [
        "path": "ghost.txt",
        "edits": [["oldString": "a", "newString": "b"]],
      ], context: context)
    try #require(result.isError)
    try #require(result.content.contains("not found"))
  }

  @Test func testRejectsBinaryFile() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("binary.bin")
    try Data([0x01, 0x00, 0x02, 0x03]).write(to: fileURL)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "binary.bin",
        "edits": [["oldString": "a", "newString": "b"]],
      ])
    try #require(result.isError)
    try #require(result.content.contains("binary"))
  }

  fileprivate func invoke(_ args: [String: Any], context: AgentToolContext) async throws
    -> AgentToolInvocationResult
  {
    let data = try JSONSerialization.data(withJSONObject: args)
    return try await tool.invoke(arguments: data, context: context)
  }

  fileprivate func invokeMarkingRead(_ url: URL, args: [String: Any]) async throws
    -> AgentToolInvocationResult
  {
    let context = AgentToolContext(workingDirectory: temporaryDirectory)
    await context.readTracker.markRead(url)
    return try await invoke(args, context: context)
  }
}
