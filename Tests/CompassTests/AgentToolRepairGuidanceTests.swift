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
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("uses insert/insertion"))
    #expect(result.content.contains("use startLine=3, endLine=2"))
    #expect(result.content.contains("use replacementLines or content instead of insert"))
    #expect(result.content.contains("return `edit_file` with these arguments"))
    #expect(result.content.contains(#""path":"notes.txt""#))
    #expect(result.content.contains(#""startLine":3"#))
    #expect(result.content.contains(#""endLine":2"#))
    #expect(result.content.contains(#""insert":"three""#))
  }

  @Test
  func editFileStartLineZeroSuggestsFirstLineInsert() async throws {
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
      arguments: Data(#"{"path":"notes.txt","startLine":0,"endLine":0,"insert":"zero"}"#.utf8),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("never use startLine=0"))
    #expect(result.content.contains("To insert before the first line"))
    #expect(result.content.contains(#""path":"notes.txt""#))
    #expect(result.content.contains(#""startLine":1"#))
    #expect(result.content.contains(#""endLine":0"#))
    #expect(result.content.contains(#""insert":"zero""#))
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
  func editFileMissingPathWithContentShowsWriteFileArguments() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let srcURL = tempURL.appending(path: "packages/cli/src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: srcURL, withIntermediateDirectories: true)
    try "export const main = true;\n".write(
      to: srcURL.appending(path: "main.ts"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"packages/cli/src/summarize.ts","startLine":1,"endLine":1,"content":"export function summarizeCLI(): string {\n  return '1 open / 1 total';\n}\n"}"#
          .utf8
      ),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .readNotTracked)
    #expect(result.content.contains("file does not exist"))
    #expect(result.content.contains("return `write_file` with these arguments"))
    #expect(result.content.contains(#""path":"packages/cli/src/summarize.ts""#))
    #expect(result.content.contains(#""content":"export function summarizeCLI()"#))
  }

  @Test
  func editFileRejectsInsertAliasWithReplacementRange() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let srcURL = tempURL.appending(path: "packages/cli/src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: srcURL, withIntermediateDirectories: true)
    let mainURL = srcURL.appending(path: "main.ts")
    let original = """
    #!/usr/bin/env tsx
    import { summarizeQueue } from "@compass-test/core";

    export function main(): string {
      return summarizeQueue([]);
    }
    """
    try original.write(to: mainURL, atomically: true, encoding: .utf8)
    try "export function summarizeCLI() { return ''; }\n".write(
      to: srcURL.appending(path: "summarize.ts"),
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
        #"{"path":"packages/cli/src/main.ts","startLine":1,"endLine":1,"insert":"import { summarizeCLI } from './summarize';\n"}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("uses insert/insertion"))
    #expect(result.content.contains("use startLine=1, endLine=0"))
    #expect(result.content.contains("use replacementLines or content instead of insert"))
    let unchanged = try String(contentsOf: mainURL, encoding: .utf8)
    #expect(unchanged == original)
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
    #expect(result.content.contains("write_file only creates new files"))
  }

  @Test
  func writeFileRejectsExistingFileEvenAfterRead() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let cliSrc =
      tempURL
      .appending(path: "packages", directoryHint: .isDirectory)
      .appending(path: "cli", directoryHint: .isDirectory)
      .appending(path: "src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cliSrc, withIntermediateDirectories: true)
    let mainURL = cliSrc.appending(path: "main.ts")
    try "export function main() {}\nconsole.log(main());".write(
      to: mainURL,
      atomically: true,
      encoding: .utf8
    )
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"packages/cli/src/main.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentWriteFileTool().invoke(
      arguments: Data(#"{"path":"packages/cli/src/main.ts","content":"export {};"}"#.utf8),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("write_file refused to overwrite packages/cli/src/main.ts"))
    #expect(result.content.contains("Use edit_file for existing files"))
    #expect(result.content.contains("startLine=1, endLine=2"))
    #expect(result.content.contains("return `edit_file` with these arguments"))
    #expect(result.content.contains(#""path":"packages/cli/src/main.ts""#))
    #expect(result.content.contains(#""startLine":1"#))
    #expect(result.content.contains(#""endLine":2"#))
    #expect(result.content.contains(#""content":"export {};""#))
    let current = try String(contentsOf: mainURL, encoding: .utf8)
    #expect(current == "export function main() {}\nconsole.log(main());")
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
  func writeFileRejectsNewSelfRelativeModuleImport() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let srcURL = tempURL.appending(path: "packages/cli/src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: srcURL, withIntermediateDirectories: true)
    let fileURL = srcURL.appending(path: "summarize.ts")
    let result = try await AgentWriteFileTool().invoke(
      arguments: Data(
        #"{"path":"packages/cli/src/summarize.ts","content":"import { summarizeCLI } from './summarize';\n\nexport { summarizeCLI };\n"}"#
          .utf8
      ),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("write_file refused to create packages/cli/src/summarize.ts"))
    #expect(result.content.contains("self-referential relative module `./summarize`"))
    #expect(result.content.contains("define the symbol directly in packages/cli/src/summarize.ts"))
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
  }

  @Test
  func writeFileRejectsNewMissingRelativeModuleImport() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let srcURL = tempURL.appending(path: "packages/cli/src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: srcURL, withIntermediateDirectories: true)
    let fileURL = srcURL.appending(path: "summarize.ts")
    let result = try await AgentWriteFileTool().invoke(
      arguments: Data(
        #"{"path":"packages/cli/src/summarize.ts","content":"import { CLIEntry } from '../types';\n\nexport function summarizeCLI(entries: CLIEntry[]): string {\n  return String(entries.length);\n}\n"}"#
          .utf8
      ),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("unresolved relative module `../types`"))
    #expect(result.content.contains("packages/cli/types.ts"))
    #expect(result.content.contains("define the implementation directly"))
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
  }

  @Test
  func writeFileRejectsPlaceholderImplementation() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let srcURL = tempURL.appending(path: "packages/cli/src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: srcURL, withIntermediateDirectories: true)
    let fileURL = srcURL.appending(path: "summarize.ts")
    let result = try await AgentWriteFileTool().invoke(
      arguments: Data(
        #"{"path":"packages/cli/src/summarize.ts","content":"export function summarizeCLI(entries: any[]): string {\n  // TODO: Implement logic to summarize entries\n  return 'Summary: ' + entries.length + ' entries';\n}\n"}"#
          .utf8
      ),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("placeholder implementation code"))
    #expect(result.content.contains("TODO: Implement logic"))
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
  }

  @Test
  func writeFileRejectsImplementTheLogicPlaceholder() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let srcURL = tempURL.appending(path: "packages/cli/src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: srcURL, withIntermediateDirectories: true)
    let fileURL = srcURL.appending(path: "summarize.ts")
    let result = try await AgentWriteFileTool().invoke(
      arguments: Data(
        #"{"path":"packages/cli/src/summarize.ts","content":"export function summarizeCLI(entries: unknown[]): string {\n  // Implement the logic to summarize CLI entries here\n  return 'Summary of CLI entries';\n}\n"}"#
          .utf8
      ),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("placeholder implementation code"))
    #expect(result.content.contains("Implement the logic"))
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
  }

  @Test
  func writeFileRejectsPlaceholderImplementationComment() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let srcURL = tempURL.appending(path: "packages/cli/src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: srcURL, withIntermediateDirectories: true)
    let fileURL = srcURL.appending(path: "summarize.ts")
    let result = try await AgentWriteFileTool().invoke(
      arguments: Data(
        #"{"path":"packages/cli/src/summarize.ts","content":"export function summarizeCLI(entries: { id: string; title: string; done: boolean }[]): string {\n  // Placeholder implementation\n  return `Summary: ${entries.length} entries`;\n}\n"}"#
          .utf8
      ),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("placeholder implementation code"))
    #expect(result.content.contains("Placeholder implementation"))
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
  }

  @Test
  func writeFileRejectsCommentOnlySourceFile() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let srcURL = tempURL.appending(path: "packages/cli/src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: srcURL, withIntermediateDirectories: true)
    let fileURL = srcURL.appending(path: "summarize.ts")
    let result = try await AgentWriteFileTool().invoke(
      arguments: Data(
        #"{"path":"packages/cli/src/summarize.ts","content":"// This file holds the summarizeCLI function\n"}"#
          .utf8
      ),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("source files cannot be empty or comment-only"))
    #expect(result.content.contains("complete implementation"))
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
  }

  @Test
  func writeFileRejectsVitestJestPackageImport() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let srcURL = tempURL.appending(path: "packages/cli/src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: srcURL, withIntermediateDirectories: true)
    let fileURL = srcURL.appending(path: "summarize.test.ts")
    let result = try await AgentWriteFileTool().invoke(
      arguments: Data(
        #"{"path":"packages/cli/src/summarize.test.ts","content":"import { summarizeCLI } from './summarize';\nimport { describe, expect, test } from '@vitest/jest';\n\ndescribe('summarizeCLI', () => {\n  test('formats counts', () => {\n    expect(summarizeCLI([])).toBe('Done: 0, Pending: 0');\n  });\n});\n"}"#
          .utf8
      ),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("`@vitest/jest` is not a Vitest package import"))
    #expect(result.content.contains("from \"vitest\""))
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
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
    #expect(result.content.contains("Do not retry startLine=1, endLine=1"))
    #expect(result.content.contains("do not fix this by shifting to another single-line range"))
    #expect(result.content.contains("Your next edit_file call must use a different edit shape"))
    #expect(result.content.contains("Do not submit failed/blocked until you have tried"))
    #expect(result.content.contains("with only the new lines to insert, not the whole file"))
    #expect(result.content.contains("return `edit_file` with these arguments"))
    #expect(result.content.contains(#""path":"main.ts""#))
    #expect(result.content.contains(#""startLine":1"#))
    #expect(result.content.contains(#""endLine":6"#))
    #expect(result.content.contains("export function replacement"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(unchanged.contains("export function one()"))
  }

  @Test
  func editFileRejectsShortTopOfFilePartialRewrite() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let srcURL = tempURL.appending(path: "packages/cli/src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: srcURL, withIntermediateDirectories: true)
    let mainURL = srcURL.appending(path: "main.ts")
    let original = """
    #!/usr/bin/env tsx
    import { summarizeQueue } from "@compass-test/core";

    export function main(argv = process.argv.slice(2)): string {
      const title = argv.join(" ").trim() || "First Compass task";
      return summarizeQueue([{ id: "task-1", title, done: false }]);
    }

    if (import.meta.url === `file://${process.argv[1]}`) {
      console.log(main());
    }
    """
    try original.write(to: mainURL, atomically: true, encoding: .utf8)
    try "export function summarizeCLI() { return ''; }\n".write(
      to: srcURL.appending(path: "summarize.ts"),
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
        #"{"path":"packages/cli/src/main.ts","startLine":1,"endLine":1,"content":"import { summarizeCLI } from './summarize';\n\nexport function main(): void {\n  const entries = [];\n  console.log(summarizeCLI(entries));\n}\n"}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("partial whole-file rewrite"))
    #expect(result.content.contains("use startLine=1, endLine=11"))
    #expect(result.content.contains("with only the new lines to insert, not the whole file"))
    #expect(result.content.contains("return `edit_file` with these arguments"))
    #expect(result.content.contains(#""path":"packages/cli/src/main.ts""#))
    #expect(result.content.contains(#""startLine":1"#))
    #expect(result.content.contains(#""endLine":11"#))
    #expect(result.content.contains("summarizeCLI(entries)"))
    let unchanged = try String(contentsOf: mainURL, encoding: .utf8)
    #expect(unchanged == original)
  }

  @Test
  func editFileRejectsBodyOnlyReplacementOfFunctionDeclaration() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "main.ts")
    let original = """
    #!/usr/bin/env tsx
    import { summarizeQueue } from "@compass-test/core";

    export function main(argv = process.argv.slice(2)): string {
      const title = argv.join(" ").trim() || "First Compass task";
      return summarizeQueue([{ id: "task-1", title, done: false }]);
    }

    if (import.meta.url === `file://${process.argv[1]}`) {
      console.log(main());
    }
    """
    try original.write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"main.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"main.ts","startLine":4,"endLine":6,"content":"  const entries: { id: string; title: string; done: boolean }[] = [{ id: \"task-1\", title, done: false }];\n  return summarizeCLI(entries);\n"}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("would remove the function declaration `main`"))
    #expect(result.content.contains("Your next edit_file call must use a different edit shape"))
    #expect(result.content.contains("use startLine=4, endLine=7"))
    #expect(result.content.contains("include the complete `main` function declaration"))
    #expect(result.content.contains("edit only the function body with startLine=5, endLine=6"))
    #expect(result.content.contains("do not call read_file again for main.ts"))
    #expect(result.content.contains("Do not retry startLine=4, endLine=6"))
    #expect(result.content.contains("return `edit_file` with these arguments next"))
    #expect(result.content.contains(#""path":"main.ts""#))
    #expect(result.content.contains(#""startLine":4"#))
    #expect(result.content.contains(#""endLine":7"#))
    #expect(result.content.contains("export function main(argv = process.argv.slice(2)): string {"))
    #expect(result.content.contains("return summarizeCLI(entries);"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(unchanged == original)
  }

  @Test
  func editFileRejectsTestCodeInNonTestSourceFile() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "main.ts")
    let original = """
    #!/usr/bin/env tsx
    import { summarizeQueue } from "@compass-test/core";

    export function main(argv = process.argv.slice(2)): string {
      const title = argv.join(" ").trim() || "First Compass task";
      return summarizeQueue([{ id: "task-1", title, done: false }]);
    }
    """
    try original.write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"main.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"main.ts","startLine":5,"endLine":6,"content":"  it(\"handles the --limit argument\", () => {\n    expect(main([\"--limit\", \"4\", \"Ship\", \"it\"])).toBe(\"4 open / 4 total\");\n  });"}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("test code into non-test source file main.ts"))
    #expect(result.content.contains("Do not paste Vitest/Jest"))
    #expect(result.content.contains(".test.ts"))
    #expect(result.content.contains("implementation code only"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(unchanged == original)
  }

  @Test
  func editFileRejectsArgumentParsingImplementationInTestFile() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "main.test.ts")
    let original = """
    import { describe, expect, it } from "vitest";
    import { main } from "./main";

    describe("cli", () => {
      it("prints the queue summary", () => {
        expect(main(["Ship", "it"])).toBe("1 open / 1 total");
      });
    });
    """
    try original.write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"main.test.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"main.test.ts","startLine":6,"endLine":6,"content":"    const [action, countStr] = argv;\n    const count = parseInt(countStr, 10);\n    const title = argv.slice(2).join(\" \").trim() || \"First Compass task\";\n    return summarizeQueue([{ id: \"task-1\", title, done: action === \"--done\" && count === 1 }]);\n  });\n  it(\"handles --done with count\", () => {\n    expect(main([\"--done\", \"1\", \"Ship\", \"it\"])).toBe(\"0 open / 1 total\");\n  });"}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("argument-parsing implementation code into test file main.test.ts"))
    #expect(result.content.contains("Do not repair production behavior"))
    #expect(result.content.contains("Edit main.ts with the implementation"))
    #expect(result.content.contains("keep test edits focused"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(unchanged == original)
  }

  @Test
  func editFileAllowsAssertionsInTestFile() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "main.test.ts")
    let original = """
    import { describe, expect, it } from "vitest";
    import { main } from "./main";

    describe("cli", () => {
      it("prints the queue summary", () => {
        expect(main(["Ship", "it"])).toBe("1 open / 1 total");
      });
    });
    """
    try original.write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"main.test.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"main.test.ts","startLine":8,"endLine":7,"insert":"\n  it(\"handles --done with count\", () => {\n    expect(main([\"--done\", \"1\", \"Ship\", \"it\"])).toBe(\"0 open / 1 total\");\n  });"}"#
          .utf8
      ),
      context: context
    )

    #expect(!result.isError)
    let edited = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(edited.contains("handles --done with count"))
    #expect(edited.contains("expect(main([\"--done\", \"1\", \"Ship\", \"it\"])).toBe(\"0 open / 1 total\")"))
  }

  @Test
  func editFileTreatsIdenticalReplacementAsNoOp() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "summarize.ts")
    let original = """
    import { summarizeQueue } from "@compass-test/core";

    export function summarizeCLI(entries: { id: string; title: string; done: boolean }[]): string {
      return summarizeQueue(entries);
    }
    """
    try original.write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"summarize.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"summarize.ts","startLine":1,"endLine":5,"replacement":"import { summarizeQueue } from \"@compass-test/core\";\n\nexport function summarizeCLI(entries: { id: string; title: string; done: boolean }[]): string {\n  return summarizeQueue(entries);\n}"}"#
          .utf8
      ),
      context: context
    )

    #expect(!result.isError)
    #expect(result.content.contains("no changes needed for summarize.ts"))
    #expect(result.content.contains("Do not retry the identical edit"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(unchanged == original)
  }

  @Test
  func editFileRejectsDuplicateSourceInsertionBlock() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "main.ts")
    let original = """
    #!/usr/bin/env tsx
    import { summarizeQueue } from "@compass-test/core";

      const limit = parseInt(argv.shift(), 10);
      if (!isNaN(limit)) {
        argv.unshift(title);
        title = `Open ${limit} / ${limit} total`;
      }

    export function main(argv = process.argv.slice(2)): string {
      const title = argv.join(" ").trim() || "First Compass task";
      return summarizeQueue([{ id: "task-1", title, done: false }]);
    }
    """
    try original.write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"main.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"main.ts","startLine":4,"endLine":3,"insert":"\n  const limit = parseInt(argv.shift(), 10);\n  if (!isNaN(limit)) {\n    argv.unshift(title);\n    title = `Open ${limit} / ${limit} total`;\n  }\n"}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("same nonblank source block already exists"))
    #expect(result.content.contains("Do not insert this block again"))
    #expect(result.content.contains("replace or remove lines"))
    #expect(result.content.contains("rewrite the enclosing function or whole file"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(unchanged == original)
  }

  @Test
  func editFileRejectsDuplicateSourceReplacementBlock() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "main.test.ts")
    let original = """
      import { describe, expect, it } from "vitest";
      import { main } from "./main";

      describe("@split-argv-fixture/cli", () => {
        it("prints the queue summary", () => {
          it("prints the queue summary with limit", () => {
            expect(main(["--limit", "4", "Ship", "it"])).toBe("4 open / 4 total");
          });
        });
      });
      """
    try original.write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"main.test.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"main.test.ts","startLine":5,"endLine":5,"replacement":"    it(\"prints the queue summary with limit\", () => {\n      expect(main([\"--limit\", \"4\", \"Ship\", \"it\"])).toBe(\"4 open / 4 total\");\n    });"}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("same nonblank source block already exists"))
    #expect(result.content.contains("Do not duplicate this block by replacing another line/range"))
    #expect(result.content.contains("replace or remove lines"))
    #expect(result.content.contains("exact broken test structure"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(unchanged == original)
  }

  @Test
  func editFileRejectsNewPlaceholderImplementation() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "summarize.ts")
    let original = """
    export function summarizeCLI(entries: { id: string; title: string; done: boolean }[]): string {
      const doneCount = entries.filter(entry => entry.done).length;
      const totalCount = entries.length;
      return `${doneCount} of ${totalCount} tasks done.`;
    }
    """
    try original.write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"summarize.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"summarize.ts","startLine":1,"endLine":1,"replacement":"export function summarizeCLI(entries: any[]): string {\n  // TODO: Implement logic to summarize entries\n  return 'Summary: ' + entries.length + ' entries';\n}"}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("placeholder implementation code"))
    #expect(result.content.contains("Do not replace working source"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(unchanged == original)
  }

  @Test
  func editFileRejectsReplaceThisWithActualImplementationPlaceholder() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "summarize.ts")
    let original = """
    export function summarizeCLI(entries: { id: string; title: string; done: boolean }[]): string {
      const doneCount = entries.filter(entry => entry.done).length;
      const totalCount = entries.length;
      return `${doneCount} of ${totalCount} tasks done.`;
    }
    """
    try original.write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"summarize.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"summarize.ts","startLine":2,"endLine":3,"replacementLines":["  // Replace this with the actual implementation","  return `Summary: ${entries.length} entries`;"]}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("placeholder implementation code"))
    #expect(result.content.contains("Replace this with the actual implementation"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(unchanged == original)
  }

  @Test
  func editFileRejectsCommentOnlyReplacementOfWorkingSource() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "main.ts")
    let original = """
    #!/usr/bin/env tsx
    import { summarizeQueue } from "@compass-test/core";

    export function main(argv = process.argv.slice(2)): string {
      const title = argv.join(" ").trim() || "First Compass task";
      return summarizeQueue([{ id: "task-1", title, done: false }]);
    }

    if (import.meta.url === `file://${process.argv[1]}`) {
      console.log(main());
    }
    """
    try original.write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"main.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"main.ts","startLine":4,"endLine":8,"content":"// TODO: Move logic to summarize.ts\n// export function main(argv = process.argv.slice(2)): string {\n//   const title = argv.join(\" \").trim() || \"First Compass task\";\n//   return summarizeQueue([{ id: \"task-1\", title, done: false }]);\n// }\n"}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("comment-only content"))
    #expect(result.content.contains("Do not replace working source"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(unchanged == original)
  }

  @Test
  func editFileRejectsSuspiciousTopOfFileBulkInsertion() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "main.ts")
    let original = """
    #!/usr/bin/env tsx
    import { summarizeQueue } from "@compass-test/core";

    export function main(argv = process.argv.slice(2)): string {
      const title = argv.join(" ").trim() || "First Compass task";
      return summarizeQueue([{ id: "task-1", title, done: false }]);
    }
    """
    try original.write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"main.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"main.ts","startLine":1,"endLine":0,"content":"import { summarizeCLI } from \"./summarize\";\n\nexport function main(argv = process.argv.slice(2)): string {\n  const title = argv.join(\" \").trim() || \"First Compass task\";\n  return summarizeCLI([{ id: \"task-1\", title, done: false }]);\n}\n\nif (import.meta.url === `file://${process.argv[1]}`) {\n  console.log(main());\n}"}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("whole-file rewrite expressed as an insertion"))
    #expect(result.content.contains("Do not retry startLine=1, endLine=0"))
    #expect(result.content.contains("use startLine=1, endLine=7"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(unchanged == original)
  }

  @Test
  func editFileAllowsSmallTopOfFileInsertion() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "main.ts")
    try "export function main() { return true; }\n".write(
      to: fileURL,
      atomically: true,
      encoding: .utf8
    )
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"main.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"main.ts","startLine":1,"endLine":0,"content":"import { readFileSync } from \"node:fs\";"}"#
          .utf8
      ),
      context: context
    )

    #expect(!result.isError)
    let changed = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(changed.hasPrefix("import { readFileSync } from \"node:fs\";\n"))
  }

  @Test
  func editFileRejectsTopLevelImportInsideOpenFunction() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "main.ts")
    let original = """
    #!/usr/bin/env tsx
    import { summarizeQueue } from "@compass-test/core";

    export function main(argv = process.argv.slice(2)): string {
      const title = argv.join(" ").trim() || "First Compass task";
      return summarizeQueue([{ id: "task-1", title, done: false }]);
    }

    if (import.meta.url === `file://${process.argv[1]}`) {
      console.log(main());
    }
    """
    try original.write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"main.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(
        #"{"path":"main.ts","startLine":5,"endLine":11,"content":"import { summarizeCLI } from './summarize';\n\nexport function main(argv = process.argv.slice(2)): string {\n  const title = argv.join(' ').trim() || 'First Compass task';\n  return summarizeCLI([{ id: 'task-1', title, done: false }]);\n}\n\nif (import.meta.url === `file://${process.argv[1]}`) {\n  console.log(main());\n}"}"#
          .utf8
      ),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("starts inside an open block from line 4"))
    #expect(result.content.contains("top-level import"))
    #expect(result.content.contains("include line 4 in the edit range"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(unchanged == original)
  }

  @Test
  func editFileRejectsClearingNonEmptySourceFile() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let fileURL = tempURL.appending(path: "summarize.ts")
    let original = """
      export function summarizeCLI(entries: string[]): string {
        return `${entries.length} total`;
      }
      """
    try original.write(to: fileURL, atomically: true, encoding: .utf8)
    let context = AgentToolContext(workingDirectory: tempURL)
    _ = try await AgentReadFileTool().invoke(
      arguments: Data(#"{"path":"summarize.ts"}"#.utf8),
      context: context
    )

    let result = try await AgentEditFileTool().invoke(
      arguments: Data(#"{"path":"summarize.ts","startLine":1,"endLine":3,"replacement":""}"#.utf8),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("would leave summarize.ts empty"))
    #expect(result.content.contains("provide complete replacementLines"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(unchanged == original)
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
      arguments: Data(#"{"command":"pnpm verify"}"#.utf8),
      context: context
    )

    #expect(!result.isError)
    #expect(result.content.contains("[stdout]\nverify passed"))
    #expect(result.content.contains("[exit 0]"))
    #expect(result.content.contains("`pnpm verify` exited 0"))
    #expect(result.content.contains("do not keep editing"))
    #expect(result.content.contains("submit status=succeeded now"))
    #expect(result.content.contains("specific acceptance requirement is still missing"))
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
      arguments: Data(#"{"commands":["pnpm verify"]}"#.utf8),
      context: context
    )

    #expect(!result.isError)
    #expect(await bashRunner.commands == ["pnpm verify"])
    #expect(result.content.contains("`pnpm verify` exited 0"))
  }

  @Test
  func bashCommandsArrayRunsAsSingleShellScript() async throws {
    let tempURL = try makeToolGuidanceTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let bashRunner = RecordingBashRunner(
      result: ProcessResult(exitCode: 0, stdout: "ok\n", stderr: "")
    )
    let context = AgentToolContext(
      workingDirectory: tempURL,
      bashRunner: bashRunner,
      phase: .develop
    )

    let result = try await AgentBashTool().invoke(
      arguments: Data(#"{"commands":["pnpm install --frozen-lockfile","pnpm verify"]}"#.utf8),
      context: context
    )

    #expect(!result.isError)
    #expect(await bashRunner.commands == ["pnpm install --frozen-lockfile\npnpm verify"])
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
      arguments: Data(#"{"command":"pnpm verify"}"#.utf8),
      context: context
    )

    #expect(result.isError)
    #expect(result.errorKind == .bashFailure)
    #expect(result.content.contains("[stderr]\ntimed out"))
    #expect(result.content.contains("[exit 124]"))
    #expect(!result.content.contains("`pnpm verify` exited 0"))
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
  let url = FileManager.default.temporaryDirectory
    .appending(path: "AgentToolRepairGuidanceTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
