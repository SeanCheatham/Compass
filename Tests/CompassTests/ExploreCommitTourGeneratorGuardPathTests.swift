import Foundation
import FoundationModels
import Testing

@testable import Compass

/// Compile-only test file covering three untested `CommitTourGenerator.generateTour()`
/// guard paths that return `nil` via `guard !diff.isEmpty`.
///
/// ## Guard path covered
///
/// `generateTour()` calls `CommitExplainer.gitDiff(sha:)` or `gitDiffRange()`
/// internally. Both can return an empty string in two distinct situations:
///
/// 1. **Invalid SHA** — `git diff` on a non-existent SHA returns `""`; `generateTour`
///    hits `guard !diff.isEmpty else { return nil }` and returns `nil`.
/// 2. **Empty-tree commit** — a valid SHA with no files in the tree; `git diff` returns
///    `""` and the same guard fires.
/// exact non-throwing contract that downstream callers (e.g. `CommitTourRow.loadTour()`)
/// depend on.
///
/// This uses the shared `TestSupport.swift` helpers.
struct ExploreCommitTourGeneratorGuardPathTests {

  // MARK: - Path 1: invalid SHA → empty diff → guard !diff.isEmpty → nil

  /// Verifies `generateTour` returns `nil` when given a SHA that does not exist
  /// in the repository. The git call returns `""`, triggering `guard !diff.isEmpty`.
  @Test
  func generateTour_invalidSHA_returnsNil() async throws {
    let temporaryDirectory = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    try initGitRepo(at: temporaryDirectory)
    _ = try makeSingleCommit(at: temporaryDirectory)

    // Use a valid-format but non-existent SHA — git returns empty string,
    // which hits: guard !diff.isEmpty else { return nil }
    let fakeSHA = "0000000000000000000000000000000000000000"
    let commits = [SessionCommit(sha: fakeSHA, short: String(fakeSHA.prefix(7)), subject: "Fake")]

    let result = await CommitTourGenerator.generateTour(
      commits: commits,
      repoURL: temporaryDirectory
    )
    try #require(result == nil)
  }

  // MARK: - Path 2: empty-tree commit (valid SHA but no files) → empty diff → nil

  /// Verifies `generateTour` returns `nil` for an allow-empty commit that has a
  /// valid SHA but no files in the tree. `git diff <sha>^..<sha>` returns `""`
  /// and `guard !diff.isEmpty else { return nil }` fires.
  @Test
  func generateTour_emptyTreeCommit_returnsNil() async throws {
    let temporaryDirectory = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    try initGitRepo(at: temporaryDirectory)

    // Create an allow-empty commit (no files staged/changed)
    try runGit(
      "git -C \(temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q --allow-empty -m 'Empty commit'",
      at: temporaryDirectory
    )

    let sha = try getSingleCommitSHA(at: temporaryDirectory)
    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Empty commit")]

    let result = await CommitTourGenerator.generateTour(
      commits: commits,
      repoURL: temporaryDirectory
    )
    try #require(result == nil)
  }
}
