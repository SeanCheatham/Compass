import Foundation
import FoundationModels
import Testing

@testable import Compass

/// Tests verifying `ExploreFilesPopover.loadChanges()` guard behaviors.
///
/// Due to the Swift 6.3.2 toolchain limitation (`swift build --target CompassTests`
/// fails due to a linker error in SwiftTestingMacros), SwiftUI view instantiation
/// cannot be tested in-process. These tests exercise `FileExplainer.changes(for:)`
/// and `FileExplainer.explain()` directly under the same conditions that
/// `loadChanges()` evaluates.
///
/// ## Guard paths verified
///
/// - **Path 1 (empty commits → no changes):** `loadChanges()` calls
///   `FileExplainer.changes(for:)` at line 1504. When `item.commits` is empty,
///   `changes(for:)` returns `[]` early at line 323:
///   `guard let first = commits.first else { return [] }` — no git diff is run.
///   The popover renders the `changes.isEmpty` empty state ("No file changes found").
///
/// - **Path 3 (model unavailable):** `loadChanges()` calls
///   `FileExplainer.explain(file:repoURL:commits:)` for each loaded file (line 1528).
///   When Foundation Models is unavailable, `CommitExplainer.summarize(diff:)`
///   returns `nil` (non-throwing) → `explanation` stays `nil` for each file.
///
/// This mirrors the structure of `ExplorePerCommitNarrativesPopoverTests` (which
/// tests `CommitExplainer.explain()` empty-commits guard) and
/// `ExploreQnAPopoverTests` (which tests `RepoQnA.answer()` model-unavailable path).
struct ExploreFilesPopoverTests {

  // MARK: - Path 1: empty commits → FileExplainer.changes(for:) returns []

  /// Verifies `FileExplainer.changes(for:)` returns `[]` when commits is empty.
  ///
  /// `loadChanges()` calls `FileExplainer.changes(for:)` at line 1504. When
  /// `item.commits` is empty, `changes(for:)` hits the guard at line 323:
  /// `guard let first = commits.first else { return [] }` — no git diff is run.
  ///
  /// The popover would then render the `changes.isEmpty` empty state:
  /// "No file changes found in these commits."
  @Test
  func loadChanges_emptyCommits_returnsEmptyChanges() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try initGitRepo(at: test.temporaryDirectory)

    let emptyCommits: [SessionCommit] = []

    // When commits is empty, changes(for:) returns [] at the guard (line 323)
    // before any git diff is run. The popover would show the empty state.
    let result = await FileExplainer.changes(for: test.temporaryDirectory, commits: emptyCommits)

    #require(result.isEmpty)
  }

  // MARK: - Path 3: FileExplainer.explain returns nil when Foundation Models is unavailable
  //          → loadChanges() would leave explanation = nil for each file

  /// Verifies `FileExplainer.explain()` returns `nil` when Foundation Models is unavailable.
  ///
  /// `loadChanges()` calls `FileExplainer.explain(file:repoURL:commits:)` for each
  /// file at line 1528. When Foundation Models is unavailable,
  /// `CommitExplainer.summarize(diff:)` returns `nil` (non-throwing), so
  /// `explain()` propagates `nil` → `explanation` stays `nil` for each file.
  ///
  /// The chain this test exercises:
  /// `loadChanges()` → `FileExplainer.explain()` → `CommitExplainer.summarize(diff:)`
  ///                   → `nil` (model unavailable) → `explanation = nil`
  @Test
  func loadChanges_explainReturnsNil_leavesExplanationNil() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try initGitRepo(at: test.temporaryDirectory)
    let commits = try makeSingleCommit(at: test.temporaryDirectory)

    // Call explain directly — this is what loadChanges() does at line 1528.
    // When Foundation Models is unavailable, it returns nil (non-throwing),
    // which leaves the per-file explanation nil in the loaded changes array.
    let result = await FileExplainer.explain(
      file: "Sources/App.swift",
      repoURL: test.temporaryDirectory,
      commits: commits
    )

    if !FoundationModelsAvailability.isAvailable {
      // The nil return is the expected result when the model is unavailable.
      #require(result == nil)
    }
    // If the model IS available, a non-nil string would be returned — both are valid.
  }

  // MARK: - Helpers

  private var temporaryDirectory: URL!

  private mutating func setUp() {
    temporaryDirectory = try! makeTempDir()
  }

  private mutating func tearDown() {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    temporaryDirectory = nil
  }
}
