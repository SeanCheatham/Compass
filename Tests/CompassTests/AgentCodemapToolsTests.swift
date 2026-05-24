import Foundation
import XCTest

@testable import Compass

final class AgentCodemapToolsTests: XCTestCase {
  private var workingDirectory: URL!
  private var cacheDirectory: URL!
  private var context: AgentToolContext!

  override func setUpWithError() throws {
    workingDirectory = try makeTempDir()
    cacheDirectory = workingDirectory.appendingPathComponent(".compass/codemap")
    context = AgentToolContext(workingDirectory: workingDirectory)
  }

  override func tearDownWithError() throws {
    if let workingDirectory {
      try? FileManager.default.removeItem(at: workingDirectory)
    }
    workingDirectory = nil
    cacheDirectory = nil
    context = nil
  }

  // MARK: - outline

  func testOutlineReturnsSymbolsAndImports() async throws {
    try seedEntry(
      path: "Sources/Foo.swift",
      symbols: [
        CodemapSymbol(kind: .class, name: "Foo", line: 4, endLine: 12),
        CodemapSymbol(kind: .function, name: "bar", line: 7, endLine: 9),
      ],
      imports: [CodemapImport(raw: "Foundation", line: 1)]
    )
    let result = try await AgentOutlineTool().invoke(
      arguments: try JSONEncoder().encode(["path": "Sources/Foo.swift"]),
      context: context
    )
    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("path: Sources/Foo.swift"))
    XCTAssertTrue(result.content.contains("imports:"))
    XCTAssertTrue(result.content.contains("Foundation"))
    XCTAssertTrue(result.content.contains("L4-12  class  Foo"))
    XCTAssertTrue(result.content.contains("L7-9  function  bar"))
  }

  func testOutlineSurfacesMissingEntryAsError() async throws {
    let result = try await AgentOutlineTool().invoke(
      arguments: try JSONEncoder().encode(["path": "missing.swift"]),
      context: context
    )
    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.content.contains("No codemap entry"))
  }

  // MARK: - find_symbol

  func testFindSymbolReturnsAllMatches() async throws {
    try seedEntry(
      path: "a.swift",
      symbols: [CodemapSymbol(kind: .class, name: "Service", line: 10, endLine: 30)]
    )
    try seedEntry(
      path: "b.swift",
      symbols: [
        CodemapSymbol(kind: .struct, name: "Service", line: 5, endLine: 7),
        CodemapSymbol(kind: .function, name: "configure", line: 9, endLine: 11),
      ]
    )

    let result = try await AgentFindSymbolTool().invoke(
      arguments: try JSONEncoder().encode(["name": "Service"]),
      context: context
    )
    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("matches: 2"))
    XCTAssertTrue(result.content.contains("a.swift:10  class"))
    XCTAssertTrue(result.content.contains("b.swift:5  struct"))
  }

  func testFindSymbolFiltersByKind() async throws {
    try seedEntry(
      path: "a.swift",
      symbols: [
        CodemapSymbol(kind: .class, name: "Service", line: 10, endLine: 30),
        CodemapSymbol(kind: .function, name: "Service", line: 50, endLine: 52),
      ]
    )
    let result = try await AgentFindSymbolTool().invoke(
      arguments: try JSONEncoder().encode(["name": "Service", "kind": "class"]),
      context: context
    )
    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("matches: 1"))
    XCTAssertTrue(result.content.contains("a.swift:10  class"))
    XCTAssertFalse(result.content.contains("a.swift:50"))
  }

  func testFindSymbolReportsMissAsOkay() async throws {
    let result = try await AgentFindSymbolTool().invoke(
      arguments: try JSONEncoder().encode(["name": "Nope"]),
      context: context
    )
    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("No codemap symbol named 'Nope'"))
  }

  // MARK: - summary

  func testSummaryReturnsCachedText() async throws {
    try seedEntry(
      path: "Sources/Foo.swift",
      symbols: [CodemapSymbol(kind: .class, name: "Foo", line: 1, endLine: 1)],
      summary: "Foo holds the running state.",
      summaryModel: "Haiku-tier"
    )
    let result = try await AgentSummaryTool().invoke(
      arguments: try JSONEncoder().encode(["path": "Sources/Foo.swift"]),
      context: context
    )
    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("summarized by Haiku-tier"))
    XCTAssertTrue(result.content.contains("Foo holds the running state."))
  }

  func testSummaryReportsMissingPassAsOkay() async throws {
    try seedEntry(
      path: "Sources/Foo.swift",
      symbols: [CodemapSymbol(kind: .class, name: "Foo", line: 1, endLine: 1)]
    )
    let result = try await AgentSummaryTool().invoke(
      arguments: try JSONEncoder().encode(["path": "Sources/Foo.swift"]),
      context: context
    )
    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("No summary yet"))
  }

  // MARK: - list_files

  func testListFilesReturnsEverythingWhenNoFilter() async throws {
    try seedEntry(path: "a.swift", symbols: [])
    try seedEntry(path: "lib/b.swift", symbols: [])
    let result = try await AgentListFilesTool().invoke(
      arguments: Data("{}".utf8),
      context: context
    )
    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("files: 2"))
    XCTAssertTrue(result.content.contains("a.swift"))
    XCTAssertTrue(result.content.contains("lib/b.swift"))
  }

  func testListFilesFiltersBySubstring() async throws {
    try seedEntry(path: "alpha.swift", symbols: [])
    try seedEntry(path: "lib/beta.swift", symbols: [])
    let result = try await AgentListFilesTool().invoke(
      arguments: try JSONEncoder().encode(["filter": "beta"]),
      context: context
    )
    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("files: 1"))
    XCTAssertTrue(result.content.contains("lib/beta.swift"))
    XCTAssertFalse(result.content.contains("alpha.swift"))
  }

  // MARK: - importers_of

  func testImportersOfMatchesRelativeImports() async throws {
    try seedEntry(
      path: "src/foo.ts",
      symbols: [CodemapSymbol(kind: .function, name: "foo", line: 1, endLine: 1)]
    )
    try seedEntry(
      path: "src/bar.ts",
      symbols: [CodemapSymbol(kind: .function, name: "bar", line: 1, endLine: 1)],
      imports: [CodemapImport(raw: "./foo", line: 1)]
    )
    let result = try await AgentImportersOfTool().invoke(
      arguments: try JSONEncoder().encode(["path": "src/foo.ts"]),
      context: context
    )
    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("importers: 1"))
    XCTAssertTrue(result.content.contains("src/bar.ts:1"))
  }

  func testImportersOfMatchesIndexBareImport() async throws {
    try seedEntry(
      path: "src/foo/index.ts",
      symbols: [CodemapSymbol(kind: .function, name: "f", line: 1, endLine: 1)]
    )
    try seedEntry(
      path: "src/main.ts",
      symbols: [CodemapSymbol(kind: .function, name: "g", line: 1, endLine: 1)],
      imports: [CodemapImport(raw: "./foo", line: 1)]
    )
    let result = try await AgentImportersOfTool().invoke(
      arguments: try JSONEncoder().encode(["path": "src/foo/index.ts"]),
      context: context
    )
    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("importers: 1"))
    XCTAssertTrue(result.content.contains("src/main.ts:1"))
  }

  func testImportersOfReportsEmptyAsOkay() async throws {
    try seedEntry(
      path: "src/foo.ts",
      symbols: [CodemapSymbol(kind: .function, name: "foo", line: 1, endLine: 1)]
    )
    let result = try await AgentImportersOfTool().invoke(
      arguments: try JSONEncoder().encode(["path": "src/foo.ts"]),
      context: context
    )
    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("No codemap entries import"))
  }

  // MARK: - Decoupled store directory

  /// Regression: under the Shared-VM route, `workingDirectory` is the
  /// guest worktree, but the codemap lives at the host's
  /// `<workspace.compassURL>/codemap`. The context must let callers
  /// thread that host path in so codemap-backed tools keep finding
  /// entries instead of returning empty results.
  func testCodemapStoreHonorsExplicitDirectorySeparateFromWorkingDirectory() async throws {
    let hostCodemapDirectory = workingDirectory.appendingPathComponent("host-codemap")
    let guestWorktree = workingDirectory.appendingPathComponent("guest-worktree")
    try FileManager.default.createDirectory(at: guestWorktree, withIntermediateDirectories: true)
    let store = CodemapStore(directory: hostCodemapDirectory)
    try store.saveEntry(
      CodemapEntry(
        relativePath: "Sources/MinimapView.swift",
        language: .swift,
        contentHash: String(repeating: "a", count: 64),
        sizeBytes: 100,
        symbols: [],
        imports: [],
        summary: nil,
        summaryModel: nil,
        summaryContentHash: nil
      ))

    let routedContext = AgentToolContext(
      workingDirectory: guestWorktree,
      codemapStoreDirectory: hostCodemapDirectory
    )
    let result = try await AgentListFilesTool().invoke(
      arguments: try JSONEncoder().encode(["filter": "minimap"]),
      context: routedContext
    )
    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("Sources/MinimapView.swift"))
  }

  // MARK: - Registration

  func testCodemapToolsAreRegisteredInReadOnlySet() {
    let names = ToolRegistry.readOnlyTools().map(\.spec.name)
    XCTAssertTrue(names.contains(AgentOutlineTool.toolName))
    XCTAssertTrue(names.contains(AgentFindSymbolTool.toolName))
    XCTAssertTrue(names.contains(AgentSummaryTool.toolName))
    XCTAssertTrue(names.contains(AgentListFilesTool.toolName))
    XCTAssertTrue(names.contains(AgentImportersOfTool.toolName))
  }

  // MARK: - Helpers

  private func seedEntry(
    path: String,
    symbols: [CodemapSymbol],
    imports: [CodemapImport] = [],
    summary: String? = nil,
    summaryModel: String? = nil
  ) throws {
    let store = CodemapStore(directory: cacheDirectory)
    let entry = CodemapEntry(
      relativePath: path,
      language: CodemapLanguage.forRelativePath(path) ?? .swift,
      contentHash: String(repeating: "a", count: 64),
      sizeBytes: 100,
      symbols: symbols,
      imports: imports,
      summary: summary,
      summaryModel: summaryModel,
      summaryContentHash: summary == nil ? nil : String(repeating: "a", count: 64)
    )
    try store.saveEntry(entry)
  }
}
