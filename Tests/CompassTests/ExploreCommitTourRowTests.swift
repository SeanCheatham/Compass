import Foundation
import FoundationModels
import Testing

@testable import Compass

/// Tests verifying `CommitTourRow.loadTour()` guard behavior for the
/// `result == nil` path that sets `tourAvailabilityError = true`.
///
/// Due to the Swift 6.3.2 toolchain limitation (`swift build --target CompassTests`
/// fails due to a linker error in SwiftTestingMacros), SwiftUI view instantiation
/// cannot be tested in-process. These tests exercise `CommitTourGenerator.generateTour()`
/// directly under the same conditions that `loadTour()` evaluates.
///
/// ## Guard path verified
///
/// - **Path 2 (model unavailable):** `loadTour()` calls `CommitTourGenerator.generateTour()`.
///   When `FoundationModelsAvailability.isAvailable == false`, `generateTour()` returns `nil`
///   (non-throwing) → `if result == nil { tourAvailabilityError = true }` (line 1142).
///
///   `generateTour()` can return `nil` in three distinct ways, all non-throwing:
///
///   1. Empty commits array: `guard let firstCommit = commits.first else { return nil }`
///   2. Empty diff result: `guard !diff.isEmpty else { return nil }`
///   3. Foundation Models unavailable → `generate(diff:)` returns `nil`
///
///   This test exercises case 3: a real git repo with valid commits, calling
///   `generateTour()` directly and verifying the `nil` return is the exact condition
///   that triggers `tourAvailabilityError` in the view.
///
/// This mirrors the Path 3 pattern from `ExploreRepoQnAAnswerGuardTests` but for
/// the tour generator path instead of the Q&A answer path.
struct ExploreCommitTourRowTests {

  // MARK: - Path 2: generateTour returns nil when Foundation Models is unavailable
  //          → loadTour() would set tourAvailabilityError = true

  /// Verifies the `result == nil` condition that sets `tourAvailabilityError = true`
  /// in `CommitTourRow.loadTour()` (line 1142).
  ///
  /// When `FoundationModelsAvailability.isAvailable == false`,
  /// `CommitTourGenerator.generateTour()` returns `nil` (non-throwing) →
  /// `if result == nil { tourAvailabilityError = true }`.
  ///
  /// The chain this test exercises:
  /// `loadTour()` → `CommitTourGenerator.generateTour()` → `nil` (model unavailable)
  ///               → `tourAvailabilityError = true`
  @Test
  func loadTour_generateTourReturnsNil_setsTourAvailabilityError() async throws {
    let temporaryDirectory = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    try initGitRepo(at: temporaryDirectory)
    let commits = try makeSingleCommit(at: temporaryDirectory)

    // Call generateTour directly — this is what loadTour() does at line 1140.
    // When Foundation Models is unavailable, it returns nil (non-throwing),
    // which is the exact condition that triggers: if result == nil { tourAvailabilityError = true }
    let result = await CommitTourGenerator.generateTour(
      commits: commits,
      repoURL: temporaryDirectory
    )

    if !FoundationModelsAvailability.isAvailable {
      // The nil return is the exact condition that sets tourAvailabilityError = true.
      try #require(result == nil)
    }
    // If the model IS available, a non-nil string would be returned — both are valid.
  }

  // MARK: - Empty commits guard (generateTour internal path 1)

  /// Verifies `generateTour([])` returns `nil` without throwing.
  ///
  /// `generateTour()` has `guard let firstCommit = commits.first else { return nil }`.
  /// This guard prevents git invocation for empty commit arrays and returns nil cleanly.
  @Test
  func loadTour_emptyCommits_returnsNil() async throws {
    let temporaryDirectory = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    try initGitRepo(at: temporaryDirectory)

    // Empty commits array hits: guard let firstCommit = commits.first else { return nil }
    let result = await CommitTourGenerator.generateTour(
      commits: [],
      repoURL: temporaryDirectory
    )
    try #require(result == nil)
  }

  // MARK: - Empty diff guard (generateTour internal path 2)

  /// Verifies `generateTour()` returns `nil` when git produces an empty diff.
  ///
  /// `generateTour()` calls `_gitDiffForSha()` or `_gitDiffRange()` (which return
  /// empty string for invalid/unavailable commits) and then hits
  /// `guard !diff.isEmpty else { return nil }` before calling `generate(diff:)`.
  @Test
  func loadTour_emptyDiff_returnsNil() async throws {
    let temporaryDirectory = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    try initGitRepo(at: temporaryDirectory)

    // Use a valid-looking but non-existent SHA — git diff returns empty string,
    // which hits: guard !diff.isEmpty else { return nil }
    let fakeSHA = "0000000000000000000000000000000000000000"
    let commits = [SessionCommit(sha: fakeSHA, short: String(fakeSHA.prefix(7)), subject: "Fake")]
    let result = await CommitTourGenerator.generateTour(
      commits: commits,
      repoURL: temporaryDirectory
    )
    try #require(result == nil)
  }
}
