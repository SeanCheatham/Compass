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

  @Test func testReplacesLineContainingEmbeddedQuotes() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("rust-test.rs")
    try """
    #[test]
    fn test_shading_level_serialization() {
        let json = serde_json::to_string(&ShadingLevel::Partial).unwrap();
        assert_eq!(json, "old");
    }
    """
    .write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "rust-test.rs",
        "edits": [
          [
            "startLine": 4,
            "endLine": 4,
            "replacementLines": ["    assert_eq!(json, \"\\\"partial\\\");"],
          ]
        ],
      ])

    try #require(!result.isError)
    let updated = try String(contentsOf: fileURL, encoding: .utf8)
    try #require(updated.contains("partial"))
    try #require(!updated.contains("\"old\""))
  }

  @Test func testReplacesSingleLineRange() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
    try "alpha\nbeta\ngamma".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "notes.txt",
        "edits": [
          [
            "startLine": 2,
            "endLine": 2,
            "replacementLines": ["BETA"],
          ]
        ],
      ])

    try #require(!result.isError)
    try #require(result.content.contains("applied 1 edit to notes.txt"))
    try #require(result.content.contains("file now has 3 lines"))
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
          [
            "startLine": 1,
            "endLine": 1,
            "replacementLines": ["ALPHA"],
          ],
          [
            "startLine": 3,
            "endLine": 3,
            "replacementLines": ["GAMMA"],
          ],
        ],
      ])

    try #require(!result.isError)
    try #require(result.content.contains("applied 2 edits to notes.txt"))
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
          [
            "startLine": 1,
            "endLine": 1,
            "replacementLines": ["two"],
          ],
          [
            "startLine": 1,
            "endLine": 1,
            "replacementLines": ["three"],
          ],
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
          [
            "startLine": 1,
            "endLine": 1,
            "replacementLines": ["ALPHA"],
          ],
          [
            "startLine": 99,
            "endLine": 99,
            "replacementLines": ["found"],
          ],
        ],
      ])

    try #require(result.isError)
    try #require(result.content.contains("edits[1]"))
    try #require(try String(contentsOf: fileURL, encoding: .utf8) == "alpha\nbeta")
  }

  @Test func testInsertsBeforeLineWithoutDeleting() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("insert.txt")
    try "alpha\nbeta".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "insert.txt",
        "edits": [
          [
            "startLine": 2,
            "endLine": 1,
            "replacementLines": ["inserted"],
          ]
        ],
      ])

    try #require(!result.isError)
    try #require(try String(contentsOf: fileURL, encoding: .utf8) == "alpha\ninserted\nbeta")
  }

  @Test func testDeletesLineRangeWithEmptyReplacementLines() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("delete.txt")
    try "alpha\nbeta\ngamma".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "delete.txt",
        "edits": [
          [
            "startLine": 2,
            "endLine": 2,
            "replacementLines": [],
          ]
        ],
      ])

    try #require(!result.isError)
    try #require(try String(contentsOf: fileURL, encoding: .utf8) == "alpha\ngamma")
  }

  @Test func testAcceptsSnakeCaseEditArgumentsFromLessCapableModels() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("snake.txt")
    try "foo\nbar\nbaz".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "file_path": "snake.txt",
        "edits": [
          [
            "start_line": "2",
            "end_line": "3",
            "replacement_lines": ["BAR", "BAZ"],
          ]
        ],
      ])

    try #require(!result.isError)
    try #require(try String(contentsOf: fileURL, encoding: .utf8) == "foo\nBAR\nBAZ")
  }

  @Test func testAcceptsReplacementStringSplitIntoLines() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("multiline.txt")
    try "alpha\nbeta".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "multiline.txt",
        "edits": [
          [
            "startLine": 2,
            "endLine": 2,
            "newString": "line one\nline two",
          ]
        ],
      ])

    try #require(!result.isError)
    try #require(try String(contentsOf: fileURL, encoding: .utf8) == "alpha\nline one\nline two")
  }

  @Test func testAcceptsSingleEditObjectFromLessCapableModels() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("single-object.txt")
    try "alpha\nbeta".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "single-object.txt",
        "edits": [
          "startLine": 2,
          "endLine": 2,
          "replacementLines": ["BETA"],
        ],
      ])

    try #require(!result.isError)
    try #require(result.content.contains("applied 1 edit to single-object.txt"))
    try #require(try String(contentsOf: fileURL, encoding: .utf8) == "alpha\nBETA")
  }

  @Test func testAcceptsTopLevelEditOperationFromLessCapableModels() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("top-level.txt")
    try "foo\nbar".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "file": "top-level.txt",
        "start_line": 1,
        "end_line": 1,
        "replacement_lines": ["FOO"],
      ])

    try #require(!result.isError)
    try #require(try String(contentsOf: fileURL, encoding: .utf8) == "FOO\nbar")
  }

  @Test func testMissingEditsReportsRepairableFieldName() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("missing-edits.txt")
    try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: ["path": "missing-edits.txt"])

    try #require(result.isError)
    try #require(result.errorKind == .invalidArguments)
    try #require(result.content.contains("Missing required field `edits`"))
  }

  @Test func testIncludesNearbyLineHintsWhenRangeOutOfRange() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("near.txt")
    try "func helloWorld() { return 1 }\nfunc bye() { return 3 }"
      .write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "near.txt",
        "edits": [
          [
            "startLine": 9,
            "endLine": 9,
            "replacementLines": ["missing"],
          ]
        ],
      ])

    try #require(result.isError)
    try #require(result.content.contains("out of range"))
    try #require(result.content.contains("line 1:"))
    try #require(result.content.contains("helloWorld"))
  }

  @Test func testFailsWhenReplacementLinesAreIdentical() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("notes.txt")
    try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "notes.txt",
        "edits": [
          [
            "startLine": 1,
            "endLine": 1,
            "replacementLines": ["alpha"],
          ]
        ],
      ])

    try #require(result.isError)
    try #require(result.content.contains("identical"))
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
        "edits": [
          [
            "startLine": 1,
            "endLine": 1,
            "replacementLines": ["b"],
          ]
        ],
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
        "edits": [
          [
            "startLine": 1,
            "endLine": 1,
            "replacementLines": ["ALPHA"],
          ]
        ],
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
        "edits": [
          [
            "startLine": 1,
            "endLine": 1,
            "replacementLines": ["b"],
          ]
        ],
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
        "edits": [
          [
            "startLine": 1,
            "endLine": 1,
            "replacementLines": ["b"],
          ]
        ],
      ])
    try #require(result.isError)
    try #require(result.content.contains("binary"))
  }

  @Test func testRejectsInvalidUTF8WithoutRewritingFile() async throws {
    let fileURL = temporaryDirectory.appendingPathComponent("invalid.txt")
    let original = Data([0xC3, 0x28])
    try original.write(to: fileURL)

    let result = try await invokeMarkingRead(
      fileURL,
      args: [
        "path": "invalid.txt",
        "edits": [
          [
            "startLine": 1,
            "endLine": 1,
            "replacementLines": [")"],
          ]
        ],
      ])

    try #require(result.isError)
    try #require(result.errorKind == .binaryFile)
    try #require(result.content.contains("binary"))
    try #require(Data(contentsOf: fileURL) == original)
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
