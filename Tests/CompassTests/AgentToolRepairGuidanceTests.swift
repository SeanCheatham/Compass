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
    #expect(result.content.contains("with only the new lines to insert, not the whole file"))
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
    #expect(result.content.contains("Keep line 4 in the replacement"))
    let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(unchanged == original)
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

private func makeToolGuidanceTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "AgentToolRepairGuidanceTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
