import Foundation
import Testing

@testable import Compass

struct AgentCodemapToolsTests: ~Copyable {
  private var workingDirectory: URL!
  private var cacheDirectory: URL!
  private var context: AgentToolContext!

  init() throws {
    workingDirectory = try makeTempDir()
    cacheDirectory = workingDirectory.appendingPathComponent(".compass/codemap")
    context = AgentToolContext(workingDirectory: workingDirectory)
  }

  deinit {
    if let workingDirectory {
      try? FileManager.default.removeItem(at: workingDirectory)
    }
  }

  // MARK: - outline

  @Test func testOutlineReturnsSymbolsAndImports() async throws {
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
    #require(!result.isError)
    #require(result.content.contains("path: Sources/Foo.swift"))
    #require(result.content.contains("imports:"))
    #require(result.content.contains("Foundation"))
    #require(result.content.contains("L4-12  class  Foo"))
    #require(result.content.contains("L7-9  function  bar"))
  }

  @Test func testOutlineSurfacesMissingEntryAsError() async throws {
    let result = try await AgentOutlineTool().invoke(
      arguments: try JSONEncoder().encode(["path": "missing.swift"]),
      context: context
    )
    #require(result.isError)
    #require(result.content.contains("No codemap entry"))
  }

  // MARK: - find_symbol

  @Test func testFindSymbolReturnsAllMatches() async throws {
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
    #require(!result.isError)
    #require(result.content.contains("matches: 2"))
    #require(result.content.contains("a.swift:10  class"))
    #require(result.content.contains("b.swift:5  struct"))
  }

  @Test func testFindSymbolFiltersByKind() async throws {
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
    #require(!result.isError)
    #require(result.content.contains("matches: 1"))
    #require(result.content.contains("a.swift:10  class"))
    #require(!result.content.contains("a.swift:50"))
  }

  @Test func testFindSymbolReportsMissAsOkay() async throws {
    let result = try await AgentFindSymbolTool().invoke(
      arguments: try JSONEncoder().encode(["name": "Nope"]),
      context: context
    )
    #require(!result.isError)
    #require(result.content.contains("No codemap symbol named 'Nope'"))
  }

  // MARK: - summary

  @Test func testSummaryReturnsCachedText() async throws {
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
    #require(!result.isError)
    #require(result.content.contains("summarized by Haiku-tier"))
    #require(result.content.contains("Foo holds the running state."))
  }

  @Test func testSummaryReportsMissingPassAsOkay() async throws {
    try seedEntry(
      path: "Sources/Foo.swift",
      symbols: [CodemapSymbol(kind: .class, name: "Foo", line: 1, endLine: 1)]
    )
    let result = try await AgentSummaryTool().invoke(
      arguments: try JSONEncoder().encode(["path": "Sources/Foo.swift"]),
      context: context
    )
    #require(!result.isError)
    #require(result.content.contains("No summary yet"))
  }

  // MARK: - list_files

  @Test func testListFilesReturnsEverythingWhenNoFilter() async throws {
    try seedEntry(path: "a.swift", symbols: [])
    try seedEntry(path: "lib/b.swift", symbols: [])
    let result = try await AgentListFilesTool().invoke(
      arguments: Data("{}".utf8),
      context: context
    )
    #require(!result.isError)
    #require(result.content.contains("files: 2"))
    #require(result.content.contains("a.swift"))
    #require(result.content.contains("lib/b.swift"))
  }

  @Test func testListFilesFiltersBySubstring() async throws {
    try seedEntry(path: "alpha.swift", symbols: [])
    try seedEntry(path: "lib/beta.swift", symbols: [])
    let result = try await AgentListFilesTool().invoke(
      arguments: try JSONEncoder().encode(["filter": "beta"]),
      context: context
    )
    #require(!result.isError)
    #require(result.content.contains("files: 1"))
    #require(result.content.contains("lib/beta.swift"))
    #require(!result.content.contains("alpha.swift"))
  }

  // MARK: - importers_of

  @Test func testImportersOfMatchesRelativeImports() async throws {
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
    #require(!result.isError)
    #require(result.content.contains("importers: 1"))
    #require(result.content.contains("src/bar.ts:1"))
  }

  @Test func testImportersOfMatchesIndexBareImport() async throws {
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
    #require(!result.isError)
    #require(result.content.contains("importers: 1"))
    #require(result.content.contains("src/main.ts:1"))
  }

  @Test func testImportersOfReportsEmptyAsOkay() async throws {
    try seedEntry(
      path: "src/foo.ts",
      symbols: [CodemapSymbol(kind: .function, name: "foo", line: 1, endLine: 1)]
    )
    let result = try await AgentImportersOfTool().invoke(
      arguments: try JSONEncoder().encode(["path": "src/foo.ts"]),
      context: context
    )
    #require(!result.isError)
    #require(result.content.contains("No codemap entries import"))
  }

  // MARK: - Decoupled store directory

  /// Regression: under the Shared-VM route, `workingDirectory` is the
  /// guest worktree, but the codemap lives at the host's
  /// `<workspace.compassURL>/codemap`. The context must let callers
  /// thread that host path in so codemap-backed tools keep finding
  /// entries instead of returning empty results.
  @Test func testCodemapStoreHonorsExplicitDirectorySeparateFromWorkingDirectory() async throws {
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
    #require(!result.isError)
    #require(result.content.contains("Sources/MinimapView.swift"))
  }

  // MARK: - Registration

  @Test func testCodemapToolsAreRegisteredInReadOnlySet() {
    let names = ToolRegistry.readOnlyTools().map(\.spec.name)
    #require(names.contains(AgentOutlineTool.toolName))
    #require(names.contains(AgentFindSymbolTool.toolName))
    #require(names.contains(AgentSummaryTool.toolName))
    #require(names.contains(AgentListFilesTool.toolName))
    #require(names.contains(AgentImportersOfTool.toolName))
  }

  // MARK: - CodemapLanguage / forRelativePath

  @Test func testCodemapLanguageForRelativePath_UnusualExtensions() async throws {
    // seedEntry uses CodemapLanguage.forRelativePath internally (line 279),
    // so these exercise it transitively as a smoke test.
    try seedEntry(path: "foo.mts",  symbols: [])
    try seedEntry(path: "bar.cts",  symbols: [])
    try seedEntry(path: "baz.tsx",  symbols: [])
    try seedEntry(path: "qux.pyi",  symbols: [])
    try seedEntry(path: "fle.mjs",  symbols: [])
    try seedEntry(path: "app.cjs",  symbols: [])

    // Explicit direct assertions — nil means "unsupported extension".
    #require(CodemapLanguage.forRelativePath("foo.mts") == .typescript)
    #require(CodemapLanguage.forRelativePath("bar.cts") == .typescript)
    #require(CodemapLanguage.forRelativePath("baz.tsx") == .tsx)
    #require(CodemapLanguage.forRelativePath("qux.pyi") == .python)
    #require(CodemapLanguage.forRelativePath("fle.mjs") == .javascript)
    #require(CodemapLanguage.forRelativePath("app.cjs") == .javascript)
    #require(CodemapLanguage.forRelativePath("no-extension") == nil)
    #require(CodemapLanguage.forRelativePath(".unknown-ext") == nil)
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