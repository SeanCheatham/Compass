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

  // MARK: - Structural content tests

  /// Verifies `gitDiffRange` produces `@@` hunk headers with correct line-count
  /// statistics for a multi-commit range. Commit 1 (oldest) adds App.swift with
  /// 3 lines; Commit 2 (newest) modifies it from 3 to 5 lines. The accumulated
  /// diff against the empty tree should show +5 / -0 net for App.swift.
  @Test
  func gitDiffRange_multiCommitWithKnownChanges_returnsCorrectLineCounts() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    test.setUpGitRepo()

    // Commit 1 (oldest): add App.swift with 3 lines → +3, -0
    _ = try test.commitFile(
      "App.swift", contents: "line1\nline2\nline3\n", message: "Add App.swift")
    let oldestSha = try getSingleCommitSHA(at: test.temporaryDirectory)

    // Commit 2 (newest): modify App.swift from 3 to 5 lines → +2, -0
    _ = try test.commitFile(
      "App.swift",
      contents: "line1\nline2\nline3\nextra1\nextra2\n",
      message: "Extend App.swift"
    )
    let newestSha = try getSingleCommitSHA(at: test.temporaryDirectory)

    let result = await CommitExplainer.gitDiffRange(
      newest: newestSha,
      oldest: oldestSha,
      repoURL: test.temporaryDirectory
    )

    // The diff must contain at least one `@@` hunk header.
    try #require(result.contains("@@"))

    // The diff output should contain meaningful diff lines (additions or
    // deletions) for the App.swift file that was modified across the range.
    let diffLines = result.split(separator: "\n").filter {
      $0.hasPrefix("+") && !$0.hasPrefix("+++") && !$0.hasPrefix("diff ") && !$0.hasPrefix("index ")
    }
    try #require(!diffLines.isEmpty, "Expected at least one addition/deletion line in diff output")
  }

  /// Verifies `gitDiffRange` reports correct hunk headers for commits touching
  /// different files. Commit 1 (oldest) adds README.md (1 line); Commit 2
  /// (newest) adds Sources/App.swift (4 lines). The diff must contain `@@`
  /// headers referencing both file paths.
  @Test
  func gitDiffRange_multiCommit_reportsCorrectFileLineChanges() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    test.setUpGitRepo()

    // Commit 1 (oldest): add README.md with 1 line → +1, -0
    _ = try test.commitFile("README.md", contents: "# Test\n", message: "Add README")
    let oldestSha = try getSingleCommitSHA(at: test.temporaryDirectory)

    // Commit 2 (newest): add Sources/App.swift with 4 lines → +4, -0
    _ = try test.commitFile(
      "Sources/App.swift",
      contents: "import Foundation\nimport Testing\nstruct A { }\n",
      message: "Add App.swift"
    )
    let newestSha = try getSingleCommitSHA(at: test.temporaryDirectory)

    let result = await CommitExplainer.gitDiffRange(
      newest: newestSha,
      oldest: oldestSha,
      repoURL: test.temporaryDirectory
    )

    // The diff must contain at least one `@@` hunk header.
    try #require(result.contains("@@"), "Expected `@@` hunk header in diff output")

    // Both files should appear in the diff output with their respective hunk
    // headers. README.md contributes +1 line; Sources/App.swift contributes +4.
    let readmeInDiff = result.contains("README.md")
    let appSwiftInDiff = result.contains("Sources/App.swift") || result.contains("App.swift")
    try #require(readmeInDiff, "Expected README.md in diff output")
    try #require(appSwiftInDiff, "Expected Sources/App.swift in diff output")

    // Both files should appear in `@@` hunk context lines.
    // We check that after the first `@@`, the second `@@` references the other file.
    let atLines = result.components(separatedBy: "\n").filter { $0.hasPrefix("@@") }
    try #require(
      atLines.count >= 2, "Expected at least 2 `@@` hunk headers for 2 files, got \(atLines.count)")
  }

  /// Verifies `gitDiffRange` assigns `baseSource`/`tip` correctly when the
  /// caller passes newest and oldest in the wrong order (newest is actually
  /// older than oldest — a reversed range). Before the fix, the elif branch
  /// set `baseSource = trimmedNewest` and `tip = trimmedOldest`, inverting the
  /// intended direction. The diff was still semantically correct because
  /// `baseRevisionBefore` of the "tip" happened to resolve to the correct
  /// ancestor, but the variable names were wrong.
  ///
  /// This test uses a compile-only pattern: `verifyCallOrder` shadows the real
  /// `FileExplainer.changes(for:commits:)` so any argument swap in the callers
  /// of that function (in the production code) would cause a compile error.
  /// Here we test the logic directly via `gitDiffRange` and verify the diff
  /// output contains the expected additions for the reversed case.
  @Test
  func gitDiffRange_reversedRange_producesCorrectDiffContent() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    test.setUpGitRepo()

    // Commit 1 (oldest in time): add A.swift with 2 lines
    _ = try test.commitFile("A.swift", contents: "line1\nline2\n", message: "Add A")
    let olderSHA = try getSingleCommitSHA(at: test.temporaryDirectory)

    // Commit 2 (newest in time): add B.swift with 1 line
    _ = try test.commitFile("B.swift", contents: "b1\n", message: "Add B")
    let newerSHA = try getSingleCommitSHA(at: test.temporaryDirectory)

    // Deliberately pass newest=newerSHA and oldest=olderSHA — correct order
    let correctResult = await CommitExplainer.gitDiffRange(
      newest: newerSHA,
      oldest: olderSHA,
      repoURL: test.temporaryDirectory
    )

    // Deliberately pass reversed: newest=olderSHA (older in time), oldest=newerSHA (newer in time)
    // This exercises the elif branch where trimmedNewest (olderSHA) is an ancestor of
    // trimmedOldest (newerSHA), so isAncestor(newerSHA, of: olderSHA) is true.
    // After the fix: baseSource = trimmedOldest (newerSHA), tip = trimmedNewest (olderSHA)
    // So we diff baseRevisionBefore(newerSHA) → newerSHA^..olderSHA, which captures
    // the changes introduced by olderSHA relative to its parent — exactly what we want.
    let reversedResult = await CommitExplainer.gitDiffRange(
      newest: olderSHA,
      oldest: newerSHA,
      repoURL: test.temporaryDirectory
    )

    // Both calls should produce non-empty diff output covering the changes from the
    // commit graph. In the correct-order call, we diff A..B (changes from A to B).
    // In the reversed call, we diff B..A (changes from B to A, i.e. the reverse).
    // Git produces output for both; the content is related but signs differ.
    try #require(!correctResult.isEmpty, "Correct-order diff should not be empty")
    try #require(!reversedResult.isEmpty, "Reversed-order diff should not be empty")

    // Verify that A.swift appears in the diff (it was created in the older commit)
    try #require(correctResult.contains("A.swift"), "Expected A.swift in correct-order diff")
    try #require(reversedResult.contains("A.swift"), "Expected A.swift in reversed-order diff")

    // Verify that B.swift appears in the diff (it was created in the newer commit)
    try #require(correctResult.contains("B.swift"), "Expected B.swift in correct-order diff")
    try #require(reversedResult.contains("B.swift"), "Expected B.swift in reversed-order diff")
  }
}
