import Foundation
import FoundationModels
import Testing

@testable import Compass

/// Compile-only test file covering the `FileExplainer.explain()` guard path when
/// `gitDiff` returns an empty string for an empty-tree commit.
///
/// ## Guard path covered
///
/// `explain(file:repoURL:commits:)` calls `CommitExplainer.gitDiff(sha:)` internally.
/// When given a valid SHA that has no files in the tree (empty-tree commit),
/// `git diff <sha>^..<sha>` returns `""`. This triggers the guard at
/// `if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }`
/// and `explain()` returns `nil` — without throwing.
///
/// This mirrors the guard-path pattern established in
/// `ExploreCommitTourGeneratorGuardPathTests.swift`.
///
/// ## Why this matters
///
/// `explain()` is called by Explore popover code when the user requests an
/// AI explanation for a changed file. The `nil` return is the expected
/// non-throwing contract that callers handle gracefully. An empty-tree
/// commit can legitimately occur when the user browses a commit that added
/// no files (e.g., a metadata-only commit, a merge commit with no conflicts,
/// or a forced-empty commit during rebase).
///
/// This uses the same helper pattern established in
/// `ExploreCommitTourGeneratorGuardPathTests.swift`.
struct ExploreFileExplainerEmptyCommitsTests {

  // MARK: - Empty-tree commit → gitDiff returns "" → guard returns nil

  /// Verifies `explain()` returns `nil` when given a valid SHA whose tree
  /// contains no files. `git diff <sha>^..<sha>` returns `""` (nothing to diff),
  /// triggering `if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }`.
  ///
  /// The chain exercised:
  /// `explain(file:"Sources/App.swift", repoURL, commits=[sha])` →
  /// `CommitExplainer.gitDiff(sha: sha, repoURL:)` returns `""` (empty-tree) →
  /// `guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` →
  /// `nil`
  @Test
  func explain_emptyTreeCommit_returnsNil() async throws {
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

    // Even though the file path is valid, the commit has no files — git diff
    // returns "" and explain() returns nil via the guard check.
    let result = await FileExplainer.explain(
      file: "Sources/App.swift",
      repoURL: temporaryDirectory,
      commits: commits
    )
    try #require(result.0 == nil)
  }
}
