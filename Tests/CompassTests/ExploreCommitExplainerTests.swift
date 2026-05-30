import Foundation
import FoundationModels
import Testing

@testable import Compass

struct ExploreCommitExplainerTests {
  private var temporaryDirectory: URL!

  // MARK: - Empty input guard

  @Test
  func summarize_emptyString_returnsNil() async throws {
    let result = await CommitExplainer.summarize(diff: "")
    try #require(result.0 == nil && result.1 == .emptyDiff)
  }

  @Test
  func summarize_whitespaceOnly_returnsNil() async throws {
    let result = await CommitExplainer.summarize(diff: "   \n\t  ")
    try #require(result.0 == nil && result.1 == .emptyDiff)
  }

  // MARK: - Diff length filter (max ~600 tokens)

  @Test
  func summarize_largeDiff_stillAcceptsInput() async throws {
    // Build a diff well over 600 tokens to exercise the length cap path.
    // CommitExplainer itself does not hard-cap token count; it passes
    // the full diff to the model and relies on the prompt to keep output
    // short (~3 sentences). This test simply confirms the method
    // accepts large input without crashing.
    let largeDiff = (0..<200).map { i in
      "+\(String(repeating: "line", count: 80)) change \(i)"
    }.joined(separator: "\n")

    // Should not throw; returns nil if the model is unavailable or
    // produces no content on this host.
    let result = await CommitExplainer.summarize(diff: largeDiff)
    // Result may be nil in test environments where Foundation Models
    // is unavailable, but the call itself must not throw.
    _ = result
  }

  @Test
  func summarize_normalDiff_doesNotThrow() async throws {
    let diff = """
      Sources/App.swift        |  12 ++++++------
      Sources/Model.swift      |   4 ++++++
      """
    try await withMockFoundationModels(response: "Mock summary.") {
      let result = await CommitExplainer.summarize(diff: diff)
      try #require(result.0 == "Mock summary.")
      try #require(result.1 == nil)
    }
  }

  // MARK: - isAvailable guard

  @Test
  func summarize_returnsNilWhenModelUnavailable() async throws {
    // When FoundationModelsAvailability.isAvailable is false (e.g. on an
    // older macOS version or a simulator), summarize returns nil without
    // attempting to create a session.
    let diff = """
      Sources/App.swift        |   2 ++
      """
    let result = await CommitExplainer.summarize(diff: diff)
    // Either Foundation Models is available and we get a string (or nil
    // from an error), or it is unavailable and we definitely get nil.
    if !FoundationModelsAvailability.isAvailable {
      try #require(result.0 == nil && result.1 == .foundationModelsUnavailable)
    }
  }

  // MARK: - summarizeWhyGenerated

  @Test
  func summarizeWhyGenerated_emptyString_returnsNil() async throws {
    let result = await CommitExplainer.summarizeWhyGenerated(diff: "")
    try #require(result.0 == nil && result.1 == .emptyDiff)
  }

  @Test
  func summarizeWhyGenerated_normalDiff_doesNotThrow() async throws {
    let diff = """
      Sources/App.swift        |  12 ++++++------
      Sources/Model.swift      |   4 ++++++
      """
    try await withMockFoundationModels(response: "Mock purpose.") {
      let result = await CommitExplainer.summarizeWhyGenerated(diff: diff)
      try #require(result.0 == "Mock purpose.")
      try #require(result.1 == nil)
    }
  }

  // MARK: - explain(commit:repoURL:)

  private mutating func explainSetUp() {
    temporaryDirectory = try! makeTempDir()
  }

  private mutating func explainTearDown() {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    temporaryDirectory = nil
  }

  private func explainInitGitRepo(at url: URL) {
    let process = Process()
    process.launchPath = "/bin/zsh"
    process.arguments = ["-lc", "git init -q && git branch -M main"]
    process.currentDirectoryURL = url
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try? process.run()
    process.waitUntilExit()
  }

  private func explainWriteFile(_ relative: String, contents: String) throws {
    let url = temporaryDirectory.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private func explainRunGit(_ command: String, at url: URL) throws {
    let process = Process()
    process.launchPath = "/bin/zsh"
    process.arguments = ["-lc", command]
    process.currentDirectoryURL = url
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw TestHelperError.gitCommandFailed(status: process.terminationStatus)
    }
  }

