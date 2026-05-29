import Foundation
import FoundationModels
import Testing

@testable import Compass

/// Compile-only test file covering two guard paths in `CommitExplainer` that
/// return `nil` without throwing.
///
/// ## Guard paths covered
///
/// ### Path 1 — `gitDiff(sha:)` on malformed SHA
///
/// `CommitExplainer.gitDiff(sha:repoURL:)` uses `try?` on `ProcessRunner.runEnv`.
/// When git receives a malformed SHA it exits non-zero, `try?` produces `nil`,
/// and the method returns `""`. Callers that receive `""` and trim it to empty
/// hit `guard !trimmed.isEmpty` and return `nil` without throwing.
///
/// ### Path 2 — `explain(commit:)` when git returns empty diff on a valid commit
///
/// `CommitExplainer.explain(commit:repoURL:)` fetches the diff then trims and
/// guards on `!trimmed.isEmpty`. This path is triggered when the commit SHA is
/// valid but the diff is empty — e.g., a file that was added in a later commit
/// does not exist in the queried commit, so `git diff <sha>^..<sha>` returns `""`.
///
/// This uses the same `setUp`/`tearDown`/`initGitRepo`/`makeSingleCommit` pattern
/// established in `ExploreCommitTourGeneratorGuardPathTests.swift`.
struct ExploreCommitExplainerGuardPathTests {

  // MARK: - Path 1: gitDiff — malformed SHA → try? returns nil → ""

  /// Verifies `gitDiff` returns `""` when given a SHA that git cannot parse.
  /// A malformed SHA causes `git diff` to fail; `try?` returns `nil`, and
  /// the method returns `""` (the `?? ""` fallback). Callers then hit their
  /// own `guard !trimmed.isEmpty else { return nil }` and return `nil`.
  @Test
  func gitDiff_malformedSHA_returnsEmptyString() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try test.initGitRepo()
    _ = try test.makeSingleCommit()

    // A SHA with an embedded newline is not valid for git — git exits non-zero
    // and `try?` returns nil. The method falls back to `""`.
    let malformedSHA = "abc123\ndef456"
    let result = await CommitExplainer.gitDiff(
      sha: malformedSHA,
      repoURL: test.temporaryDirectory
    )
    // The malformed SHA causes git to fail; try? returns nil, result is ""
    try #require(result == "")
  }

  // MARK: - Path 2: explain — valid SHA but file absent from that commit → empty diff → nil

  /// Verifies `explain(commit:repoURL:)` returns `nil` when the commit SHA is
  /// valid but the file being queried has no content in that commit.
  ///
  /// The test creates two commits: the first adds `Sources/App.swift`, the
  /// second adds `Sources/Other.swift`. Querying the first commit for
  /// `Sources/Other.swift` produces an empty diff (the file did not exist yet),
  /// which hits `guard !trimmed.isEmpty else { return nil }`.
  ///
  /// The chain exercised:
  /// `explain(commit: [first_sha], repoURL)` →
  /// `CommitExplainer.gitDiff(sha:)` returns `""` (file not in commit) →
  /// `guard !trimmed.isEmpty else { return nil }` →
  /// `nil`
  @Test
  func explain_commitValidButFileAbsentInCommit_returnsNil() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try test.initGitRepo()
    _ = try test.makeSingleCommit()

    // Create a second commit that adds a different file
    try test.writeFile("Sources/Other.swift", contents: "import Foundation\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/Other.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add Other.swift'"
    )

    // Get the SHA of the first commit (which only has Sources/App.swift)
    let firstSHA = try test.getSingleCommitSHA()
    let firstCommit = SessionCommit(
      sha: firstSHA,
      short: String(firstSHA.prefix(7)),
      subject: "Add App.swift"
    )

    // Query the first commit using the path from the second commit
    // — "Sources/Other.swift" did not exist in the first commit, so
    // git returns "" and explain returns nil.
    let result = await CommitExplainer.explain(
      commit: firstCommit,
      repoURL: test.temporaryDirectory
    )
    try #require(result == nil)
  }

  // MARK: - Path 2b: explain — malformed SHA → empty diff → nil

  /// Verifies `explain(commit:repoURL:)` returns `nil` when given a malformed
  /// SHA. `gitDiff` returns `""` (try? failure), trimming produces empty string,
  /// and the guard fires.
  @Test
  func explain_malformedSHA_returnsNil() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try test.initGitRepo()
    _ = try test.makeSingleCommit()

    let malformedCommit = SessionCommit(
      sha: "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",
      short: "zzzzzzz",
      subject: "Malformed"
    )
    let result = await CommitExplainer.explain(
      commit: malformedCommit,
      repoURL: test.temporaryDirectory
    )
    // Malformed SHA causes gitDiff to return "", trim gives "", guard fires → nil
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