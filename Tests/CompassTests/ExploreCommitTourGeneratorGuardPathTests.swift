import Foundation
import FoundationModels
import Testing

@testable import Compass

/// Compile-only test file covering three untested `CommitTourGenerator.generateTour()`
/// guard paths that return `nil` via `guard !diff.isEmpty`.
///
/// ## Guard path covered
///
/// `generateTour()` calls `CommitExplainer.gitDiff(sha:)` or `gitDiffRange()`
/// internally. Both can return an empty string in two distinct situations:
///
/// 1. **Invalid SHA** — `git diff` on a non-existent SHA returns `""`; `generateTour`
///    hits `guard !diff.isEmpty else { return nil }` and returns `nil`.
/// 2. **Empty-tree commit** — a valid SHA with no files in the tree; `git diff` returns
///    `""` and the same guard fires.
/// exact non-throwing contract that downstream callers (e.g. `CommitTourRow.loadTour()`)
/// depend on.
///
/// This uses the same `setUp`/`tearDown`/`initGitRepo`/`makeSingleCommit` pattern
/// established in `ExploreCommitTourRowTests.swift`.
struct ExploreCommitTourGeneratorGuardPathTests {

  // MARK: - Path 1: invalid SHA → empty diff → guard !diff.isEmpty → nil

  /// Verifies `generateTour` returns `nil` when given a SHA that does not exist
  /// in the repository. The git call returns `""`, triggering `guard !diff.isEmpty`.
  @Test
  func generateTour_invalidSHA_returnsNil() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try test.initGitRepo()
    _ = try test.makeSingleCommit()

    // Use a valid-format but non-existent SHA — git returns empty string,
    // which hits: guard !diff.isEmpty else { return nil }
    let fakeSHA = "0000000000000000000000000000000000000000"
    let commits = [SessionCommit(sha: fakeSHA, short: String(fakeSHA.prefix(7)), subject: "Fake")]

    let result = await CommitTourGenerator.generateTour(
      commits: commits,
      repoURL: test.temporaryDirectory
    )
    try #require(result == nil)
  }

  // MARK: - Path 2: empty-tree commit (valid SHA but no files) → empty diff → nil

  /// Verifies `generateTour` returns `nil` for an allow-empty commit that has a
  /// valid SHA but no files in the tree. `git diff <sha>^..<sha>` returns `""`
  /// and `guard !diff.isEmpty else { return nil }` fires.
  @Test
  func generateTour_emptyTreeCommit_returnsNil() async throws {
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

    let result = await CommitTourGenerator.generateTour(
      commits: commits,
      repoURL: test.temporaryDirectory
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

  private mutating func writeFile(_ relative: String, contents: String) throws {
    let url = temporaryDirectory.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
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

  private mutating func makeSingleCommit() throws -> [SessionCommit] {
    try writeFile("Sources/App.swift", contents: "import Foundation\n")
    try runGit(
      "git -C \(temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add App.swift'"
    )
    let sha = try getSingleCommitSHA()
    return [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add App.swift")]
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
