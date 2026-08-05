import Foundation
import Testing

@testable import CompassCore

@Suite("AgentGrepTool")
struct AgentGrepToolTests {
  @Test
  func findsMatchesAndStripsWorkingDirectoryPrefix() async throws {
    let tempURL = try makeGrepTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    try FileManager.default.createDirectory(
      at: tempURL.appending(path: "src"),
      withIntermediateDirectories: true
    )
    try """
    fn main() {
        println!("Compass grep fixture");
    }
    """.write(
      to: tempURL.appending(path: "src/main.rs"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await AgentGrepTool().invoke(
      arguments: Data(#"{"pattern":"Compass grep fixture","path":"src"}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(!result.isError)
    #expect(result.content.contains("src/main.rs:"))
    #expect(result.content.contains("Compass grep fixture"))
    #expect(!result.content.contains(tempURL.path))
  }

  @Test
  func caseInsensitiveAliasAndNoMatches() async throws {
    let tempURL = try makeGrepTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try "Hello World".write(
      to: tempURL.appending(path: "note.txt"),
      atomically: true,
      encoding: .utf8
    )

    let matched = try await AgentGrepTool().invoke(
      arguments: Data(#"{"query":"hello world","ignore_case":true}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )
    #expect(!matched.isError)
    #expect(matched.content.contains("note.txt:"))

    let missed = try await AgentGrepTool().invoke(
      arguments: Data(#"{"pattern":"definitely-missing-token"}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )
    #expect(!missed.isError)
    #expect(missed.content == "(no matches)")
  }

  @Test
  func emptyPatternAndPathEscapeAreTypedFailures() async throws {
    let tempURL = try makeGrepTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let empty = try await AgentGrepTool().invoke(
      arguments: Data(#"{"pattern":"  "}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )
    #expect(empty.isError)
    #expect(empty.errorKind == .invalidArguments)

    let escaped = try await AgentGrepTool().invoke(
      arguments: Data(#"{"pattern":"foo","path":"/etc"}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )
    #expect(escaped.isError)
    #expect(escaped.errorKind == .pathEscape)
  }

  @Test
  func globRestrictsSearchedFiles() async throws {
    let tempURL = try makeGrepTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try "unique-token-here".write(
      to: tempURL.appending(path: "keep.swift"),
      atomically: true,
      encoding: .utf8
    )
    try "unique-token-here".write(
      to: tempURL.appending(path: "skip.txt"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await AgentGrepTool().invoke(
      arguments: Data(#"{"pattern":"unique-token-here","glob":"*.swift"}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(!result.isError)
    #expect(result.content.contains("keep.swift"))
    #expect(!result.content.contains("skip.txt"))
  }
}

@Suite("PlainTextListPrefix")
struct PlainTextListPrefixTests {
  @Test
  func stripsBulletsNumbersAndCheckboxes() {
    #expect(PlainTextListPrefix.strippedEntry(from: "- ship it") == "ship it")
    #expect(PlainTextListPrefix.strippedEntry(from: "* [x] done") == "done")
    #expect(
      PlainTextListPrefix.strippedEntry(from: "• keep unicode bullets") == "keep unicode bullets")
    #expect(PlainTextListPrefix.strippedEntry(from: "12. numbered") == "numbered")
    #expect(PlainTextListPrefix.strippedEntry(from: "3) also numbered") == "also numbered")
    #expect(PlainTextListPrefix.strippedEntry(from: "[ ] bare checkbox") == "bare checkbox")
    #expect(PlainTextListPrefix.strippedEntry(from: "plain prose") == nil)
  }

  @Test
  func cleanedLineFallsBackToTrimmedText() {
    #expect(PlainTextListPrefix.cleanedLine("  — em dash item  ") == "em dash item")
    #expect(PlainTextListPrefix.cleanedLine("  just text  ") == "just text")
  }
}

private func makeGrepTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "AgentGrepToolTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
