import Foundation
import Testing

@testable import Compass

struct ExploreCommitExplainerGitDiffTests {
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

  // MARK: - gitDiff(sha:repoURL:)

  @Test
  func gitDiff_emptyStringSHA_returnsEmptyString() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    test.setUpGitRepo()
    _ = try test.commitFile("README.md", contents: "# Test\n", message: "Initial")

    let result = await CommitExplainer.gitDiff(
      sha: "",
      repoURL: test.temporaryDirectory
    )
    try #require(result == "")
  }

  @Test
  func gitDiff_invalidSHA_returnsEmptyString() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    test.setUpGitRepo()
    _ = try test.commitFile("README.md", contents: "# Test\n", message: "Initial")

    let result = await CommitExplainer.gitDiff(
      sha: "0000000000000000000000000000000000000000",
      repoURL: test.temporaryDirectory
    )
    try #require(result == "")
  }

  @Test
  func gitDiff_nonExistentRepoURL_returnsEmptyString() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    test.setUpGitRepo()
    _ = try test.commitFile("README.md", contents: "# Test\n", message: "Initial")

    let nonExistent = test.temporaryDirectory.appendingPathComponent("does-not-exist")
    try FileManager.default.removeItem(at: test.temporaryDirectory)

    let result = await CommitExplainer.gitDiff(
      sha: "0000000000000000000000000000000000000000",
      repoURL: nonExistent
    )
    try #require(result == "")
  }

  @Test
  func gitDiff_normalSingleCommit_returnsNonEmptyDiff() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    test.setUpGitRepo()
    _ = try test.commitFile("README.md", contents: "# Test\n", message: "Initial")

    // Get the commit SHA
    let sha = try getSingleCommitSHA(at: test.temporaryDirectory)

    let result = await CommitExplainer.gitDiff(
      sha: sha,
      repoURL: test.temporaryDirectory
    )
    // git diff <sha>^..<sha> on the first commit is empty (no parent)
    // so let's create a second commit with a change
    _ = try test.commitFile("README.md", contents: "# Test\nExtra line.\n", message: "Modify")

    let sha2 = try getSingleCommitSHA(at: test.temporaryDirectory)
    let result2 = await CommitExplainer.gitDiff(
      sha: sha2,
      repoURL: test.temporaryDirectory
    )
    try #require(!result2.isEmpty)
  }

  @Test
  func gitDiff_largeDiff_returnsNonEmptyDiff() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    test.setUpGitRepo()
    _ = try test.commitFile("README.md", contents: "# Test\n", message: "Initial")

    // Create a commit with many lines of changes
    let largeContents = (0..<100).map { i in "Line \(i): content" }.joined(separator: "\n")
    _ = try test.commitFile("data.txt", contents: largeContents, message: "Add large file")

    let sha = try getSingleCommitSHA(at: test.temporaryDirectory)

    let result = await CommitExplainer.gitDiff(
      sha: sha,
      repoURL: test.temporaryDirectory
    )
    try #require(!result.isEmpty)
  }

  // MARK: - gitDiffRange(newest:oldest:repoURL:)

  @Test
  func gitDiffRange_normalMultiCommitRange_returnsNonEmptyDiff() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    test.setUpGitRepo()
    _ = try test.commitFile("README.md", contents: "# Test\n", message: "Initial")

    // Get first commit SHA (oldest)
    let oldestSha = try getSingleCommitSHA(at: test.temporaryDirectory)

    // Create second commit
    _ = try test.commitFile("README.md", contents: "# Test\nLine 2.\n", message: "Add line 2")

    // Get second commit SHA (newest)
    let newestSha = try getSingleCommitSHA(at: test.temporaryDirectory)

    let result = await CommitExplainer.gitDiffRange(
      newest: newestSha,
      oldest: oldestSha,
      repoURL: test.temporaryDirectory
    )
    try #require(!result.isEmpty)
  }

  @Test
  func gitDiffRange_reversedNewestOldestOrder_stillWorks() async throws {
    // Git handles reversed range gracefully — `git diff A..B` vs `git diff B..A`
    // both produce output, just with +/- signs swapped. The method should not throw.
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    test.setUpGitRepo()
    _ = try test.commitFile("README.md", contents: "# Test\n", message: "Initial")

    let oldestSha = try getSingleCommitSHA(at: test.temporaryDirectory)

    _ = try test.commitFile("README.md", contents: "# Test\nLine 2.\n", message: "Add line 2")

    let newestSha = try getSingleCommitSHA(at: test.temporaryDirectory)

    // Pass newest as "oldest" and vice versa — git handles it without error
    let result = await CommitExplainer.gitDiffRange(
      newest: oldestSha,
      oldest: newestSha,
      repoURL: test.temporaryDirectory
    )
    // Should return some output (diff with reversed +/- signs)
    try #require(!result.isEmpty)
  }

  @Test
  func gitDiffRange_emptyStringSHAs_returnsEmptyString() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    test.setUpGitRepo()
    _ = try test.commitFile("README.md", contents: "# Test\n", message: "Initial")

    let result = await CommitExplainer.gitDiffRange(
      newest: "",
      oldest: "",
      repoURL: test.temporaryDirectory
    )
    try #require(result == "")
  }

  @Test
  func gitDiffRange_nonExistentRepoURL_returnsEmptyString() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    test.setUpGitRepo()
    _ = try test.commitFile("README.md", contents: "# Test\n", message: "Initial")

    let nonExistent = test.temporaryDirectory.appendingPathComponent("does-not-exist")
    try FileManager.default.removeItem(at: test.temporaryDirectory)

    let result = await CommitExplainer.gitDiffRange(
      newest: "0000000000000000000000000000000000000000",
      oldest: "0000000000000000000000000000000000000000",
      repoURL: nonExistent
    )
    try #require(result == "")
  }
}
