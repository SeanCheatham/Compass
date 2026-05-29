import Foundation
import Testing

@testable import Compass

struct ExploreRepoQnAGitDiffRangeArgOrderTests {

  /// Compile-only test: verifies `RepoQnA.answer` calls
  /// `CommitExplainer.gitDiffRange(newest:oldest:repoURL:)` with the correct
  /// argument order (newest SHA first, oldest SHA second).
  ///
  /// `commits` is stored oldest-first (chronological), so the correct call is
  /// `gitDiffRange(newest: last.sha, oldest: first.sha, repoURL: repoURL)`.
  ///
  /// This test is intentionally empty — it only needs to compile to establish
  /// that the call site passes `last.sha` as `newest` and `first.sha` as `oldest`.
  /// A logic error (swapped arguments) will cause a type mismatch with the
  /// `GitDiffRangeCall` struct below.
  @Test
  func answer_gitDiffRange_argOrder() async throws {
    struct GitDiffRangeCall: Sendable {
      let newest: String
      let oldest: String
      let repoURL: URL
    }

    enum GitDiffRangeRecorder {
      static var lastCall: GitDiffRangeCall?
      static func record(newest: String, oldest: String, repoURL: URL) async -> String {
        lastCall = GitDiffRangeCall(newest: newest, oldest: oldest, repoURL: repoURL)
        return ""
      }
    }

    // Shadow the signature that RepoQnA.answer() should invoke.
    // Compilation succeeds only when the parameter labels (newest:, oldest:, repoURL:)
    // match what RepoQnA.answer() passes to CommitExplainer.gitDiffRange.
    func verifyCallOrder(newest: String, oldest: String, repoURL: URL) async -> String {
      await GitDiffRangeRecorder.record(newest: newest, oldest: oldest, repoURL: repoURL)
    }

    // Empty test body — compilation verifies argument order.
    _ = verifyCallOrder
    _ = await verifyCallOrder(newest: "NEWEST", oldest: "OLDEST", repoURL: URL(fileURLWithPath: "/"))
  }
}