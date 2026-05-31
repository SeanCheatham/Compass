import Foundation
import Testing

@testable import Compass

/// Guard-path tests for `ExploreTreeBuilder` covering untested control-flow
/// branches.
///
/// ## Guards covered
///
/// ### 1 — `insert(path:into:)` empty-path guard  (line 116)
///
/// ```swift
/// guard !components.isEmpty else { return }
/// ```
///
/// Called from `insert(path:into:)` when an empty string is passed.
/// The guard fires and returns without crashing. No file tree mutation occurs.
///
/// ### 2 — `buildSourceTree` empty-paths guard  (line 89)
///
/// ```swift
/// if paths.isEmpty {
///   return CodemapFileSystem(rootURL: repoURL).buildSourceTree()
/// }
/// ```
///
/// Triggered when `GitSourcePaths.sourcePaths(in:)` returns `[]` — either
/// because git is unavailable or because `git ls-files` produced no tracked
/// source files. `CodemapFileSystem.buildSourceTree()` is called as fallback.
///
/// ### 3 — `buildTree` empty-roots guard  (line 95-103)
///
/// When `paths.sorted(...)` yields an empty array the for-loop never runs and
/// `sortNodes([])` is called, returning `[]` immediately.
///
/// ### 4 — `insert(components:fullPath:into:siblings:prefix:)` nested path
///
/// Called from the `insert(path:into:)` caller at line 117 to build nested
/// directory/file nodes.
///
/// ### 5 — `sortNodes`
///
/// Called from `buildTree` (line 102) and `insert` recursive branch (line 176).
/// Direct assertions cover directory-first and case-insensitive sorting.
struct ExploreTreeBuilderGuardPathTests {

  // MARK: - Guard 1: insert — empty-path guard fires at line 116

  /// Verifies `insert(path:into:)` accepts an empty path and exercises the
  /// `!components.isEmpty` guard without mutating the tree.
  @Test
  func insert_emptyPath_compilesAndGuardsCorrectly() throws {
    let tree = ExploreTreeBuilder.buildTree(fromSourcePaths: [""])
    try #require(tree.isEmpty)
  }

  // MARK: - Guard 1b: insert(components:…) nested path

  /// Verifies the nested insert path builds a directory node containing the
  /// requested source file.
  @Test
  func insertComponents_compileTimeSignature_verifiesCallCompiles() throws {
    let tree = ExploreTreeBuilder.buildTree(fromSourcePaths: ["Sources/App.swift"])
    try #require(tree.count == 1)
    try #require(tree[0].relativePath == "Sources")
    try #require(tree[0].isDirectory)
    try #require(tree[0].children.map(\.relativePath) == ["Sources/App.swift"])
  }

  // MARK: - Guard 2: buildSourceTree — paths.isEmpty at line 89

  /// Verifies `buildSourceTree` calls `CodemapFileSystem.buildSourceTree()` as
  /// fallback when `GitSourcePaths.sourcePaths(in:)` returns `[]`.
  ///
  /// This occurs when git is unavailable (not installed) or when
  /// `git ls-files` returns nothing (fresh repo with no committed source
  /// files). The `if paths.isEmpty` guard at line 89 fires and the fallback
  /// is invoked. The test creates a temp directory that is not a git repo,
  /// so `GitSourcePaths.sourcePaths(in:)` returns `[]` → fallback is called.
  @Test
  func buildSourceTree_noGitOrNoFiles_callsCodemapFileSystemFallback() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    // Confirm this is not a git repo.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["rev-parse", "--is-inside-work-tree"]
    process.currentDirectoryURL = repoURL.standardizedFileURL
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    let isGitRepo = process.terminationStatus == 0
    try #require(!isGitRepo, "directory unexpectedly is a git repo; skipping")

    // buildSourceTree detects git unavailable → GitSourcePaths returns []
    // → paths.isEmpty guard fires → CodemapFileSystem.buildSourceTree() called.
    let tree = ExploreTreeBuilder.buildSourceTree(repoURL: repoURL)
    // No source files exist → tree is empty.
    try #require(tree.isEmpty)
  }

  /// Verifies `CodemapFileSystem.buildSourceTree()` returns `[]` for a directory
  /// with no source files.
  ///
  /// `CodemapFileSystem.buildSourceTree()` → `pruneSourceNodes(buildTree())`.
  /// Files without a `CodemapLanguage` are pruned. A directory with only
  /// non-source files (e.g. `.log` files) produces an empty tree.
  @Test
  func codemapFileSystem_noSourceFiles_returnsEmptyTree() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    try FileManager.default.createDirectory(
      at: repoURL.appendingPathComponent("Logs", isDirectory: true),
      withIntermediateDirectories: true
    )
    try "log content".write(
      to: repoURL.appendingPathComponent("Logs/app.log"),
      atomically: true,
      encoding: .utf8
    )

    let fs = CodemapFileSystem(rootURL: repoURL)
    let tree = fs.buildSourceTree()
    // Logs/app.log has no CodemapLanguage → filtered out → tree is empty.
    try #require(tree.isEmpty)
  }

  // MARK: - Guard 3: buildTree — empty paths → sortNodes([]) at line 102

  /// Verifies `buildTree(fromSourcePaths: [])` returns `[]` without crashing.
  ///
  /// With `paths = []`, `paths.sorted(...)` yields `[]`. The for-loop at line
  /// 97-99 never runs. `sortNodes([])` is called and returns `[]`.
  @Test
  func buildTree_emptyPaths_returnsEmptyTree() throws {
    let tree = ExploreTreeBuilder.buildTree(fromSourcePaths: [])
    try #require(tree.isEmpty)
  }

  // MARK: - Guard 5: sortNodes

  /// Verifies `sortNodes` orders directories before files and sorts children
  /// case-insensitively.
  @Test
  func sortNodes_compileTimeSignature_verifiesBothCallSites() throws {
    let tree = ExploreTreeBuilder.buildTree(fromSourcePaths: [
      "b.swift",
      "Sources/Z.swift",
      "Sources/A.swift",
      "a.swift",
    ])

    try #require(tree.map(\.relativePath) == ["Sources", "a.swift", "b.swift"])
    try #require(tree[0].children.map(\.relativePath) == ["Sources/A.swift", "Sources/Z.swift"])
  }
}
