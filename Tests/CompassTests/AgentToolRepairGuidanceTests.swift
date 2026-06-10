import Foundation
import Testing

@testable import CompassCore

@Suite("Agent tool repair guidance")
struct AgentToolRepairGuidanceTests {
  @Test
  func readFileMissingPathListsNearbyEntries() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let cliSrc =
      tempURL
      .appending(path: "packages", directoryHint: .isDirectory)
      .appending(path: "cli", directoryHint: .isDirectory)
      .appending(path: "src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cliSrc, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: cliSrc.appending(path: "empty", directoryHint: .isDirectory),
      withIntermediateDirectories: true
    )
    try "export const main = true;\n".write(
      to: cliSrc.appending(path: "main.ts"),
      atomically: true,
      encoding: .utf8
    )
    try "import './main';\n".write(
      to: cliSrc.appending(path: "main.test.ts"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"packages/cli/src/cli.ts"}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .fileNotFound)
    #expect(result.content.contains("Nearest existing directory: packages/cli/src"))
    #expect(result.content.contains("- main.ts"))
    #expect(result.content.contains("Use read_file with one of these paths"))

    let emptyDirectoryResult = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"packages/cli/src/empty/generated.ts"}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )
    #expect(emptyDirectoryResult.isError)
    #expect(emptyDirectoryResult.content.contains("Nearest existing directory: packages/cli/src"))
    #expect(emptyDirectoryResult.content.contains("- main.ts"))
  }

  @Test
  func editFileOutOfRangeExplainsInsertAfterEnd() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "notes.txt")
    try "one\ntwo".write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"notes.txt"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(#"{"path":"notes.txt","startLine":3,"endLine":3,"insert":"three"}"#.utf8),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .editConflict)
    #expect(result.content.contains("replace the last line with startLine=2, endLine=2"))
    #expect(result.content.contains("insert after the last line, use startLine=3, endLine=2"))
    #expect(result.content.contains("Do not retry the same out-of-range range"))
  }

  @Test
  func editFileMissingPathSuggestsWriteFile() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"packages/core/src/utils/activity.ts","startLine":1,"endLine":1,"content":"export {};"}"#
          .utf8
      ),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .readNotTracked)
    #expect(result.content.contains("file does not exist"))
    #expect(result.content.contains("Use write_file to create this new file"))
  }

  @Test
  func editFileMissingLineFieldsShowsRepairShape() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(#"{"path":"packages/core/src/index.ts","content":"new text"}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("edit_file requires path plus startLine, endLine"))
    #expect(result.content.contains("Example insert after line 6"))
    #expect(result.content.contains("Use write_file instead only when creating a new file"))
  }
}

private func makeToolGuidanceTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "AgentToolRepairGuidanceTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
