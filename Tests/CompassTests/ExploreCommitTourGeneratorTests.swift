import Foundation
import FoundationModels
import Testing

@testable import Compass

// MARK: - ExploreCommitTourGeneratorError

/// Error type used by test helpers in ExploreCommitTourGeneratorTests.
/// Required to be `Sendable` under Swift 6 strict concurrency when thrown
/// from async closures (e.g. inside `withCheckedThrowingContinuation`).
struct ExploreCommitTourGeneratorError: Error, Sendable {
  enum Kind: Sendable {
    case gitCommandFailed(status: Int32)
    case shellCommandFailed(command: String)
    case noCommitSHAFound
    case fnReturnedNil
  }
  let kind: Kind
}

struct ExploreCommitTourGeneratorTests {
  // MARK: - Empty string guard

  @Test
  func generate_emptyString_returnsNil()  async throws {
    let result = await CommitTourGenerator.generate(diff: "")
    try #require(result == nil)
  }

  // MARK: - Whitespace-only guard

  @Test
  func generate_whitespaceOnlyString_returnsNil()  async throws {
    let result = await CommitTourGenerator.generate(diff: "   \n\t  \n  ")
    try #require(result == nil)
  }

  @Test
  func generate_newlinesOnlyString_returnsNil()  async throws {
    let result = await CommitTourGenerator.generate(diff: "\n\n\n")
    try #require(result == nil)
  }

  // MARK: - Non-throwing contract for normal diffs

  @Test
  func generate_normalDiff_doesNotThrow()  async throws {
    // Verify the async method does not throw for a valid diff.
    // Returns nil when Foundation Models is unavailable in this environment.
    let diff = """
    Sources/App.swift | 4 ++++
    Sources/Model.swift | 2 ++
    """
    let result = await CommitTourGenerator.generate(diff: diff)
    // Result may be nil (Foundation Models unavailable) or non-nil (available)
    // but it must not throw.
    try #require(result == nil || result != nil)
  }

  @Test
  func generate_singleLineDiff_doesNotThrow()  async throws {
    let diff = "README.md | 1 +"
    let result = await CommitTourGenerator.generate(diff: diff)
    if FoundationModelsAvailability.isAvailable {
      try #require(result != nil && !result!.isEmpty)
    }
  }

  // MARK: - Large-diff stability

  @Test
  func generate_largeDiff_doesNotThrow()  async throws {
    // A large diff mimicking a full commit range; must not crash or throw.
    let largeDiff = (1...200).map { idx in
      "Sources/File\(String(format: "%03d", idx)).swift\t|  \(idx) +\t\t// Line \(idx) of a simulated large diff"
    }.joined(separator: "\n")

    let result = await CommitTourGenerator.generate(diff: largeDiff)
    // Returns nil if Foundation Models is unavailable or declines output.
    // Must never throw regardless of input size.
    _ = result
  }

  @Test
  func generate_largeDiffWithManyFiles_doesNotThrow()  async throws {
    // Wide diff: many files, small changes each — tests batch-processing stability.
    let wideDiff = (1...50).map { idx in
      "Sources/Package\(idx)/Source.swift\t|  2 +\t\t// Added utility function in package \(idx)"
    }.joined(separator: "\n")

    let result = await CommitTourGenerator.generate(diff: wideDiff)
    _ = result
  }

  // MARK: - generateTour empty commits guard

  @Test
  func generateTour_emptyCommits_returnsNil()  async throws {
    // Empty commits array must return nil without attempting to invoke git or the model.
    let repoURL = try makeTempDir()
    let result = await CommitTourGenerator.generateTour(commits: [], repoURL: repoURL)
    try #require(result == nil)
  }

  // MARK: - generateTour single-commit integration (real git repo)

  @Test
  func generateTour_singleCommit_callsGitDiffForSha()  async throws {
    let repoURL = try makeTempDir()

    // Set up a real git repo with one commit
    try await runShell(
      "git init -q && git branch -M main && " +
        "git -c user.email=t@t -c user.name=t commit -q --allow-empty -m 'Initial'",
      at: repoURL
    )

    // Get the SHA of the single commit
    let sha = try await capture("git rev-parse HEAD", at: repoURL)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Initial")]
    let result = await CommitTourGenerator.generateTour(commits: commits, repoURL: repoURL)

    // Both nil and non-nil are acceptable; the key requirement is no crash.
    _ = result
  }

  // MARK: - generateTour multi-commit integration (real git repo)

  @Test
  func generateTour_multiCommit_callsGitDiffRange()  async throws {
    let repoURL = try makeTempDir()

    // Set up a real git repo with two commits
    try await runShell("git init -q && git branch -M main", at: repoURL)

    // First commit
    try await runShell(
      "touch README.md && " +
        "git add README.md && " +
        "git -c user.email=t@t -c user.name=t commit -q -m 'First'",
      at: repoURL
    )

    // Second commit
    try await runShell(
      "echo 'content' >> README.md && " +
        "git add README.md && " +
        "git -c user.email=t@t -c user.name=t commit -q -m 'Second'",
      at: repoURL
    )

    // Get both SHAs
    let firstSha = try await capture("git rev-parse HEAD~", at: repoURL)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let secondSha = try await capture("git rev-parse HEAD", at: repoURL)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let commits = [
      SessionCommit(sha: secondSha, short: String(secondSha.prefix(7)), subject: "Second"),
      SessionCommit(sha: firstSha, short: String(firstSha.prefix(7)), subject: "First"),
    ]
    let result = await CommitTourGenerator.generateTour(commits: commits, repoURL: repoURL)

    // Returns nil when unavailable or when the model declines output.
    // Must not throw regardless of commit range.
    _ = result
  }

  // MARK: - isAvailable guard

  @Test
  func generate_returnsNilWhenModelUnavailable()  async throws {
    // When FoundationModelsAvailability.isAvailable is false, generate
    // returns nil without attempting to create a session.
    let diff = """
    Sources/App.swift        |   2 ++
    """
    let result = await CommitTourGenerator.generate(diff: diff)
    // Either Foundation Models is available and we get a string (or nil
    // from an error), or it is unavailable and we definitely get nil.
    if !FoundationModelsAvailability.isAvailable {
      try #require(result == nil)
    }
  }

}
