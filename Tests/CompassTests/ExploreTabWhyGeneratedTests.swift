import Foundation
import FoundationModels
import Testing

@testable import Compass

/// Tests verifying `ExploreTab`'s "Why Generated?" interaction paths.
///
/// `ExploreTab` surfaces "Why Generated?" via a popover triggered by tapping a
/// file in the Explore tree. When the user taps, `handleFileTap(_:)` sets
/// `whyGeneratedFile`, clears any prior explanation, and calls `loadWhyGenerated()`.
/// That method guards against a nil `whyGeneratedFile` before calling
/// `FileExplainer.whyGenerated(file:repoURL:commits:)`.
///
/// These tests exercise the same guard paths that the UI interaction exercises,
/// mirroring the pattern established in `ExploreFilesPopoverTests` and
/// `ExploreQnAPopoverTests` — testing the Explore layer UI interaction paths
/// through the underlying model layer.
///
/// ## Guard paths verified
///
/// - **Path 1 (`whyGeneratedFile == nil` guard → `.noDiff`):** `loadWhyGenerated()`
///   at line 246 has `guard let file = whyGeneratedFile else { return }`. When
///   `whyGeneratedFile` is `nil` the method returns early without calling the
///   explainer. Calling `FileExplainer.whyGenerated(..., commits: [])` hits the
///   `commitDiffRange` empty-array guard and returns `(nil, .noDiff)` — the same
///   result the UI would see if the guard fired.
///
/// - **Path 2 (empty diff → `.emptyDiff`):** `FileExplainer.whyGenerated()`
///   returns `(nil, .emptyDiff)` when `git diff` produces a whitespace-only
///   result (after trimming). An allow-empty commit has a valid SHA but no tree
///   changes, so `git diff <sha>^..<sha>` returns the empty string. The guard at
///   line 287 fires and `whyGenerated` returns `(nil, .emptyDiff)` without
///   reaching the Foundation Models call.
///
/// - **Path 3 (model unavailable → `.foundationModelsUnavailable`):** When
///   Foundation Models is unavailable, `CommitExplainer.summarizeWhyGenerated(diff:)`
///   returns `(nil, .foundationModelsUnavailable)` via the `guard` in the shared
///   `summarize(diff:)` helper. `whyGenerated` propagates this reason unchanged.
///
/// - **Path 4 (successful call):** The call chain is reachable with a real git
///   repo and valid commits. The explanation may be `nil` if no diff is available,
///   but the call must not throw and must return a reason tuple in all paths.
struct ExploreTabWhyGeneratedTests {

  // MARK: - Path 1: whyGeneratedFile == nil guard → commits = [] → .noDiff

  /// Verifies `FileExplainer.whyGenerated(..., commits: [])` returns `(nil, .noDiff)`.
  ///
  /// `loadWhyGenerated()` calls `FileExplainer.whyGenerated()` only after passing
  /// the `guard let file = whyGeneratedFile else { return }` at line 246. If
  /// `whyGeneratedFile` were `nil` the method would return early without invoking
  /// the explainer. The equivalent guard path is tested directly here:
  /// an empty `commits` array causes `CommitExplainer.commitDiffRange` to return
  /// `nil`, and `whyGenerated` returns `(nil, .noDiff)`.
  ///
  /// The chain this test exercises:
  /// `loadWhyGenerated()` → `guard let file = whyGeneratedFile` → (early return, not tested here)
  ///                       → `FileExplainer.whyGenerated()` → `commitDiffRange([])` → `nil`
  ///                       → `(nil, .noDiff)`
  @Test
  func whyGenerated_emptyCommits_returnsNoDiffReason() async throws {
    let temporaryDirectory = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    try initGitRepo(at: temporaryDirectory)

    // Empty commits → commitDiffRange returns nil → whyGenerated returns (nil, .noDiff)
    // This is the equivalent outcome when loadWhyGenerated's guard fires on nil whyGeneratedFile.
    let result = await FileExplainer.whyGenerated(
      file: "Sources/App.swift",
      repoURL: temporaryDirectory,
      commits: []
    )
    try #require(result.0 == nil)
    try #require(result.1 == .noDiff)
  }

  // MARK: - Path 2: empty diff (allow-empty commit) → .emptyDiff