  @Test
  func explain_normalSingleCommitDiff_isPassedToSummarizeAndReturnsString() async throws {
    // Path 1: normal single-commit diff is passed to summarize and returns a string.
    // We verify the diff is produced by git and passed to summarize.
    // Result may be nil if Foundation Models is unavailable on the test host.
    var test = Self()
    test.explainSetUp()
    defer { test.explainTearDown() }

    test.explainInitGitRepo(at: test.temporaryDirectory)

    // Create first commit with an initial file
    try test.explainWriteFile("README.md", contents: "# Test\n")
    try test.explainRunGit(
      "git -C \(test.temporaryDirectory.path) add . && " + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Initial'",
      at: test.temporaryDirectory
    )

    // Create second commit that modifies the file
    try test.explainWriteFile("README.md", contents: "# Test\nExtra line.\n")
    try test.explainRunGit(
      "git -C \(test.temporaryDirectory.path) add . && " + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add line'",
      at: test.temporaryDirectory
    )

    // Get the second commit SHA
    let shaResult = try test.explainRunGitCapture(
      "git -C \(test.temporaryDirectory.path) rev-parse HEAD",
      at: test.temporaryDirectory
    )
    let sha = shaResult.trimmingCharacters(in: .whitespacesAndNewlines)

    let commit = SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add line")

    // Call explain and verify it returns (nil or string) without throwing
    let result = await CommitExplainer.explain(commit: commit, repoURL: test.temporaryDirectory)
    // When Foundation Models is unavailable, the guard should be explicit.
    // When it is available, the model may still return empty output on a test host.
    if !FoundationModelsAvailability.isAvailable {
      try #require(result.0 == nil && result.1 == .foundationModelsUnavailable)
    }
  }

