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
    #expect(
      result.content.contains(
        "Use write_file for packages/core/src/utils/activity.ts only when the plan explicitly requires creating that exact new file"
      ))
  }

  @Test
  func editFileMissingPathListsNearbyExistingFiles() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let cliSrc =
      tempURL
      .appending(path: "packages", directoryHint: .isDirectory)
      .appending(path: "cli", directoryHint: .isDirectory)
      .appending(path: "src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cliSrc, withIntermediateDirectories: true)
    try "export function main() {}\n".write(
      to: cliSrc.appending(path: "main.ts"),
      atomically: true,
      encoding: .utf8
    )
    try "import { main } from './main';\n".write(
      to: cliSrc.appending(path: "main.test.ts"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"packages/cli/src/cli.ts","startLine":1,"endLine":1,"content":"export {};"}"#.utf8
      ),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .readNotTracked)
    #expect(result.content.contains("Nearest existing directory: packages/cli/src"))
    #expect(result.content.contains("- main.ts"))
    #expect(result.content.contains("- main.test.ts"))
    #expect(result.content.contains("read_file on one of these paths"))
    #expect(result.content.contains("only when the plan explicitly requires creating"))
  }

  @Test
  func writeFileNewSiblingMentionsExistingFiles() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let cliSrc =
      tempURL
      .appending(path: "packages", directoryHint: .isDirectory)
      .appending(path: "cli", directoryHint: .isDirectory)
      .appending(path: "src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cliSrc, withIntermediateDirectories: true)
    try "export function main() {}\n".write(
      to: cliSrc.appending(path: "main.ts"),
      atomically: true,
      encoding: .utf8
    )
    try "import { main } from './main';\n".write(
      to: cliSrc.appending(path: "main.test.ts"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await AgentWriteFileTool().invoke(
      arguments: Data(#"{"path":"packages/cli/src/cli.ts","content":"export {};"}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(!result.isError)
    #expect(result.content.contains("Created a new file in existing directory packages/cli/src"))
    #expect(result.content.contains("- main.ts"))
    #expect(result.content.contains("- main.test.ts"))
    #expect(result.content.contains("use read_file/edit_file on the existing path"))
  }

  @Test
  func writeFileRejectsDuplicatePackageEntrypoint() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let cliDirectory =
      tempURL
      .appending(path: "packages", directoryHint: .isDirectory)
      .appending(path: "cli", directoryHint: .isDirectory)
    let cliSrc = cliDirectory.appending(path: "src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cliSrc, withIntermediateDirectories: true)
    try "export function main() {}\n".write(
      to: cliSrc.appending(path: "main.ts"),
      atomically: true,
      encoding: .utf8
    )
    try """
    {
      "name": "@compass-test/cli",
      "type": "module",
      "bin": {
        "compass-test": "./src/main.ts"
      }
    }
    """.write(
      to: cliDirectory.appending(path: "package.json"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await AgentWriteFileTool().invoke(
      arguments: Data(#"{"path":"packages/cli/src/cli.ts","content":"export {};"}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("write_file refused to create packages/cli/src/cli.ts"))
    #expect(result.content.contains("packages/cli/package.json"))
    #expect(result.content.contains("bin.compass-test"))
    #expect(result.content.contains("packages/cli/src/main.ts"))
    #expect(result.content.contains("Edit packages/cli/src/main.ts instead"))
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

  @Test
  func editFileRejectsReadFileLineNumberPrefixesInReplacementContent() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "notes.txt")
    try "const ok = true;\n".write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"notes.txt"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"notes.txt","startLine":1,"endLine":1,"content":"    10\tconst bad = true;"}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("line-number prefixes"))
    #expect(result.content.contains("pass only source text"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(unchanged == "const ok = true;\n")
  }

  @Test
  func editFileRejectsReadFileFooterTextInReplacementContent() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "notes.txt")
    try "const ok = true;\n".write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"notes.txt"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"notes.txt","edits":[{"startLine":1,"endLine":1,"replacementLines":["const bad = true;","(total 12 lines)"]}]}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("read_file footer text"))
    #expect(result.content.contains("pass only source text"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(unchanged == "const ok = true;\n")
  }

  @Test
  func editFileRejectsEmbeddedNewlineInsideReplacementLineEntry() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "notes.txt")
    try "const ok = true;\n".write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"notes.txt"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"notes.txt","edits":[{"startLine":1,"endLine":1,"replacementLines":["const one = 1;\nconst two = 2;"]}]}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("contains embedded newline characters"))
    #expect(result.content.contains("one source line per string"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(unchanged == "const ok = true;\n")
  }

  @Test
  func editFileRejectsSuspiciousSingleLineBulkReplacement() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "main.ts")
    try """
    import { current } from "./current";
    export function one() { return 1; }
    export function two() { return 2; }
    export function three() { return 3; }
    export function four() { return 4; }
    export function five() { return 5; }
    """.write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"main.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"main.ts","startLine":1,"endLine":1,"content":"import { next } from './next';\n\nexport function replacement() {\n  return next();\n}\n\nexport function extra() {\n  return 42;\n}"}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("partial whole-file rewrite"))
    #expect(result.content.contains("use startLine=1, endLine=6"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(unchanged.contains("export function one()"))
  }

  @Test
  func editFileRejectsNewMissingRelativeModuleImport() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let srcURL = tempURL.appending(path: "packages/cli/src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: srcURL, withIntermediateDirectories: true)
    let fileURL = srcURL.appending(path: "main.ts")
    try """
    import { summarizeQueue } from "@compass-test/core";

    export function main(): string {
      return summarizeQueue([]);
    }
    """.write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"packages/cli/src/main.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"packages/cli/src/main.ts","startLine":1,"endLine":1,"content":"import { summarizeCLI } from './utils';\n\nimport { summarizeQueue } from \"@compass-test/core\";"}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("unresolved relative module `./utils`"))
    #expect(result.content.contains("packages/cli/src/utils.ts"))
    #expect(result.content.contains("keep the implementation inside packages/cli/src/main.ts"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(!unchanged.contains("./utils"))
  }

  @Test
  func editFileAllowsNewRelativeModuleImportWhenTargetExists() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let srcURL = tempURL.appending(path: "packages/cli/src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: srcURL, withIntermediateDirectories: true)
    let fileURL = srcURL.appending(path: "main.ts")
    try "export const main = true;\n".write(to: fileURL, atomically: true, encoding: .utf8)
    try "export const summarizeCLI = true;\n".write(
      to: srcURL.appending(path: "utils.ts"),
      atomically: true,
      encoding: .utf8
    )
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"packages/cli/src/main.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"packages/cli/src/main.ts","startLine":1,"endLine":1,"content":"import { summarizeCLI } from './utils';\nexport const main = summarizeCLI;"}"#
          .utf8
      ),
      context: context
    )

    #expect(!result.isError)
    let changed = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(changed.contains("./utils"))
  }

  @Test
  func editFileRejectsNewSelfRelativeModuleImport() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let srcURL = tempURL.appending(path: "packages/cli/src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: srcURL, withIntermediateDirectories: true)
    let fileURL = srcURL.appending(path: "main.ts")
    try """
    export function main(): string {
      return "ok";
    }
    """.write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"packages/cli/src/main.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"packages/cli/src/main.ts","startLine":1,"endLine":1,"content":"import { summarizeCLI } from './main';\nexport function main(): string {"}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("self-referential relative module `./main`"))
    #expect(result.content.contains("A file cannot import or export from itself"))
    #expect(result.content.contains("define the symbol directly in packages/cli/src/main.ts"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(!unchanged.contains("./main"))
  }
}

private func makeToolGuidanceTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "AgentToolRepairGuidanceTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
