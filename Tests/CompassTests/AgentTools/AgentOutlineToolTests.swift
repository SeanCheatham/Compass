import Foundation
import Testing

@testable import CompassCore

@Suite("AgentOutlineTool")
struct AgentOutlineToolTests {
  @Test
  func missingCodemapEntryReturnsTypedFailure() async throws {
    let tempURL = try makeOutlineTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let codemapURL = tempURL.appending(path: "codemap", directoryHint: .isDirectory)

    let result = try await AgentOutlineTool().invoke(
      arguments: Data(#"{"path":"src/missing.rs"}"#.utf8),
      context: AgentToolContext(
        workingDirectory: tempURL,
        codemapStoreDirectory: codemapURL
      )
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("No codemap entry"))
  }

  @Test
  func outlinesIndexedFileWithImportsAndSymbols() async throws {
    let tempURL = try makeOutlineTempDirectory()
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
          CodemapSymbol(
            kind: .function,
            name: "main",
            line: 3,
            endLine: 5
          )
        ],
        imports: [
          CodemapImport(raw: "use compass_core::run;", line: 1)
        ],
        summary: nil,
        summaryModel: nil,
        summaryContentHash: nil,
        isGenerated: false
      )
    )

    let result = try await AgentOutlineTool().invoke(
      arguments: Data(#"{"file_path":"crates/cli/src/main.rs"}"#.utf8),
      context: AgentToolContext(
        workingDirectory: tempURL,
        codemapStoreDirectory: codemapURL
      )
    )

    #expect(!result.isError)
    #expect(result.content.contains("path: crates/cli/src/main.rs"))
    #expect(result.content.contains("imports:"))
    #expect(result.content.contains("use compass_core::run;"))
    #expect(result.content.contains("function  main"))
  }
}

private func makeOutlineTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "AgentOutlineToolTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