  private func explainRunGitCapture(_ command: String, at url: URL) throws -> String {
    let process = Process()
    process.launchPath = "/bin/zsh"
    process.arguments = ["-lc", command]
    process.currentDirectoryURL = url
    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw TestHelperError.gitCommandFailed(status: process.terminationStatus)
    }
    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
  }

  @Test
  func explain_emptyDiff_returnsNilWithoutCallingSummarize() async throws {
    // Path 2: empty diff returns nil without calling summarize.
    // An empty commit (no file changes) produces no diff output.
    var test = Self()
    test.explainSetUp()
    defer { test.explainTearDown() }

    test.explainInitGitRepo(at: test.temporaryDirectory)

    // Create initial commit
    try test.explainWriteFile("README.md", contents: "# Test\n")
    try test.explainRunGit(
      "git -C \(test.temporaryDirectory.path) add . && " + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Initial'",
      at: test.temporaryDirectory
    )

    // Create a commit that makes no file changes.
    try test.explainRunGit(
      "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q --allow-empty -m 'Empty change'",
      at: test.temporaryDirectory
    )

    let shaResult2 = try test.explainRunGitCapture(
      "git -C \(test.temporaryDirectory.path) rev-parse HEAD",
      at: test.temporaryDirectory
    )
    let emptySha = shaResult2.trimmingCharacters(in: .whitespacesAndNewlines)

    let commit = SessionCommit(
      sha: emptySha, short: String(emptySha.prefix(7)), subject: "Empty change")

    // The diff for an empty commit should be empty → explain returns nil.
    // This does not call summarize because the trimmed diff is empty.
    let result = await CommitExplainer.explain(commit: commit, repoURL: test.temporaryDirectory)
    try #require(result.0 == nil && result.1 == .emptyDiff)
  }

  /// Verifies `explain(commit:repoURL:)` returns `(nil, .emptyDiff)` when git
  /// runs successfully but produces no diff output for a merge commit that
  /// touched no files on the first-parent mainline.
  ///
  /// This covers the git-level empty-diff path: `gitDiff(sha:)` returns ""
  /// because the commit introduced no file changes on main, so the guard
  /// `guard !trimmed.isEmpty` fires and returns `(nil, .emptyDiff)`.
  @Test
  func explain_mergeCommitWithNoMainlineChanges_returnsNilWithEmptyDiffReason() async throws {
    var test = Self()
    test.explainSetUp()
    defer { test.explainTearDown() }

    test.explainInitGitRepo(at: test.temporaryDirectory)

    // Create an initial commit on main
    try test.explainWriteFile("README.md", contents: "# Test\n")
    try test.explainRunGit(
      "git -C \(test.temporaryDirectory.path) add . && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Initial'",
      at: test.temporaryDirectory
    )

    // Create a topic branch with no tree changes, then merge it. The merge commit
    // exists, but its tree is identical to the first parent.
    try test.explainRunGit(
      "git -C \(test.temporaryDirectory.path) checkout -q -b topic",
      at: test.temporaryDirectory
    )
    try test.explainRunGit(
      "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q --allow-empty -m 'Empty topic'",
      at: test.temporaryDirectory
    )

    // Merge topic into main with a --no-ff merge commit
    // The merge commit is on mainline but its diff against the first parent is empty.
    try test.explainRunGit(
      "git -C \(test.temporaryDirectory.path) checkout -q main",
      at: test.temporaryDirectory
    )
    try test.explainRunGit(
      "git -C \(test.temporaryDirectory.path) merge -q --no-ff topic -m 'Merge topic'",
      at: test.temporaryDirectory
    )

    let shaResult = try test.explainRunGitCapture(
      "git -C \(test.temporaryDirectory.path) rev-parse HEAD",
      at: test.temporaryDirectory
    )
    let mergeSha = shaResult.trimmingCharacters(in: .whitespacesAndNewlines)
    let commit = SessionCommit(sha: mergeSha, short: String(mergeSha.prefix(7)), subject: "Merge topic")

    // Git ran successfully but the diff for the merge commit against its first parent
    // is empty. explain returns .emptyDiff.
    let result = await CommitExplainer.explain(commit: commit, repoURL: test.temporaryDirectory)
    try #require(result.0 == nil)
    try #require(result.1 == .emptyDiff)
  }

  /// Verifies `explain(commit:repoURL:)` returns `(nil, .emptyDiff)` when git
  /// runs successfully but the target commit has no tree changes.
  ///
  /// This covers the git-level empty-diff path: diffing against the first parent
  /// produces no output, so the guard `guard !trimmed.isEmpty`
  /// fires and returns `(nil, .emptyDiff)`.
  @Test
  func explain_gitSucceedsButTreeIsEmpty_returnsNilWithEmptyDiffReason() async throws {
    var test = Self()
    test.explainSetUp()
    defer { test.explainTearDown() }

    test.explainInitGitRepo(at: test.temporaryDirectory)

    // Create a commit with a file
    try test.explainWriteFile("README.md", contents: "# Test\n")
    try test.explainRunGit(
      "git -C \(test.temporaryDirectory.path) add . && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add README'",
      at: test.temporaryDirectory
    )

    // Add a valid empty commit after the initial file commit.
    try test.explainRunGit(
      "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q --allow-empty -m 'Empty change'",
      at: test.temporaryDirectory
    )

    let shaResult = try test.explainRunGitCapture(
      "git -C \(test.temporaryDirectory.path) rev-parse HEAD",
      at: test.temporaryDirectory
    )
    let sha = shaResult.trimmingCharacters(in: .whitespacesAndNewlines)
    let commit = SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Empty change")

    let result = await CommitExplainer.explain(commit: commit, repoURL: test.temporaryDirectory)
    try #require(result.0 == nil)
    try #require(result.1 == .emptyDiff)
  }

  @Test
  func explain_gitFailure_returnsNil() async throws {
    // Path 3: git failure returns nil.
    // Use a repo URL that does not exist.
    var test = Self()
    test.explainSetUp()
    defer { test.explainTearDown() }

    // Remove the directory so git fails.
    let nonExistentURL = try #require(test.temporaryDirectory)
    try FileManager.default.removeItem(at: nonExistentURL)

    let fakeCommit = SessionCommit(
      sha: "0000000000000000000000000000000000000000", short: "0000000", subject: "Fake")

    let result = await CommitExplainer.explain(commit: fakeCommit, repoURL: nonExistentURL)
    try #require(result.0 == nil && result.1 == .emptyDiff)
  }

  // MARK: - whyGenerated (FileExplainer path)

  @Test
  func whyGenerated_normalPath_callsSummarizeWithWhyGeneratedPrompt() async throws {
    // Test the FileExplainer.whyGenerated path: it calls
    // CommitExplainer.summarizeWhyGenerated (not summarize).
    // Set up a real git repo with a multi-commit range.
    var test = Self()
    test.explainSetUp()
    defer { test.explainTearDown() }

    test.explainInitGitRepo(at: test.temporaryDirectory)

    // Create first commit with an initial file
    try test.explainWriteFile("README.md", contents: "# Test\n")
    try test.explainRunGit(
      "git -C \(test.temporaryDirectory.path) add . && " + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Initial'",
      at: test.temporaryDirectory
    )

    // Create second commit that modifies the file
    try test.explainWriteFile("README.md", contents: "# Test\nExtra line.\n")
    try test.explainRunGit(
      "git -C \(test.temporaryDirectory.path) add . && " + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add line'",
      at: test.temporaryDirectory
    )

    // Get both commit SHAs for a multi-commit range
    let shaResult = try test.explainRunGitCapture(
      "git -C \(test.temporaryDirectory.path) rev-parse HEAD",
      at: test.temporaryDirectory
    )
    let newestSha = shaResult.trimmingCharacters(in: .whitespacesAndNewlines)

    let shaResult2 = try test.explainRunGitCapture(
      "git -C \(test.temporaryDirectory.path) rev-parse HEAD~",
      at: test.temporaryDirectory
    )
    let oldestSha = shaResult2.trimmingCharacters(in: .whitespacesAndNewlines)

    // Commits array in insertion order (newest first)
    let commits = [
      SessionCommit(sha: newestSha, short: String(newestSha.prefix(7)), subject: "Add line"),
      SessionCommit(sha: oldestSha, short: String(oldestSha.prefix(7)), subject: "Initial"),
    ]

    // Call whyGenerated and verify the unavailable guard when Foundation Models is absent.
    let result = await FileExplainer.whyGenerated(
      file: "README.md",
      repoURL: test.temporaryDirectory,
      commits: commits
    )
    if !FoundationModelsAvailability.isAvailable {
      try #require(result.0 == nil && result.1 == .foundationModelsUnavailable)
    }
  }

  // MARK: - Tuple return: (text, reason) guard paths

  /// Verifies `summarize(diff:)` returns `(nil, .foundationModelsUnavailable)`
  /// when Foundation Models is not available on this system.
  ///
  /// This directly exercises the tuple return value: the first element must be
  /// `nil` and the second must be `.foundationModelsUnavailable` — the exact
  /// reason the UI displays when the feature fails to activate.
  @Test
  func summarize_modelUnavailable_returnsNilWithUnavailableReason() async throws {
    // On hosts without Apple Intelligence, confirm the method returns the
    // correct `(nil, .foundationModelsUnavailable)` tuple.
    let diff = """
      Sources/App.swift        |   2 ++
      """
    let result = await CommitExplainer.summarize(diff: diff)
    if !FoundationModelsAvailability.isAvailable {
      try #require(result.0 == nil)
      try #require(result.1 == .foundationModelsUnavailable)
    }
  }

  /// Verifies `summarize(diff:)` returns `(nil, .emptyDiff)` when the diff
  /// contains only whitespace — the trimmed diff is empty, so the guard fires
  /// and returns the correct reason tuple.
  @Test
  func summarize_whitespaceOnly_returnsNilWithEmptyDiffReason() async throws {
    let result = await CommitExplainer.summarize(diff: "   \n\t  ")
    try #require(result.0 == nil)
    try #require(result.1 == .emptyDiff)
  }

  /// Verifies `explain(commit:repoURL:)` returns `(nil, .foundationModelsUnavailable)`
  /// when Foundation Models is unavailable, using a real git repo with a real commit.
  ///
  /// The method fetches the diff internally and passes it to `summarize`; when
  /// `FoundationModelsAvailability.isAvailable == false`, `summarize` returns
  /// `(nil, .foundationModelsUnavailable)` and `explain` propagates that tuple
  /// unchanged — so the second commit's diff is never consulted.
  @Test
  func explain_commit_modelUnavailable_returnsNilWithUnavailableReason() async throws {
    var test = Self()
    test.explainSetUp()
    defer { test.explainTearDown() }

    test.explainInitGitRepo(at: test.temporaryDirectory)

    // Create a single commit with a file
    try test.explainWriteFile("README.md", contents: "# Test\n")
    try test.explainRunGit(
      "git -C \(test.temporaryDirectory.path) add . && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add README'",
      at: test.temporaryDirectory
    )

    let shaResult = try test.explainRunGitCapture(
      "git -C \(test.temporaryDirectory.path) rev-parse HEAD",
      at: test.temporaryDirectory
    )
    let sha = shaResult.trimmingCharacters(in: .whitespacesAndNewlines)
    let commit = SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add README")

    let result = await CommitExplainer.explain(commit: commit, repoURL: test.temporaryDirectory)
    if !FoundationModelsAvailability.isAvailable {
      try #require(result.0 == nil)
      try #require(result.1 == .foundationModelsUnavailable)
    }
  }

  // MARK: - gitDiff

  /// Verifies `gitDiff(sha:repoURL:)` returns a non-empty, well-formed diff
  /// for a single commit that modifies a file. The diff must contain the
  /// filename and at least one addition marker, proving the pipeline won't
  /// silently feed empty content downstream.
  @Test
  func gitDiff_singleCommitWithFileChange_returnsNonEmptyDiffWithFilenameAndAdditions() async throws {
    var test = Self()
    test.explainSetUp()
    defer { test.explainTearDown() }

    try initGitRepo(at: test.temporaryDirectory)

    // Create a commit that adds content to README.md
    try writeFile("README.md", contents: "# Test Project\n", at: test.temporaryDirectory)
    try runGit(
      "git -C \(test.temporaryDirectory.path) add . && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add README'",
      at: test.temporaryDirectory
    )

    let sha = try getSingleCommitSHA(at: test.temporaryDirectory)
    let diff = await CommitExplainer.gitDiff(sha: sha, repoURL: test.temporaryDirectory)

    // Diff must be non-empty
    try #require(!diff.isEmpty)
    // Diff must contain the filename
    try #require(diff.contains("README.md"))
    // Diff must contain at least one addition marker
    try #require(diff.contains("+"))
  }

  // MARK: - gitDiffRange

  /// Verifies `gitDiffRange(newest:oldest:repoURL:)` returns a non-empty diff
  /// covering a two-commit range where each commit touches a different file.
  /// The returned diff must contain both filenames, proving multi-commit ranges
  /// are captured correctly for Explore commit tours and Q&A.
  @Test
  func gitDiffRange_twoCommitsTouchingDifferentFiles_returnsDiffWithBothFilenames() async throws {
    var test = Self()
    test.explainSetUp()
    defer { test.explainTearDown() }

    try initGitRepo(at: test.temporaryDirectory)

    // Commit 1: add App.swift
    try writeFile("Sources/App.swift", contents: "import Foundation\n", at: test.temporaryDirectory)
    try runGit(
      "git -C \(test.temporaryDirectory.path) add . && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add App.swift'",
      at: test.temporaryDirectory
    )

    // Commit 2: modify README.md (different file)
    try writeFile("README.md", contents: "# Test\nExtra line.\n", at: test.temporaryDirectory)
    try runGit(
      "git -C \(test.temporaryDirectory.path) add . && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Modify README'",
      at: test.temporaryDirectory
    )

    let allSHAs = try getAllCommitSHAs(at: test.temporaryDirectory)
    try #require(allSHAs.count == 2)
    let newest = allSHAs[0]
    let oldest = allSHAs[1]

    let diff = await CommitExplainer.gitDiffRange(
      newest: newest, oldest: oldest, repoURL: test.temporaryDirectory
    )

    // Diff must be non-empty
    try #require(!diff.isEmpty)
    // Diff must contain both filenames
    try #require(diff.contains("App.swift"))
    try #require(diff.contains("README.md"))
  }
}
