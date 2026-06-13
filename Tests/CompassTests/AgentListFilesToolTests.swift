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
    try store.saveEntry(entry("src/display-name.tes", language: .tessera))
    try store.saveEntry(entry("src/format-label.tes", language: .tessera))
    try store.saveEntry(entry("Sources/App/App.swift", language: .swift))
    try store.saveEntry(entry("Sources/Core/Core.swift", language: .swift))

    let tool = AgentListFilesTool()
    let context = AgentToolContext(
      workingDirectory: tempURL,
      codemapStoreDirectory: codemapURL
    )

    let parenthesized = try await tool.invoke(
      arguments: Data(#"{"pattern":"src/**/*.(tes|swift)"}"#.utf8),
      context: context
    )
    #expect(!parenthesized.isError)
    #expect(parenthesized.content.contains("matched normalized filters"))
    #expect(parenthesized.content.contains("src/display-name.tes"))
    #expect(parenthesized.content.contains("src/format-label.tes"))
    #expect(!parenthesized.content.contains("Sources/Core/Core.swift"))

    let braced = try await tool.invoke(
      arguments: Data(#"{"filter":"Sources/App/**/*.{swift,tes}"}"#.utf8),
      context: context
    )
    #expect(!braced.isError)
    #expect(braced.content.contains("Sources/App/App.swift"))
  }

  @Test
  func includesLiveSourceFilesMissingFromCodemap() async throws {
    let tempURL = try makeListFilesTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let src = tempURL.appending(path: "src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    try "(def display ((name Text)) (concat name \"!\"))\n(display user.name)\n".write(
      to: src.appending(path: "display-name.tes"),
      atomically: true,
      encoding: .utf8
    )
    try "(def format ((name Text)) (concat \"Hello \" name))\n(format user.name)\n".write(
      to: src.appending(path: "format-label.tes"),
      atomically: true,
      encoding: .utf8
    )
    try "compiled output".write(
      to: src.appending(path: "ignored.txt"),
      atomically: true,
      encoding: .utf8
    )

    let codemapURL = tempURL.appending(path: "codemap", directoryHint: .isDirectory)
    let store = CodemapStore(directory: codemapURL)
    try store.saveEntry(entry("src/display-name.tes", language: .tessera))

    let result = try await AgentListFilesTool().invoke(
      arguments: Data(#"{"path":"src"}"#.utf8),
      context: AgentToolContext(
        workingDirectory: tempURL,
        codemapStoreDirectory: codemapURL
      )
    )

    #expect(!result.isError)
    #expect(result.content.contains("files: 2"))
    #expect(result.content.contains("src/display-name.tes  [Tessera, 0 symbol(s)]"))
    #expect(result.content.contains("src/format-label.tes  [Tessera, unindexed]"))
    #expect(!result.content.contains("ignored.txt"))

    let globResult = try await AgentListFilesTool().invoke(
      arguments: Data(#"{"pattern":"src/*.tes"}"#.utf8),
      context: AgentToolContext(
        workingDirectory: tempURL,
        codemapStoreDirectory: codemapURL
      )
    )
    #expect(!globResult.isError)
    #expect(globResult.content.contains("src/format-label.tes"))

    let emptyDirectoryResult = try await AgentListFilesTool().invoke(
      arguments: Data(#"{"path":"test"}"#.utf8),
      context: AgentToolContext(
        workingDirectory: tempURL,
        codemapStoreDirectory: codemapURL
      )
    )
    #expect(!emptyDirectoryResult.isError)
    #expect(emptyDirectoryResult.content.contains("(no source files matching 'test')"))
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
  try makeCompassTestDirectory(named: "AgentListFilesToolTests")
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
