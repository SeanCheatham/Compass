import Foundation
import Testing

@testable import CompassCore

@Suite("Agent tool repair guidance")
struct AgentToolRepairGuidanceTests {
  @Test
  func readFileMissingPathListsNearbyEntries() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let src = tempURL.appending(path: "src", directoryHint: .isDirectory)
    let tests = tempURL.appending(path: "tests", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
    try "(def display ((name Text)) (concat name \"!\"))\n(display user.name)\n".write(
      to: src.appending(path: "display-name.tes"),
      atomically: true,
      encoding: .utf8
    )
    try #"{"name":"display-name","source":"display-name","context":"user","expect":"Ada!"}"#
      .write(
        to: tests.appending(path: "display-name.json"),
        atomically: true,
        encoding: .utf8
      )

    let sourceResult = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"src/missing.tes"}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(sourceResult.isError)
    #expect(sourceResult.errorKind == .fileNotFound)
    #expect(sourceResult.content.contains("Nearest existing directory: src"))
    #expect(sourceResult.content.contains("- display-name.tes"))
    #expect(sourceResult.content.contains("Use read_file with one of these paths"))

    let testResult = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"specs/display-name.json"}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )
    #expect(testResult.isError)
    #expect(testResult.content.contains("Same filename exists at:"))
    #expect(testResult.content.contains("- tests/display-name.json"))
  }

  @Test
  func grepAcceptsSingleFilePath() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let readmeURL = tempURL.appending(path: "README.md")
    try """
    # Fixture

    Compass local-model smoke note.
    """.write(to: readmeURL, atomically: true, encoding: .utf8)

    let result = try await AgentGrepTool().invoke(
      arguments: Data(
        #"{"pattern":"Compass local-model smoke note\\.","path":"README.md"}"#.utf8
      ),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(!result.isError)
    #expect(result.content.contains("README.md:3:Compass local-model smoke note."))
  }

  @Test
  func writeFileNewSiblingMentionsExistingFiles() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let src = tempURL.appending(path: "src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    try "(display user.name)\n".write(
      to: src.appending(path: "display-name.tes"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await AgentWriteFileTool().invoke(
      arguments: Data(
        #"{"path":"src/format-label.tes","content":"(def format ((name Text)) (concat \"Hello \" name))\n(format user.name)\n"}"#
          .utf8
      ),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(!result.isError)
    #expect(result.content.contains("Created a new file in existing directory src"))
    #expect(result.content.contains("- display-name.tes"))
  }

  @Test
  func tesseraResourceActionsGateAndEditProjectResources() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let src = tempURL.appending(path: "src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    let sourceURL = src.appending(path: "display-name.tes")
    try "(display user.name)\n".write(to: sourceURL, atomically: true, encoding: .utf8)
    try #"{"entrypoints":{}}"#.write(
      to: tempURL.appending(path: "tessera.json"),
      atomically: true,
      encoding: .utf8
    )

    let context = AgentToolContext(workingDirectory: tempURL)
    let tool = AgentTesseraTool(allowsMutation: true)
    let read = try await tool.invoke(
      arguments: Data(#"{"action":"read_resource","path":"src/display-name.tes"}"#.utf8),
      context: context
    )
    #expect(!read.isError)
    #expect(read.content.contains("(display user.name)"))

    let edit = try await tool.invoke(
      arguments: Data(
        #"{"action":"edit_resource","path":"src/display-name.tes","edits":[{"startLine":1,"endLine":1,"replacementLines":["(concat user.name \"!\")"]}]}"#
          .utf8
      ),
      context: context
    )
    #expect(!edit.isError)
    let updated = try String(contentsOf: sourceURL, encoding: .utf8)
    #expect(updated == "(concat user.name \"!\")\n")

    let overwrite = try await tool.invoke(
      arguments: Data(
        #"{"action":"write_resource","path":"src/display-name.tes","content":"(display user.name)\n"}"#
          .utf8
      ),
      context: context
    )
    #expect(overwrite.isError)
    #expect(overwrite.content.contains("tessera write_resource refused"))
    #expect(overwrite.content.contains("tessera edit_resource"))

    let forbiddenPath = try await tool.invoke(
      arguments: Data(#"{"action":"write_resource","path":"README.md","content":"Nope\n"}"#.utf8),
      context: context
    )
    #expect(forbiddenPath.isError)
    #expect(forbiddenPath.content.contains("Unsupported Tessera resource path"))

    let readOnlyTool = AgentTesseraTool(allowsMutation: false)
    let readOnlyMutation = try await readOnlyTool.invoke(
      arguments: Data(
        #"{"action":"write_resource","path":"src/other.tes","content":"(display user.name)\n"}"#.utf8
      ),
      context: context
    )
    #expect(readOnlyMutation.isError)
    #expect(readOnlyMutation.content.contains("not available in this phase"))
  }

  @Test
  func writeFileRejectsExistingFileEvenAfterRead() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let fileURL = tempURL.appending(path: "src/display-name.tes")
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try "(display user.name)\n".write(to: fileURL, atomically: true, encoding: .utf8)

    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"src/display-name.tes"}"#.utf8),
      context: context
    )
    let result = try await AgentWriteFileTool().invoke(
      arguments: Data(#"{"path":"src/display-name.tes","content":"(display user.name)\n"}"#.utf8),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("write_file refused to overwrite src/display-name.tes"))
    #expect(result.content.contains("Use edit_file"))
  }

  @Test
  func editFileOutOfRangeExplainsInsertAfterEnd() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let fileURL = tempURL.appending(path: "src/display-name.tes")
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try "(display user.name)\n".write(to: fileURL, atomically: true, encoding: .utf8)

    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"src/display-name.tes"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"src/display-name.tes","startLine":4,"endLine":4,"content":"(display user.name)\n"}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .editConflict)
    #expect(result.content.contains("file has 2 lines"))
    #expect(result.content.contains("To insert after the last line"))
    #expect(result.content.contains("If you intended to append the attempted replacement lines"))
    #expect(result.content.contains(#""startLine":3"#))
    #expect(result.content.contains(#""endLine":2"#))
    #expect(result.content.contains(#""insert":"(display user.name)\n""#))
  }

  @Test
  func editFileTreatsInsertAliasOnReplacementRangeAsReplacement() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let fileURL = tempURL.appending(path: "src/display-name.tes")
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try """
    (def display ((name Text)) (concat name "!"))
    (display user.name)
    """.write(to: fileURL, atomically: true, encoding: .utf8)

    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"src/display-name.tes"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"src/display-name.tes","startLine":1,"endLine":1,"insert":["(def display ((name Text)) (concat \"Hello, \" (concat name \"!\")))"]}"#
          .utf8
      ),
      context: context
    )

    #expect(!result.isError)
    #expect(result.content.contains("applied 1 edit"))
    let edited = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(
      edited
        == """
        (def display ((name Text)) (concat "Hello, " (concat name "!")))
        (display user.name)
        """
    )
  }

  @Test
  func editFileSplitsNewlinePackedReplacementArrayEntries() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let readmeURL = tempURL.appending(path: "README.md")
    try """
    # Fixture

    Existing body.
    """.write(to: readmeURL, atomically: true, encoding: .utf8)

    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"README.md"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        ##"{"path":"README.md","startLine":1,"endLine":1,"replacementLines":["# Fixture\n\nPacked replacement marker."]}"##
          .utf8
      ),
      context: context
    )

    #expect(!result.isError)
    #expect(result.content.contains("file now has 5 lines"))
    let edited = try String(contentsOf: readmeURL, encoding: .utf8)
    #expect(
      edited
        == """
        # Fixture

        Packed replacement marker.

        Existing body.
        """
    )
  }

  @Test
  func editFileStripsCopiedReadFileLinePrefixes() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let readmeURL = tempURL.appending(path: "README.md")
    try """
    # Fixture

    Existing body.
    """.write(to: readmeURL, atomically: true, encoding: .utf8)

    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"README.md"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        ##"{"path":"README.md","startLine":1,"endLine":3,"replacementLines":["     1\t# Fixture","     2\t","     3\tCopied prefix marker.","     4\tExisting body.","(total 4 lines)"]}"##
          .utf8
      ),
      context: context
    )

    #expect(!result.isError)
    #expect(result.content.contains("file now has 4 lines"))
    let edited = try String(contentsOf: readmeURL, encoding: .utf8)
    #expect(
      edited
        == """
        # Fixture

        Copied prefix marker.
        Existing body.
        """
    )
  }

  @Test
  func bashVerifySuccessTellsDevelopToSubmit() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let context = AgentToolContext(
      workingDirectory: tempURL,
      bashRunner: StaticBashRunner(
        result: ProcessResult(exitCode: 0, stdout: "verify passed\n", stderr: "")
      ),
      phase: .develop
    )

    let result = try await AgentBashTool().invoke(
      arguments: Data(#"{"command":"tessera verify . --json"}"#.utf8),
      context: context
    )

    #expect(!result.isError)
    #expect(result.content.contains("[stdout]\nverify passed"))
    #expect(result.content.contains("[exit 0]"))
    #expect(result.content.contains("`tessera verify . --json` exited 0"))
    #expect(result.content.contains("submit status=succeeded now"))
  }

  @Test
  func bashAcceptsCommandsArrayAlias() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let bashRunner = RecordingBashRunner(
      result: ProcessResult(exitCode: 0, stdout: "verify passed\n", stderr: "")
    )
    let context = AgentToolContext(
      workingDirectory: tempURL,
      bashRunner: bashRunner,
      phase: .develop
    )

    let result = try await AgentBashTool().invoke(
      arguments: Data(#"{"commands":["tessera verify . --json"]}"#.utf8),
      context: context
    )

    #expect(!result.isError)
    #expect(await bashRunner.commands == ["tessera verify . --json"])
    #expect(result.content.contains("`tessera verify . --json` exited 0"))
  }

  @Test
  func bashNonzeroExitIsToolFailure() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let context = AgentToolContext(
      workingDirectory: tempURL,
      bashRunner: StaticBashRunner(
        result: ProcessResult(exitCode: 124, stdout: "", stderr: "timed out\n")
      ),
      phase: .develop
    )

    let result = try await AgentBashTool().invoke(
      arguments: Data(#"{"command":"tessera verify . --json"}"#.utf8),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .bashFailure)
    #expect(result.content.contains("[stderr]\ntimed out"))
    #expect(result.content.contains("[exit 124]"))
    #expect(!result.content.contains("`tessera verify . --json` exited 0"))
  }
}

private struct StaticBashRunner: AgentBashRunner {
  let result: ProcessResult

  func run(
    command _: String,
    workingDirectory _: URL,
    timeout _: TimeInterval
  ) async throws -> ProcessResult {
    result
  }
}

private actor RecordingBashRunner: AgentBashRunner {
  private let result: ProcessResult
  private var recordedCommands: [String] = []

  init(result: ProcessResult) {
    self.result = result
  }

  var commands: [String] {
    recordedCommands
  }

  func run(
    command: String,
    workingDirectory _: URL,
    timeout _: TimeInterval
  ) async throws -> ProcessResult {
    recordedCommands.append(command)
    return result
  }
}

private func makeToolGuidanceTempDirectory() throws -> URL {
  try makeCompassTestDirectory(named: "AgentToolRepairGuidanceTests")
}
