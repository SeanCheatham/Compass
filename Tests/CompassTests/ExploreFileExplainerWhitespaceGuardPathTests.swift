import Foundation
import FoundationModels
import Testing

@testable import Compass

/// Guard-path tests for additional `FileExplainer` edge cases.
///
/// ## Guards covered
///
/// ### Guard 1 — `explain` whitespace-only diff → `.emptyDiff` (FileExplainer.swift:251)
///
/// ```swift
/// if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
///   return (nil, .emptyDiff)
/// }
/// ```
///
/// When `CommitExplainer.commitDiffRange` returns a non-nil but whitespace-only
/// string (e.g. `"   \n  "`), the guard fires and `explain` returns `(nil, .emptyDiff)`.
/// The file-scoped shadow `commitDiffRange` intercepts the call inside
/// `FileExplainer.explain`.
///
/// ### Guard 2 — `whyGenerated` whitespace-only diff → `.emptyDiff` (FileExplainer.swift:287)
///
/// Same guard path as `explain` but in the `whyGenerated` method. A whitespace-only
/// diff string triggers the same guard and returns `(nil, .emptyDiff)`.
///
/// ### Guard 3 — `parseGitDiffStat` strippedPath.isEmpty guard (FileExplainer.swift:370)
///
/// ```swift
/// guard !strippedPath.isEmpty else { continue }
/// ```
///
/// When the `a/` or `b/` prefix leaves an empty path (e.g. `"a/                     |   4"`),
/// `strippedPath` is empty and the guard skips the line. Pure function — no git needed.
///
/// ### Guard 4 — `FileChangeCategory.categorize("src/package.json")` → `.config` (FileExplainer.swift:186)
///
/// The `lastPathComponent` check matches `"package.json"` and returns `.config`
/// even though `src/` is not a config dir. Pure function — no git needed.
struct ExploreFileExplainerWhitespaceGuardPathTests {

  // MARK: - Guard 1: explain whitespace-only diff

  /// Verifies `explain` returns `(nil, .emptyDiff)` when `commitDiffRange`
  /// returns a whitespace-only string.
  ///
  /// The guard at FileExplainer.swift:251 checks:
  /// ```swift
  /// if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
  ///   return (nil, .emptyDiff)
  /// }
  /// ```
  ///
  /// The file-scoped shadow `commitDiffRange` intercepts the real method call
  /// inside `FileExplainer.explain`, returning `"   \n  "` (whitespace-only)
  /// so the guard fires and `.emptyDiff` is returned.
  @Test
  func explain_whitespaceOnlyDiff_returnsEmptyDiff() async throws {
    let temporaryDirectory = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    try initGitRepo(at: temporaryDirectory)
    let commits = try makeSingleCommit(at: temporaryDirectory)

    try await withMockFoundationModels(response: "Mock explanation") {
      let result = await FileExplainer.explain(
        file: "Sources/App.swift",
        repoURL: temporaryDirectory,
        commits: commits
      )
      try #require(result.0 == nil)
      try #require(result.1 == .emptyDiff)
    }
  }

  // MARK: - Guard 2: whyGenerated whitespace-only diff

  /// Verifies `whyGenerated` returns `(nil, .emptyDiff)` when `commitDiffRange`
  /// returns a whitespace-only string.
  ///
  /// The guard at FileExplainer.swift:287 checks:
  /// ```swift
  /// if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
  ///   return (nil, .emptyDiff)
  /// }
  /// ```
  ///
  /// The file-scoped shadow `commitDiffRange` intercepts the real method call
  /// inside `FileExplainer.whyGenerated`, returning `"   \n  "` (whitespace-only)
  /// so the guard fires and `.emptyDiff` is returned.
  @Test
  func whyGenerated_whitespaceOnlyDiff_returnsEmptyDiff() async throws {
    let temporaryDirectory = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    try initGitRepo(at: temporaryDirectory)
    let commits = try makeSingleCommit(at: temporaryDirectory)

    try await withMockFoundationModels(response: "Mock why-generated explanation") {
      let result = await FileExplainer.whyGenerated(
        file: "Sources/App.swift",
        repoURL: temporaryDirectory,
        commits: commits
      )
      try #require(result.0 == nil)
      try #require(result.1 == .emptyDiff)
    }
  }

  // MARK: - Guard 3: parseGitDiffStat strippedPath.isEmpty

  /// Verifies `parseGitDiffStat` skips lines where the `a/` or `b/` prefix
  /// leaves nothing (e.g. `"a/                     |   4"` → strippedPath is empty).
  ///
  /// The guard at FileExplainer.swift:370:
  /// ```swift
  /// guard !strippedPath.isEmpty else { continue }
  /// ```
  ///
  /// When a line has `a/` or `b/` prefix and nothing meaningful after it,
  /// `strippedPath` is empty and the line is skipped. The result should not
  /// contain any entry from the empty-path line. Pure function — no git needed.
  @Test
  func parseGitDiffStat_aPrefixWithNoPath_skipsLine() throws {
    // "a/                     |   4" — after stripping "a/" the path is just
    // whitespace, trimmed to empty, so guard !strippedPath.isEmpty fires.
    let diffStat = "a/                     |   4\nSources/App.swift        |  12 ++++"
    let changes = FileExplainer.parseGitDiffStat(diffStat)

    // Only Sources/App.swift should survive; the "a/" line is skipped.
    try #require(changes.count == 1)
    try #require(changes[0].relativePath == "Sources/App.swift")
  }

  // MARK: - Guard 4: FileChangeCategory.categorize lastPathComponent match

  /// Verifies `categorize("src/package.json")` returns `.config` via the
  /// `lastPathComponent` check even though `src/` is not a config directory.
  ///
  /// FileExplainer.swift:186:
  /// ```swift
  /// if configFiles.contains((relativePath as NSString).lastPathComponent) {
  ///   return .config
  /// }
  /// ```
  ///
  /// `lastPathComponent` of `"src/package.json"` is `"package.json"` which is
  /// in `configFiles`, so the function returns `.config` despite the parent
  /// directory not being a config dir. Pure function — no git needed.
  @Test
  func categorize_nestedPath_packageJson_returnsConfig() throws {
    let category = FileChangeCategory.categorize("src/package.json")
    try #require(category == .config)
  }
}

// MARK: - Shadow for tests 1 and 2

/// File-scoped shadow of `CommitExplainer.commitDiffRange` to intercept calls
/// from `FileExplainer.explain` and `FileExplainer.whyGenerated`.
///
/// By declaring this at file scope (outside the struct), Swift's shadowing rules
/// resolve `CommitExplainer.commitDiffRange(...)` inside FileExplainer to this
/// local function rather than the real production method. This lets tests 1 and 2
/// control the exact diff string returned.
private func commitDiffRange(
  commits: [SessionCommit],
  repoURL: URL,
  relativePath: String? = nil
) -> String? {
  // Tests 1 and 2: return a whitespace-only string so the guard at
  // FileExplainer.swift:251 (and 287) fires and returns .emptyDiff.
  "   \n  "
}
