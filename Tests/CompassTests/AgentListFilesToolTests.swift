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
