import Foundation
import Testing

@testable import CompassCore

@Suite("AgentLsTool")
struct AgentLsToolTests {
  @Test
  func listsEntriesWithDirectorySlash() async throws {
    let tempURL = try makeLsGlobTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    try FileManager.default.createDirectory(
      at: tempURL.appending(path: "src"),
      withIntermediateDirectories: true
    )
    try "fn main() {}".write(
      to: tempURL.appending(path: "main.rs"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await AgentLsTool().invoke(
      arguments: Data(#"{}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(!result.isError)
    #expect(result.content.contains("main.rs"))
    #expect(result.content.contains("src/"))
  }

  @Test
  func emptyDirectoryReturnsHint() async throws {
    let tempURL = try makeLsGlobTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let result = try await AgentLsTool().invoke(
      arguments: Data(#"{}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(!result.isError)
    #expect(result.content == "(empty directory)")
  }

  @Test
  func pathEscapePreservesTypedKind() async throws {
    let tempURL = try makeLsGlobTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let result = try await AgentLsTool().invoke(
      arguments: Data(#"{"path":"/etc"}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .pathEscape)
    #expect(!result.content.hasPrefix("Invalid arguments: Path escapes"))
  }

  @Test
  func filePathReturnsNotDirectory() async throws {
    let tempURL = try makeLsGlobTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try "x".write(
      to: tempURL.appending(path: "file.txt"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await AgentLsTool().invoke(
      arguments: Data(#"{"directory":"file.txt"}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .notDirectory)
  }
}

@Suite("AgentGlobTool")
struct AgentGlobToolTests {
  @Test
  func findsFilesByPatternNewestFirst() async throws {
    let tempURL = try makeLsGlobTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let older = tempURL.appending(path: "old.swift")
    let newer = tempURL.appending(path: "new.swift")
    try "old".write(to: older, atomically: true, encoding: .utf8)
    try "new".write(to: newer, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1_000)],
      ofItemAtPath: older.path
    )
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 2_000)],
      ofItemAtPath: newer.path
    )
    try FileManager.default.createDirectory(
      at: tempURL.appending(path: "src"),
      withIntermediateDirectories: true
    )
    try "nested".write(
      to: tempURL.appending(path: "src/nested.swift"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await AgentGlobTool().invoke(
      arguments: Data(#"{"pattern":"**/*.swift"}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(!result.isError)
    #expect(result.content.contains("new.swift"))
    #expect(result.content.contains("old.swift"))
    #expect(result.content.contains("src/nested.swift"))
    let newIndex = try #require(result.content.range(of: "new.swift")?.lowerBound)
    let oldIndex = try #require(result.content.range(of: "old.swift")?.lowerBound)
    #expect(newIndex < oldIndex)
  }

  @Test
  func noMatchesReturnsHint() async throws {
    let tempURL = try makeLsGlobTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let result = try await AgentGlobTool().invoke(
      arguments: Data(#"{"glob":"*.missing"}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(!result.isError)
    #expect(result.content == "(no matches)")
  }

  @Test
  func pathEscapePreservesTypedKind() async throws {
    let tempURL = try makeLsGlobTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let result = try await AgentGlobTool().invoke(
      arguments: Data(#"{"pattern":"*.swift","path":"/tmp"}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .pathEscape)
  }

  @Test
  func fileRootReturnsTypedNotDirectory() async throws {
    let tempURL = try makeLsGlobTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try "x".write(
      to: tempURL.appending(path: "only.txt"),
      atomically: true,
      encoding: .utf8
    )

    let result = try await AgentGlobTool().invoke(
      arguments: Data(#"{"pattern":"*","path":"only.txt"}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .notDirectory)
  }

  @Test
  func emptyPatternIsInvalidArguments() async throws {
    let tempURL = try makeLsGlobTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let result = try await AgentGlobTool().invoke(
      arguments: Data(#"{"pattern":"   "}"#.utf8),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
  }
}

private func makeLsGlobTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "AgentLsGlobToolTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
