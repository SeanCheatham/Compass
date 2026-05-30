import Foundation
import FoundationModels
import Testing

@testable import Compass

struct ExploreCommitNarratorTests {

  // MARK: - narrate with mock returns a non-empty string

  @Test
  func narrate_withMockFoundationModels_returnsNonEmptyString() async throws {
    try await withMockFoundationModels(response: "Added a new helper method to process user input.")
    {
      let commit = SessionCommit(sha: "abc123", short: "abc123", subject: "Add helper method")
      let diff = """
        +func processUserInput(_ input: String) -> String {
        +    return input.trimmingCharacters(in: .whitespaces)
        +}
        """
      let result = await CommitNarrator.narrate(commit: commit, diff: diff)
      try #require(result != nil)
      try #require(!result!.isEmpty)
    }
  }

  // MARK: - narrate a real commit without crashing

  @Test
  func narrate_realCommitWithGitRepo_doesNotThrow() async throws {
    let directory = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: directory) }

    try initGitRepo(at: directory)

    try writeFile("README.md", contents: "# Test\n", at: directory)
    try runGit(
      "git -C \(directory.path) add . && "
        + "git -C \(directory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add README'",
      at: directory
    )

    let sha = try captureGit(["rev-parse", "HEAD"], at: directory)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let commit = SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add README")

    // Build a real diff for the commit
    let diff = await CommitExplainer.gitDiff(sha: sha, repoURL: directory)

    // narrate must not throw; it may return nil if Foundation Models is unavailable
    let result = await CommitNarrator.narrate(commit: commit, diff: diff)
    // Result may be nil when Foundation Models is unavailable on the test host,
    // but the call itself must not throw.
    _ = result
  }

  // MARK: - narrate returns nil gracefully when FM unavailable

  @Test
  func narrate_whenFoundationModelsUnavailable_returnsNil() async throws {
    try await withMockFoundationModels(available: false) {
      let commit = SessionCommit(sha: "abc123", short: "abc123", subject: "Add helper method")
      let diff = """
        +func foo() {}
        """
      let result = await CommitNarrator.narrate(commit: commit, diff: diff)
      try #require(result == nil)
    }
  }

  // MARK: - narrate returns nil for empty diff

  @Test
  func narrate_emptyDiff_returnsNil() async throws {
    let commit = SessionCommit(sha: "abc123", short: "abc123", subject: "Add helper method")
    let result = await CommitNarrator.narrate(commit: commit, diff: "")
    try #require(result == nil)
  }

  // MARK: - narrate returns nil for whitespace-only diff

  @Test
  func narrate_whitespaceOnlyDiff_returnsNil() async throws {
    let commit = SessionCommit(sha: "abc123", short: "abc123", subject: "Add helper method")
    let result = await CommitNarrator.narrate(commit: commit, diff: "   \n\t  ")
    try #require(result == nil)
  }
}
