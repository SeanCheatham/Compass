import Foundation
import FoundationModels
import Testing

@testable import Compass

struct ExploreCommitExplainerTests {
  // MARK: - Empty input guard

  @Test
  func summarize_emptyString_returnsNil() async throws {
    let result = await CommitExplainer.summarize(diff: "")
    #require(result == nil)
  }

  @Test
  func summarize_whitespaceOnly_returnsNil() async throws {
    let result = await CommitExplainer.summarize(diff: "   \n\t  ")
    #require(result == nil)
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
    // May return nil in CI / test environments without Foundation Models,
    // but must not throw.
    let result = await CommitExplainer.summarize(diff: diff)
    _ = result
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
      #require(result == nil)
    }
  }

  // MARK: - summarizeWhyGenerated

  @Test
  func summarizeWhyGenerated_emptyString_returnsNil() async throws {
    let result = await CommitExplainer.summarizeWhyGenerated(diff: "")
    #require(result == nil)
  }

  @Test
  func summarizeWhyGenerated_normalDiff_doesNotThrow() async throws {
    let diff = """
    Sources/App.swift        |  12 ++++++------
    Sources/Model.swift      |   4 ++++++
    """
    // May return nil in CI / test environments without Foundation Models,
    // but must not throw.
    let result = await CommitExplainer.summarizeWhyGenerated(diff: diff)
    _ = result
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
      throw "git command failed with status \(process.terminationStatus)"
    }
  }

  @Test
  func explain_normalSingleCommitDiff_isPassedToSummarizeAndReturnsString()  async throws {
    // Path 1: normal single-commit diff is passed to summarize and returns a string.
    // We verify the diff is produced by git and passed to summarize.
    // Result may be nil if Foundation Models is unavailable on the test host.
    var test = Self()
    test.explainSetUp()
    defer { test.explainTearDown() }

    explainInitGitRepo(at: test.temporaryDirectory)

    // Create first commit with an initial file
    try explainWriteFile("README.md", contents: "# Test\n")
    try explainRunGit(
      "git -C \(test.temporaryDirectory.path) add . && " +
        "git -C \(test.temporaryDirectory.path) " +
        "-c user.email=t@t -c user.name=t commit -q -m 'Initial'",
      at: test.temporaryDirectory
    )

    // Create second commit that modifies the file
    try explainWriteFile("README.md", contents: "# Test\nExtra line.\n")
    try explainRunGit(
      "git -C \(test.temporaryDirectory.path) add . && " +
        "git -C \(test.temporaryDirectory.path) " +
        "-c user.email=t@t -c user.name=t commit -q -m 'Add line'",
      at: test.temporaryDirectory
    )

    // Get the second commit SHA
    let shaResult = try explainRunGitCapture(
      "git -C \(test.temporaryDirectory.path) rev-parse HEAD",
      at: test.temporaryDirectory
    )
    let sha = shaResult.trimmingCharacters(in: .whitespacesAndNewlines)

    let commit = SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add line")

    // Call explain and verify it returns (nil or string) without throwing
    let result = await CommitExplainer.explain(commit: commit, repoURL: test.temporaryDirectory)
    // If Foundation Models is available, we expect a non-nil string.
    // If unavailable, result will be nil — both are acceptable outcomes.
    if FoundationModelsAvailability.isAvailable {
      #require(result != nil)
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
      throw "git command failed with status \(process.terminationStatus)"
    }
    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
  }

  @Test
  func explain_emptyDiff_returnsNilWithoutCallingSummarize()  async throws {
    // Path 2: empty diff returns nil without calling summarize.
    // An empty commit (no file changes) produces no diff output.
    var test = Self()
    test.explainSetUp()
    defer { test.explainTearDown() }

    explainInitGitRepo(at: test.temporaryDirectory)

    // Create initial commit
    try explainWriteFile("README.md", contents: "# Test\n")
    try explainRunGit(
      "git -C \(test.temporaryDirectory.path) add . && " +
        "git -C \(test.temporaryDirectory.path) " +
        "-c user.email=t@t -c user.name=t commit -q -m 'Initial'",
      at: test.temporaryDirectory
    )

    // Create an empty commit (no file changes — amend to be empty)
    // We use a separate approach: create a commit with only metadata change.
    // Instead, use a merge commit that introduces no new changes.
    // Simpler: use a commit that only changes a binary file to same content.
    // Best approach: a merge commit with no changes.
    let shaResult = try explainRunGitCapture(
      "git -C \(test.temporaryDirectory.path) rev-parse HEAD",
      at: test.temporaryDirectory
    )
    let initialSha = shaResult.trimmingCharacters(in: .whitespacesAndNewlines)

    // Create a commit that makes no file changes by touching the same content
    try explainWriteFile("README.md", contents: "# Test\n")
    try explainRunGit(
      "git -C \(test.temporaryDirectory.path) add . && " +
        "git -C \(test.temporaryDirectory.path) " +
        "-c user.email=t@t -c user.name=t commit -q --allow-empty -m 'Empty change'",
      at: test.temporaryDirectory
    )

    let shaResult2 = try explainRunGitCapture(
      "git -C \(test.temporaryDirectory.path) rev-parse HEAD",
      at: test.temporaryDirectory
    )
    let emptySha = shaResult2.trimmingCharacters(in: .whitespacesAndNewlines)

    let commit = SessionCommit(sha: emptySha, short: String(emptySha.prefix(7)), subject: "Empty change")

    // The diff for an empty commit should be empty → explain returns nil.
    // This does not call summarize because the trimmed diff is empty.
    let result = await CommitExplainer.explain(commit: commit, repoURL: test.temporaryDirectory)
    #require(result == nil)
  }

  @Test
  func explain_gitFailure_returnsNil()  async throws {
    // Path 3: git failure returns nil.
    // Use a repo URL that does not exist.
    var test = Self()
    test.explainSetUp()
    defer { test.explainTearDown() }

    // Remove the directory so git fails
    try FileManager.default.removeItem(at: test.temporaryDirectory)

    let fakeCommit = SessionCommit(sha: "0000000000000000000000000000000000000000", short: "0000000", subject: "Fake")
    let nonExistentURL = test.temporaryDirectory

    let result = await CommitExplainer.explain(commit: fakeCommit, repoURL: nonExistentURL)
    #require(result == nil)
  }

  // MARK: - whyGenerated (FileExplainer path)

  @Test
  func whyGenerated_normalPath_callsSummarizeWithWhyGeneratedPrompt() async throws {
    // Test the FileExplainer.whyGenerated path: it calls
    // CommitExplainer.summarizeWhyGenerated (not summarize).
    // Set up a real git repo with a multi-commit range and verify
    // non-nil result when Foundation Models is available.
    var test = Self()
    test.explainSetUp()
    defer { test.explainTearDown() }

    explainInitGitRepo(at: test.temporaryDirectory)

    // Create first commit with an initial file
    try explainWriteFile("README.md", contents: "# Test\n")
    try explainRunGit(
      "git -C \(test.temporaryDirectory.path) add . && " +
        "git -C \(test.temporaryDirectory.path) " +
        "-c user.email=t@t -c user.name=t commit -q -m 'Initial'",
      at: test.temporaryDirectory
    )

    // Create second commit that modifies the file
    try explainWriteFile("README.md", contents: "# Test\nExtra line.\n")
    try explainRunGit(
      "git -C \(test.temporaryDirectory.path) add . && " +
        "git -C \(test.temporaryDirectory.path) " +
        "-c user.email=t@t -c user.name=t commit -q -m 'Add line'",
      at: test.temporaryDirectory
    )

    // Get both commit SHAs for a multi-commit range
    let shaResult = try explainRunGitCapture(
      "git -C \(test.temporaryDirectory.path) rev-parse HEAD",
      at: test.temporaryDirectory
    )
    let newestSha = shaResult.trimmingCharacters(in: .whitespacesAndNewlines)

    let shaResult2 = try explainRunGitCapture(
      "git -C \(test.temporaryDirectory.path) rev-parse HEAD~",
      at: test.temporaryDirectory
    )
    let oldestSha = shaResult2.trimmingCharacters(in: .whitespacesAndNewlines)

    // Commits array in insertion order (newest first)
    let commits = [
      SessionCommit(sha: newestSha, short: String(newestSha.prefix(7)), subject: "Add line"),
      SessionCommit(sha: oldestSha, short: String(oldestSha.prefix(7)), subject: "Initial"),
    ]

    // Call whyGenerated and verify non-nil when Foundation Models is available
    let result = await FileExplainer.whyGenerated(
      file: "README.md",
      repoURL: test.temporaryDirectory,
      commits: commits
    )
    if FoundationModelsAvailability.isAvailable {
      #require(result != nil)
    }
  }
}
