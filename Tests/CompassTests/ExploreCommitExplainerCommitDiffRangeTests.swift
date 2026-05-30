import Foundation
import Testing

@testable import Compass

struct ExploreCommitExplainerCommitDiffRangeTests {
  private var temporaryDirectory: URL!

  // MARK: - Setup / Teardown

  private mutating func setUp() {
    temporaryDirectory = try! makeTempDir()
  }

  private mutating func tearDown() {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    temporaryDirectory = nil
  }

  private mutating func setUpGitRepo() {
    try! initGitRepo(at: temporaryDirectory)
  }

  /// Creates a file, stages it, and commits. Returns the commit SHA.
  private mutating func commitFile(
    _ relative: String,
    contents: String,
    message: String
  ) throws -> String {
    try writeFile(relative, contents: contents, at: temporaryDirectory)
    try runGit(
      "git -C \(temporaryDirectory.path) add . && "
        + "git -C \(temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m '\(message)'",
      at: temporaryDirectory
    )
    return try getSingleCommitSHA(at: temporaryDirectory)
  }

  // MARK: - commitDiffRange(commits:repoURL:)

  /// Test 1: empty commits → nil
  ///
  /// Verifies `commitDiffRange(commits: [], repoURL:)` returns `nil` when the
  /// commits array is empty. Sets up a real temp git repo (required by the API
  /// signature) but does not call git for this path.
  @Test
  func commitDiffRange_emptyCommits_returnsNil() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    test.setUpGitRepo()
    _ = try test.commitFile("README.md", contents: "# Test\n", message: "Initial")

    let result = await CommitExplainer.commitDiffRange(
      commits: [],
      repoURL: test.temporaryDirectory
    )
    try #require(result == nil)
  }

  /// Test 2: single commit → delegates to `gitDiff`
  ///
  /// Creates a two-commit repo. Passes only the newest (second) commit in a
  /// single-element `[SessionCommit]`. Because a prior commit modified the
  /// tracked file, `git diff <sha>^..<sha>` on the newest produces non-empty
  /// output. This confirms `commitDiffRange` forwards to `gitDiff(sha:)` for
  /// single-commit calls.
  @Test
  func commitDiffRange_singleCommit_returnsNonEmptyDiff() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    test.setUpGitRepo()
    _ = try test.commitFile("README.md", contents: "# Test\n", message: "Initial")
    _ = try test.commitFile("README.md", contents: "# Test\nExtra line.\n", message: "Modify")

    let sha = try getSingleCommitSHA(at: test.temporaryDirectory)
    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Modify")]

    let result = await CommitExplainer.commitDiffRange(
      commits: commits,
      repoURL: test.temporaryDirectory
    )

    // The single-commit path delegates to `gitDiff(sha:repoURL:)`, which
    // runs `git diff <sha>^..<sha>`. Because the prior commit changed the
    // file, the diff is non-empty.
    try #require(result != nil)
    try #require(!result!.isEmpty)
  }

  /// Test 3: multi-commit → delegates to `gitDiffRange`
  ///
  /// Creates a two-commit repo with known file changes. Passes both commits
  /// (newest first) and verifies the result is non-empty and contains `@@`
  /// hunk headers from the accumulated diff range. This confirms
  /// `commitDiffRange` forwards to `gitDiffRange(newest:oldest:)` for
  /// multi-commit ranges.
  @Test
  func commitDiffRange_multiCommit_returnsNonEmptyDiffWithHunkHeaders() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    test.setUpGitRepo()

    // Oldest commit: add App.swift with 3 lines
    _ = try test.commitFile(
      "App.swift",
      contents: "line1\nline2\nline3\n",
      message: "Add App.swift"
    )
    let oldestSha = try getSingleCommitSHA(at: test.temporaryDirectory)

    // Newest commit: modify App.swift from 3 to 5 lines
    _ = try test.commitFile(
      "App.swift",
      contents: "line1\nline2\nline3\nextra1\nextra2\n",
      message: "Extend App.swift"
    )
    let newestSha = try getSingleCommitSHA(at: test.temporaryDirectory)

    let commits = [
      SessionCommit(
        sha: newestSha, short: String(newestSha.prefix(7)), subject: "Extend App.swift"),
      SessionCommit(sha: oldestSha, short: String(oldestSha.prefix(7)), subject: "Add App.swift"),
    ]

    let result = await CommitExplainer.commitDiffRange(
      commits: commits,
      repoURL: test.temporaryDirectory
    )

    // The multi-commit path delegates to `gitDiffRange(newest:oldest:repoURL:)`.
    // The accumulated diff must be non-empty and contain `@@` hunk headers.
    try #require(result != nil)
    try #require(!result!.isEmpty)
    try #require(result!.contains("@@"), "Expected `@@` hunk header in accumulated diff range")
  }
}
