import Foundation
import Testing

@testable import CompassCore

@Suite("AgentFindSymbolTool")
struct AgentFindSymbolToolTests {
  @Test
  func unknownKindReturnsTypedInvalidArguments() async throws {
    let tempURL = try makeFindSymbolTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let result = try await AgentFindSymbolTool().invoke(
      arguments: Data(#"{"name":"main","kind":"not-a-kind"}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("Unknown kind"))
    #expect(result.content.contains("function"))
  }

  @Test
  func findsMatchingSymbolsAndFiltersByKind() async throws {
    let tempURL = try makeFindSymbolTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let codemapURL = tempURL.appending(path: "codemap", directoryHint: .isDirectory)
    let store = CodemapStore(directory: codemapURL)
    try store.saveEntry(
      CodemapEntry(
        relativePath: "crates/cli/src/main.rs",
        language: .rust,
        contentHash: CodemapHash.sha256Hex("crates/cli/src/main.rs"),
        sizeBytes: 64,
        symbols: [
          CodemapSymbol(kind: .function, name: "main", line: 3, endLine: 5),
          CodemapSymbol(kind: .struct, name: "Config", line: 10, endLine: 20),
        ],
        imports: [],
        summary: nil,
        summaryModel: nil,
        summaryContentHash: nil,
        isGenerated: false
      )
    )
    try store.saveEntry(
      CodemapEntry(
        relativePath: "crates/core/src/lib.rs",
        language: .rust,
        contentHash: CodemapHash.sha256Hex("crates/core/src/lib.rs"),
        sizeBytes: 32,
        symbols: [
          CodemapSymbol(kind: .function, name: "main", line: 1, endLine: 1)
        ],
        imports: [],
        summary: nil,
        summaryModel: nil,
        summaryContentHash: nil,
        isGenerated: false
      )
    )

    let unfiltered = try await AgentFindSymbolTool().invoke(
      arguments: Data(#"{"symbol":"main"}"#.utf8),
      context: AgentToolContext(
        workingDirectory: tempURL,
        codemapStoreDirectory: codemapURL
      )
    )
    #expect(!unfiltered.isError)
    #expect(unfiltered.content.contains("matches: 2"))
    #expect(unfiltered.content.contains("crates/cli/src/main.rs:3  function"))
    #expect(unfiltered.content.contains("crates/core/src/lib.rs:1  function"))

    let filtered = try await AgentFindSymbolTool().invoke(
      arguments: Data(#"{"name":"Config","kind":"struct"}"#.utf8),
      context: AgentToolContext(
        workingDirectory: tempURL,
        codemapStoreDirectory: codemapURL
      )
    )
    #expect(!filtered.isError)
    #expect(filtered.content.contains("matches: 1"))
    #expect(filtered.content.contains("crates/cli/src/main.rs:10  struct"))
  }

  @Test
  func missReturnsHintWithoutError() async throws {
    let tempURL = try makeFindSymbolTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let codemapURL = tempURL.appending(path: "codemap", directoryHint: .isDirectory)

    let result = try await AgentFindSymbolTool().invoke(
      arguments: Data(#"{"name":"AbsentSymbol"}"#.utf8),
      context: AgentToolContext(
        workingDirectory: tempURL,
        codemapStoreDirectory: codemapURL
      )
    )

    #expect(!result.isError)
    #expect(result.content.contains("No codemap symbol named 'AbsentSymbol'"))
    #expect(result.content.contains("try `grep`"))
  }

  @Test
  func allRawValuesTrackCaseIterable() {
    #expect(CodemapSymbolKind.allRawValues == CodemapSymbolKind.allCases.map(\.rawValue))
    #expect(CodemapSymbolKind.allRawValues.contains("function"))
    #expect(CodemapSymbolKind.allRawValues.contains("constant"))
  }
}

private func makeFindSymbolTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "AgentFindSymbolToolTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
