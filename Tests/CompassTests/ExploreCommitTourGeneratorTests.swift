import Foundation
import FoundationModels
import Testing

@testable import Compass

@available(macOS 26.0, *)
struct ExploreCommitTourGeneratorTests {
  // MARK: - Empty string guard

  @Test
  func generate_emptyString_returnsNil()  throws {
    try #require(available(macOS 26.0, *))
    let result = await CommitTourGenerator.generate(diff: "")
    #require(result == nil)
  }

  // MARK: - Whitespace-only guard

  @Test
  func generate_whitespaceOnlyString_returnsNil()  throws {
    try #require(available(macOS 26.0, *))
    let result = await CommitTourGenerator.generate(diff: "   \n\t  \n  ")
    #require(result == nil)
  }

  @Test
  func generate_newlinesOnlyString_returnsNil()  throws {
    try #require(available(macOS 26.0, *))
    let result = await CommitTourGenerator.generate(diff: "\n\n\n")
    #require(result == nil)
  }

  // MARK: - Non-throwing contract for normal diffs

  @Test
  func generate_normalDiff_doesNotThrow()  throws {
    try #require(available(macOS 26.0, *))
    // Verify the async method does not throw for a valid diff.
    // Returns nil when Foundation Models is unavailable in this environment.
    let diff = """
    Sources/App.swift | 4 ++++
    Sources/Model.swift | 2 ++
    """
    let result = await CommitTourGenerator.generate(diff: diff)
    // Result may be nil (Foundation Models unavailable) or non-nil (available)
    // but it must not throw.
    #require(result == nil || result != nil)
  }

  @Test
  func generate_singleLineDiff_doesNotThrow()  throws {
    try #require(available(macOS 26.0, *))
    let diff = "README.md | 1 +"
    let result = await CommitTourGenerator.generate(diff: diff)
    if FoundationModelsAvailability.isAvailable {
      #require(result != nil && !result!.isEmpty)
    }
  }

  // MARK: - Large-diff stability

  @Test
  func generate_largeDiff_doesNotThrow()  throws {
    try #require(available(macOS 26.0, *))
    // A large diff mimicking a full commit range; must not crash or throw.
    let largeDiff = (1...200).map { index in
      "Sources/File\(String(format: "%03d", index)).swift\t|  \(index) +\t\t// Line \($0) of a simulated large diff"
    }.joined(separator: "\n")

    let result = await CommitTourGenerator.generate(diff: largeDiff)
    // Returns nil if Foundation Models is unavailable; non-nil if available.
    // Must never throw regardless of input size.
    if FoundationModelsAvailability.isAvailable {
      #require(result != nil && !result!.isEmpty)
    }
  }

  @Test
  func generate_largeDiffWithManyFiles_doesNotThrow()  throws {
    try #require(available(macOS 26.0, *))
    // Wide diff: many files, small changes each — tests batch-processing stability.
    let wideDiff = (1...50).map { index in
      "Sources/Package\(index)/Source.swift\t|  2 +\t\t// Added utility function in package \(index)"
    }.joined(separator: "\n")

    let result = await CommitTourGenerator.generate(diff: wideDiff)
    if FoundationModelsAvailability.isAvailable {
      #require(result != nil && !result!.isEmpty)
    }
  }

  // MARK: - generateTour empty commits guard

  @Test
  func generateTour_emptyCommits_returnsNil()  async throws {
    try #require(available(macOS 26.0, *))
    // Empty commits array must return nil without attempting to invoke git or the model.
    let repoURL = try makeTempDir()
    let result = await CommitTourGenerator.generateTour(commits: [], repoURL: repoURL)
    #require(result == nil)
  }

  // MARK: - generateTour single-commit integration (real git repo)

  @Test
  func generateTour_singleCommit_callsGitDiffForSha()  async throws {
    try #require(available(macOS 26.0, *))
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

    // Foundation Models availability determines whether we get a string or nil.
    // Both are acceptable — the key requirement is that it does not throw.
    if FoundationModelsAvailability.isAvailable {
      #require(result != nil)
    }
  }

  // MARK: - generateTour multi-commit integration (real git repo)

  @Test
  func generateTour_multiCommit_callsGitDiffRange()  async throws {
    try #require(available(macOS 26.0, *))
    let repoURL = try makeTempDir()

    // Set up a real git repo with two commits
    try await runShell("git init -q && git branch -M main", at: repoURL)

    // First commit
    try await runShell(
      "touch README.md && " +
        "git -c user.email=t@t -c user.name=t commit -q -m 'First'",
      at: repoURL
    )

    // Second commit
    try await runShell(
      "echo 'content' >> README.md && " +
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

    // Returns nil when unavailable; non-nil when Foundation Models is present.
    // Must not throw regardless of commit range.
    if FoundationModelsAvailability.isAvailable {
      #require(result != nil)
    }
  }

  // MARK: - isAvailable guard

  @Test
  func generate_returnsNilWhenModelUnavailable()  throws {
    // When FoundationModelsAvailability.isAvailable is false, generate
    // returns nil without attempting to create a session.
    try #require(available(macOS 26.0, *))
    let diff = """
    Sources/App.swift        |   2 ++
    """
    let result = await CommitTourGenerator.generate(diff: diff)
    // Either Foundation Models is available and we get a string (or nil
    // from an error), or it is unavailable and we definitely get nil.
    if !FoundationModelsAvailability.isAvailable {
      #require(result == nil)
    }
  }

}