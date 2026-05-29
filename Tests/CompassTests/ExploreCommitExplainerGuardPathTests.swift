import Foundation
import FoundationModels
import Testing

@testable import Compass

/// Compile-only test file covering two guard paths in `CommitExplainer` that
/// return `nil` without throwing.
///
/// ## Guard paths covered
///
/// ### Path 1 — `gitDiff(sha:)` on malformed SHA
///
/// `CommitExplainer.gitDiff(sha:repoURL:)` uses `try?` on `ProcessRunner.runEnv`.
/// When git receives a malformed SHA it exits non-zero, `try?` produces `nil`,
/// and the method returns `""`. Callers that receive `""` and trim it to empty
/// hit `guard !trimmed.isEmpty` and return `nil` without throwing.
///
/// ### Path 2 — `explain(commit:)` when git returns empty diff on a valid commit
///
/// An allow-empty commit produces an empty diff; trimming hits
/// `guard !trimmed.isEmpty` and returns `nil` without throwing.
///
/// This uses the same helper pattern established in
/// `ExploreCommitTourGeneratorGuardPathTests.swift`.
struct ExploreCommitExplainerGuardPathTests {

  // MARK: - Path 1: gitDiff — malformed SHA → try? returns nil → ""

  /// Verifies `gitDiff` returns `""` when given a SHA that git cannot parse.
  /// A malformed SHA causes `git diff` to fail; `try?` returns `nil`, and
  /// the method returns `""` (the `?? ""` fallback). Callers then hit their
  /// own `guard !trimmed.isEmpty else { return nil }` and return `nil`.
  @Test
  func gitDiff_malformedSHA_returnsEmptyString() async throws {
    let temporaryDirectory = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    try CompassTests.initGitRepo(at: temporaryDirectory)
    _ = try CompassTests.makeSingleCommit(at: temporaryDirectory)

    // A SHA with an embedded newline is not valid for git — git exits non-zero
    // and `try?` returns nil. The method falls back to `""`.
    let malformedSHA = "abc123\ndef456"
    let result = await CommitExplainer.gitDiff(
      sha: malformedSHA,
      repoURL: temporaryDirectory
    )
    // The malformed SHA causes git to fail; try? returns nil, result is ""
    try #require(result == "")
  }

  // MARK: - Path 2: explain — empty-tree commit → empty diff → nil

  /// Verifies `explain(commit:repoURL:)` returns `nil` for an allow-empty
  /// commit. `git diff <sha>^..<sha>` returns `""`, trimming produces an
  /// empty string, and the guard fires.
  @Test
  func explain_emptyTreeCommit_returnsNil() async throws {
    let temporaryDirectory = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    try CompassTests.initGitRepo(at: temporaryDirectory)
    try CompassTests.runGit(
      "git -C \(temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q --allow-empty -m 'Empty commit'",
      at: temporaryDirectory
    )

    let sha = try CompassTests.getSingleCommitSHA(at: temporaryDirectory)
    let commit = SessionCommit(
      sha: sha,
      short: String(sha.prefix(7)),
      subject: "Empty commit"
    )

    let result = await CommitExplainer.explain(
      commit: commit,
      repoURL: temporaryDirectory
    )
    try #require(result == nil)
  }

  // MARK: - Path 2b: explain — malformed SHA → empty diff → nil

  /// Verifies `explain(commit:repoURL:)` returns `nil` when given a malformed
  /// SHA. `gitDiff` returns `""` (try? failure), trimming produces empty string,
  /// and the guard fires.
  @Test
  func explain_malformedSHA_returnsNil() async throws {
    let temporaryDirectory = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    try CompassTests.initGitRepo(at: temporaryDirectory)
    _ = try CompassTests.makeSingleCommit(at: temporaryDirectory)

    let malformedCommit = SessionCommit(
      sha: "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",
      short: "zzzzzzz",
      subject: "Malformed"
    )
    let result = await CommitExplainer.explain(
      commit: malformedCommit,
      repoURL: temporaryDirectory
    )
    // Malformed SHA causes gitDiff to return "", trim gives "", guard fires → nil
    try #require(result == nil)
  }
}
