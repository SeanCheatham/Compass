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
    try store.saveEntry(entry("crates/cli/src/main.rs", language: .rust))
    try store.saveEntry(entry("crates/cli/tests/cli.rs", language: .rust))
    try store.saveEntry(entry("crates/core/src/lib.rs", language: .rust))

    let cliSrc = tempURL.appending(path: "crates/cli/src", directoryHint: .isDirectory)
    let cliTests = tempURL.appending(path: "crates/cli/tests", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cliSrc, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: cliTests, withIntermediateDirectories: true)
    try "fn main() {}\n".write(to: cliSrc.appending(path: "main.rs"), atomically: true, encoding: .utf8)
    try "#[test] fn smoke() {}\n".write(
      to: cliTests.appending(path: "cli.rs"), atomically: true, encoding: .utf8)

    let tool = AgentListFilesTool()
    let context = AgentToolContext(
      workingDirectory: tempURL,
      codemapStoreDirectory: codemapURL
    )

    let parenthesized = try await tool.invoke(
      arguments: Data(#"{"pattern":"crates/cli/src/**/*.rs"}"#.utf8),
      context: context
    )
    #expect(!parenthesized.isError)
    #expect(parenthesized.content.contains("crates/cli/src/main.rs"))
    #expect(!parenthesized.content.contains("crates/core/src/lib.rs"))

    let braced = try await tool.invoke(
      arguments: Data(#"{"filter":"crates/cli/tests/**/*.rs"}"#.utf8),
      context: context
    )
    #expect(!braced.isError)
    #expect(braced.content.contains("crates/cli/tests/cli.rs"))
  }

  @Test
  func includesLiveSourceFilesMissingFromCodemap() async throws {
    let tempURL = try makeListFilesTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let cliSrc =
      tempURL
      .appending(path: "crates", directoryHint: .isDirectory)
      .appending(path: "cli", directoryHint: .isDirectory)
      .appending(path: "src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cliSrc, withIntermediateDirectories: true)
    try "pub fn main() -> bool { true }\n".write(
      to: cliSrc.appending(path: "main.rs"),
      atomically: true,
      encoding: .utf8
    )
    try "pub fn summarize_cli() -> &'static str { \"ok\" }\n".write(
      to: cliSrc.appending(path: "summarize.rs"),
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
    try store.saveEntry(entry("crates/cli/src/main.rs", language: .rust))

    let result = try await AgentListFilesTool().invoke(
      arguments: Data(#"{"path":"crates/cli/src"}"#.utf8),
      context: AgentToolContext(
        workingDirectory: tempURL,
        codemapStoreDirectory: codemapURL
      )
    )

    #expect(!result.isError)
    #expect(result.content.contains("files: 2"))
    #expect(result.content.contains("crates/cli/src/main.rs  [Rust, 0 symbol(s)]"))
    #expect(result.content.contains("crates/cli/src/summarize.rs  [Rust, unindexed]"))
    #expect(!result.content.contains("ignored.txt"))

    let globResult = try await AgentListFilesTool().invoke(
      arguments: Data(#"{"pattern":"crates/cli/src/*.rs"}"#.utf8),
      context: AgentToolContext(
        workingDirectory: tempURL,
        codemapStoreDirectory: codemapURL
      )
    )
    #expect(!globResult.isError)
    #expect(globResult.content.contains("crates/cli/src/summarize.rs"))

    let emptyDirectoryResult = try await AgentListFilesTool().invoke(
      arguments: Data(#"{"path":"crates/cli/benches"}"#.utf8),
      context: AgentToolContext(
        workingDirectory: tempURL,
        codemapStoreDirectory: codemapURL
      )
    )
    #expect(!emptyDirectoryResult.isError)
    #expect(emptyDirectoryResult.content.contains("(no source files matching 'crates/cli/benches')"))
    #expect(emptyDirectoryResult.content.contains("try a broader filter such as 'crates/cli'"))
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