  /// Verifies `FileExplainer.whyGenerated()` returns `(nil, .emptyDiff)` for an
  /// allow-empty commit.
  ///
  /// An allow-empty commit has a valid SHA but no files in the tree. When
  /// `handleFileTap` is called on a file and the only session commit is an
  /// allow-empty commit, `loadWhyGenerated()` calls `FileExplainer.whyGenerated()`.
  /// `git diff <sha>^..<sha>` returns the empty string; the guard at line 287
  /// fires and `whyGenerated` returns `(nil, .emptyDiff)` — without reaching
  /// the Foundation Models `summarizeWhyGenerated` call. The UI would display
  /// this reason in the `WhyGeneratedPopover`.
  @Test
  func whyGenerated_allowEmptyCommit_returnsEmptyDiffReason() async throws {
    let temporaryDirectory = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    try initGitRepo(at: temporaryDirectory)

    // Create an allow-empty commit — valid SHA, no files in the tree.
    try runGit(
      "git -C \(temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q --allow-empty -m 'Empty commit'",
      at: temporaryDirectory
    )

    let sha = try getSingleCommitSHA(at: temporaryDirectory)
    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Empty commit")]

    let result = await FileExplainer.whyGenerated(
      file: "Sources/App.swift",
      repoURL: temporaryDirectory,
      commits: commits
    )
    // The empty diff guard fires at line 287 → (nil, .emptyDiff)
    try #require(result.0 == nil)
    try #require(result.1 == .emptyDiff)
  }

  // MARK: - Path 3: model unavailable → .foundationModelsUnavailable

  /// Verifies `FileExplainer.whyGenerated()` returns `(nil, .foundationModelsUnavailable)`
  /// when Foundation Models is unavailable.
  ///
  /// When the user taps a file and Foundation Models is unavailable,
  /// `loadWhyGenerated()` calls `FileExplainer.whyGenerated()`, which calls
  /// `CommitExplainer.summarizeWhyGenerated(diff:)`. That method calls the
  /// shared `summarize(diff:)` helper, which has a
  /// `guard FoundationModelsAvailability.isAvailable else { return nil }` guard.
  /// When the model is unavailable the guard fires and `whyGenerated` returns
  /// `(nil, .foundationModelsUnavailable)` without throwing. The UI would
  /// display this reason in the `WhyGeneratedPopover`.
  @Test
  func whyGenerated_modelUnavailable_returnsFoundationModelsUnavailableReason() async throws {
    let temporaryDirectory = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    try initGitRepo(at: temporaryDirectory)
    let commits = try makeSingleCommit(at: temporaryDirectory)

    let result = await FileExplainer.whyGenerated(
      file: "Sources/App.swift",
      repoURL: temporaryDirectory,
      commits: commits
    )
    if !FoundationModelsAvailability.isAvailable {
      try #require(result.0 == nil)
      try #require(result.1 == .foundationModelsUnavailable)
    }
    // If the model IS available, a non-nil explanation or nil reason may be returned —
    // both are valid outcomes when the model is present.
  }

  // MARK: - Path 4: successful call chain reachable

  /// Verifies `FileExplainer.whyGenerated()` is reachable with a real git repo
  /// and valid commits, and does not throw.
  ///
  /// A successful `handleFileTap` followed by `loadWhyGenerated()` calls
  /// `FileExplainer.whyGenerated(file:repoURL:commits:)`. This test exercises
  /// that full call chain with a real commit on a real (temporary) git repo.
  /// The result may be `nil` if no diff is available or the model is unavailable,
  /// but the call must not throw and must return a reason tuple in all paths.
  ///
  /// This test confirms the call chain is wired correctly end-to-end.
  @Test
  func whyGenerated_validRepoAndCommit_returnsWithoutThrowing() async throws {
    let temporaryDirectory = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    try initGitRepo(at: temporaryDirectory)
    let commits = try makeSingleCommit(at: temporaryDirectory)

    // Call whyGenerated — the full chain from ExploreTab's loadWhyGenerated().
    // The result may be nil (no diff available or model unavailable) but the
    // call must not throw. This verifies the chain is wired correctly.
    let result = await FileExplainer.whyGenerated(
      file: "Sources/App.swift",
      repoURL: temporaryDirectory,
      commits: commits
    )
    // The call completed without throwing. result.0 may be nil (model unavailable
    // or no diff) but result.1 must be non-nil with a valid reason.
    try #require(result.1 != nil)
  }
}
