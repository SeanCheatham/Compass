import Foundation
import Testing

@testable import CompassCore

@Suite("AgentListFilesTool")
struct AgentListFilesToolTests {
  @Test
  func expandsCommonExtensionAlternationFilters() async throws {
    let tempURL = try makeListFilesTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let codemapURL = tempURL.appending(path: "codemap", directoryHint: .isDirectory)
    let store = CodemapStore(directory: codemapURL)
    try store.saveEntry(entry("packages/cli/src/main.ts", language: .typescript))
    try store.saveEntry(entry("packages/cli/src/main.test.ts", language: .typescript))
    try store.saveEntry(entry("packages/web/src/App.tsx", language: .tsx))
    try store.saveEntry(entry("packages/core/src/index.ts", language: .typescript))

    let tool = AgentListFilesTool()
    let context = AgentToolContext(
      workingDirectory: tempURL,
      codemapStoreDirectory: codemapURL
    )

    let parenthesized = try await tool.invoke(
      arguments: Data(#"{"pattern":"packages/cli/src/**/*.(ts|tsx)"}"#.utf8),
      context: context
    )
    #expect(!parenthesized.isError)
    #expect(parenthesized.content.contains("matched normalized filters"))
    #expect(parenthesized.content.contains("packages/cli/src/main.ts"))
    #expect(parenthesized.content.contains("packages/cli/src/main.test.ts"))
    #expect(!parenthesized.content.contains("packages/core/src/index.ts"))

    let braced = try await tool.invoke(
      arguments: Data(#"{"filter":"packages/web/src/**/*.{ts,tsx}"}"#.utf8),
      context: context
    )
    #expect(!braced.isError)
    #expect(braced.content.contains("packages/web/src/App.tsx"))
  }

  @Test
  func includesLiveSourceFilesMissingFromCodemap() async throws {
    let tempURL = try makeListFilesTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let cliSrc =
      tempURL
      .appending(path: "packages", directoryHint: .isDirectory)
      .appending(path: "cli", directoryHint: .isDirectory)
      .appending(path: "src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cliSrc, withIntermediateDirectories: true)
    try "export function main() { return true; }\n".write(
      to: cliSrc.appending(path: "main.ts"),
      atomically: true,
      encoding: .utf8
    )
    try "export function summarizeCLI() { return 'ok'; }\n".write(
      to: cliSrc.appending(path: "summarize.ts"),
      atomically: true,
      encoding: .utf8
    )
    try "compiled output".write(
      to: cliSrc.appending(path: "ignored.txt"),
      atomically: true,
      encoding: .utf8
    )

    let codemapURL = tempURL.appending(path: "codemap", directoryHint: .isDirectory)
    let store = CodemapStore(directory: codemapURL)
    try store.saveEntry(entry("packages/cli/src/main.ts", language: .typescript))

    let result = try await AgentListFilesTool().invoke(
      arguments: Data(#"{"path":"packages/cli/src"}"#.utf8),
      context: AgentToolContext(
        workingDirectory: tempURL,
        codemapStoreDirectory: codemapURL
      )
    )

    #expect(!result.isError)
    #expect(result.content.contains("files: 2"))
    #expect(result.content.contains("packages/cli/src/main.ts  [TypeScript, 0 symbol(s)]"))
    #expect(result.content.contains("packages/cli/src/summarize.ts  [TypeScript, unindexed]"))
    #expect(!result.content.contains("ignored.txt"))

    let globResult = try await AgentListFilesTool().invoke(
      arguments: Data(#"{"pattern":"packages/cli/src/*.ts"}"#.utf8),
      context: AgentToolContext(
        workingDirectory: tempURL,
        codemapStoreDirectory: codemapURL
      )
    )
    #expect(!globResult.isError)
    #expect(globResult.content.contains("packages/cli/src/summarize.ts"))

    let emptyDirectoryResult = try await AgentListFilesTool().invoke(
      arguments: Data(#"{"path":"packages/cli/test"}"#.utf8),
      context: AgentToolContext(
        workingDirectory: tempURL,
        codemapStoreDirectory: codemapURL
      )
    )
    #expect(!emptyDirectoryResult.isError)
    #expect(emptyDirectoryResult.content.contains("(no source files matching 'packages/cli/test')"))
    #expect(emptyDirectoryResult.content.contains("try a broader filter such as 'packages/cli'"))
  }

  @Test
  func includesLiveTesseraSourceFilesMissingFromCodemap() async throws {
    let tempURL = try makeListFilesTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let src = tempURL.appending(path: "src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    try "(def display ((name Text)) (concat name \"!\"))\n(display user.name)\n".write(
      to: src.appending(path: "display-name.tes"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await AgentListFilesTool().invoke(
      arguments: Data(#"{"path":"src"}"#.utf8),
      context: AgentToolContext(
        workingDirectory: tempURL,
        codemapStoreDirectory: tempURL.appending(path: "codemap", directoryHint: .isDirectory)
      )
    )

    #expect(!result.isError)
    #expect(result.content.contains("files: 1"))
    #expect(result.content.contains("src/display-name.tes  [Tessera, unindexed]"))
  }
}

private func makeListFilesTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "AgentListFilesToolTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func entry(_ relativePath: String, language: CodemapLanguage) -> CodemapEntry {
  CodemapEntry(
    relativePath: relativePath,
    language: language,
    contentHash: CodemapHash.sha256Hex(relativePath),
    sizeBytes: 120,
    symbols: [],
    imports: [],
    summary: nil,
    summaryModel: nil,
    summaryContentHash: nil,
    isGenerated: false
  )
}
