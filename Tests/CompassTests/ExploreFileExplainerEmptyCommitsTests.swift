import Foundation
import FoundationModels
import Testing

@testable import Compass

/// Compile-only test file covering the `FileExplainer.explain()` guard path when
/// `gitDiff` returns an empty string for an empty-tree commit.
///
/// ## Guard path covered
///
/// `explain(file:repoURL:commits:)` calls `CommitExplainer.gitDiff(sha:)` internally.
/// When given a valid SHA that has no files in the tree (empty-tree commit),
/// `git diff <sha>^..<sha>` returns `""`. This triggers the guard at
/// `if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }`
/// and `explain()` returns `nil` — without throwing.
///
/// This mirrors the guard-path pattern established in
/// `ExploreCommitTourGeneratorGuardPathTests.swift`.
///
/// ## Why this matters
///
/// `explain()` is called by Explore popover code when the user requests an
/// AI explanation for a changed file. The `nil` return is the expected
/// non-throwing contract that callers handle gracefully. An empty-tree
/// commit can legitimately occur when the user browses a commit that added
/// no files (e.g., a metadata-only commit, a merge commit with no conflicts,
/// or a forced-empty commit during rebase).
///
/// This uses the same `setUp`/`tearDown`/`initGitRepo`/`makeSingleCommit` pattern
/// established in `ExploreCommitTourGeneratorGuardPathTests.swift`.
struct ExploreFileExplainerEmptyCommitsTests {

  // MARK: - Empty-tree commit → gitDiff returns "" → guard returns nil

  /// Verifies `explain()` returns `nil` when given a valid SHA whose tree
  /// contains no files. `git diff <sha>^..<sha>` returns `""` (nothing to diff),
  /// triggering `if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }`.
  ///
  /// The chain exercised:
  /// `explain(file:"Sources/App.swift", repoURL, commits=[sha])` →
  /// `CommitExplainer.gitDiff(sha: sha, repoURL:)` returns `""` (empty-tree) →
  /// `guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` →
  /// `nil`
  @Test
  func explain_emptyTreeCommit_returnsNil() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try test.initGitRepo()

    // Create an allow-empty commit (no files staged/changed)
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q --allow-empty -m 'Empty commit'"
    )

    let sha = try test.getSingleCommitSHA()
    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Empty commit")]

    // Even though the file path is valid, the commit has no files — git diff
    // returns "" and explain() returns nil via the guard check.
    let result = await FileExplainer.explain(
      file: "Sources/App.swift",
      repoURL: test.temporaryDirectory,
      commits: commits
    )
    try #require(result == nil)
  }

  // MARK: - Helpers

  private var temporaryDirectory: URL!

  private mutating func setUp() {
    temporaryDirectory = try! makeTempDir()
  }

  private mutating func tearDown() {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    temporaryDirectory = nil
  }

  private mutating func initGitRepo() throws {
    let process = Process()
    process.launchPath = "/bin/zsh"
    process.arguments = ["-lc", "git init -q && git branch -M main"]
    process.currentDirectoryURL = temporaryDirectory
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw TestHelperError.gitCommandFailed(status: process.terminationStatus)
    }
  }

  private mutating func runGit(_ command: String) throws {
    let process = Process()
    process.launchPath = "/bin/zsh"
    process.arguments = ["-lc", command]
    process.currentDirectoryURL = temporaryDirectory
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw TestHelperError.gitCommandFailed(status: process.terminationStatus)
    }
  }

  private mutating func getSingleCommitSHA() throws -> String {
    let process = Process()
    process.launchPath = "/usr/bin/git"
    process.arguments = ["rev-parse", "HEAD"]
    process.currentDirectoryURL = temporaryDirectory
    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw TestHelperError.gitCommandFailed(status: process.terminationStatus)
    }
    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let stdout = String(data: data, encoding: .utf8) ?? ""
    let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw TestHelperError.noCommitSHAFound
    }
    return trimmed
  }
}