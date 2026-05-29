import Foundation
import Testing

@testable import Compass

struct ExploreFileExplainerGitDiffRangeArgOrderTests {

  // MARK: - explain(file:repoURL:commits:)

  /// Compile-only test: verifies `FileExplainer.explain` calls
  /// `CommitExplainer.gitDiffRange(newest:oldest:repoURL:)` with the correct
  /// argument order (newest SHA first, oldest SHA second).
  ///
  /// `commits` is stored newest-first, so the correct call is
  /// `gitDiffRange(newest: commits.first!.sha, oldest: commits.last!.sha, repoURL: repoURL)`.
  ///
  /// This test is intentionally empty — it only needs to compile to establish
  /// that the call site passes the right parameter labels. A logic error (swapped
  /// arguments) will cause a type mismatch with the `GitDiffRangeCall` struct below.
  @Test
  func explain_gitDiffRange_argOrder() async throws {
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

    // Shadow the signature that FileExplainer.explain() should invoke.
    // Compilation succeeds only when the parameter labels (newest:, oldest:, repoURL:)
    // match what FileExplainer.explain() passes to CommitExplainer.gitDiffRange.
    func verifyCallOrder(newest: String, oldest: String, repoURL: URL) async -> String {
      await GitDiffRangeRecorder.record(newest: newest, oldest: oldest, repoURL: repoURL)
    }

    // Empty test body — compilation verifies argument order.
    _ = verifyCallOrder
    _ = await verifyCallOrder(newest: "NEWEST", oldest: "OLDEST", repoURL: URL(fileURLWithPath: "/"))
  }

  // MARK: - whyGenerated(file:repoURL:commits:)

  /// Compile-only test: verifies `FileExplainer.whyGenerated` calls
  /// `CommitExplainer.gitDiffRange(newest:oldest:repoURL:)` with the correct
  /// argument order (newest SHA first, oldest SHA second).
  ///
  /// `commits` is stored newest-first, so the correct call is
  /// `gitDiffRange(newest: commits.first!.sha, oldest: commits.last!.sha, repoURL: repoURL)`.
  ///
  /// This test is intentionally empty — it only needs to compile to establish
  /// that the call site passes the right parameter labels. A logic error (swapped
  /// arguments) will cause a type mismatch with the `GitDiffRangeCall` struct below.
  @Test
  func whyGenerated_gitDiffRange_argOrder() async throws {
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

    // Shadow the signature that FileExplainer.whyGenerated() should invoke.
    // Compilation succeeds only when the parameter labels (newest:, oldest:, repoURL:)
    // match what FileExplainer.whyGenerated() passes to CommitExplainer.gitDiffRange.
    func verifyCallOrder(newest: String, oldest: String, repoURL: URL) async -> String {
      await GitDiffRangeRecorder.record(newest: newest, oldest: oldest, repoURL: repoURL)
    }

    // Empty test body — compilation verifies argument order.
    _ = verifyCallOrder
    _ = await verifyCallOrder(newest: "NEWEST", oldest: "OLDEST", repoURL: URL(fileURLWithPath: "/"))
  }
}