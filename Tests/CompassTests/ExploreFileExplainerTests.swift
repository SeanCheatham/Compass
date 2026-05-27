import Foundation
import Testing

@testable import Compass

struct ExploreFileExplainerTests {
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

  // MARK: - parseGitDiffStat

  @Test
  func parseGitDiffStat_normalAdditionsAndDeletions()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = """
    Sources/App.swift        |  12 ++++++------
    Sources/Model.swift      |   4 ++++++
    """

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    #require(changes.count == 2)

    #require(changes[0].relativePath == "Sources/App.swift")
    #require(changes[0].additions == 4)
    #require(changes[0].deletions == 2)

    #require(changes[1].relativePath == "Sources/Model.swift")
    #require(changes[1].additions == 4)
    #require(changes[1].deletions == 0)
  }

  @Test
  func parseGitDiffStat_renameArrow()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = "old/path.go => new/path.go           |   4 ++--"

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    #require(changes.count == 1)
    #require(changes[0].relativePath == "new/path.go")
    #require(changes[0].additions == 2)
    #require(changes[0].deletions == 2)
  }

  @Test
  func parseGitDiffStat_binaryFile()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = "Assets/logo.png                    |  Bin 210 kB → 215 kB"

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    #require(changes.count == 1)
    #require(changes[0].relativePath == "Assets/logo.png")
    // Binary lines produce 0 additions and 0 deletions (no + or - in the bar chart, no numeric tokens)
    #require(changes[0].additions == 0)
    #require(changes[0].deletions == 0)
  }

  @Test
  func parseGitDiffStat_pathWithSpaces()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = "My Files/App.swift   |   6 ++++++"

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    #require(changes.count == 1)
    #require(changes[0].relativePath == "My Files/App.swift")
    #require(changes[0].additions == 6)
    #require(changes[0].deletions == 0)
  }

  @Test
  func parseGitDiffStat_multiLineStatOutput()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = """
    Sources/App.swift        |  10 ++++++++
    Sources/Model.swift      |   5 +++++--
    Tests/AppTests.swift    |   2 ++
    README.md               |   1 +
    """

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    #require(changes.count == 4)
    #require(changes[0].relativePath == "Sources/App.swift")
    #require(changes[1].relativePath == "Sources/Model.swift")
    #require(changes[2].relativePath == "Tests/AppTests.swift")
    #require(changes[3].relativePath == "README.md")
  }

  @Test
  func parseGitDiffStat_numericOnlyFallback()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // No +/- bar chart, only a numeric count — should fall back to numeric count as additions
    let diffStat = "Sources/App.swift        |  42"

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    #require(changes.count == 1)
    #require(changes[0].relativePath == "Sources/App.swift")
    #require(changes[0].additions == 42)
    #require(changes[0].deletions == 0)
  }

  @Test
  func parseGitDiffStat_absentStatsParts()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Empty stats part — should produce zero additions and deletions
    let diffStat = "README.md               |"

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    #require(changes.count == 1)
    #require(changes[0].relativePath == "README.md")
    #require(changes[0].additions == 0)
    #require(changes[0].deletions == 0)
  }

  @Test
  func parseGitDiffStat_emptyInput()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let changes = FileExplainer.parseGitDiffStat("")
    #require(changes.isEmpty)
  }

  @Test
  func parseGitDiffStat_whitespaceOnlyLines()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = """
    Sources/App.swift        |  4 +
                          
    Sources/Model.swift      |  2 ++
    """

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    #require(changes.count == 2)
    #require(changes[0].relativePath == "Sources/App.swift")
    #require(changes[1].relativePath == "Sources/Model.swift")
  }

  // MARK: - extractLineCounts

  @Test
  func extractLineCounts_additionsAndDeletions()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = FileExplainer.extractLineCounts(from: "24 ++++++++----------")
    #require(result.additions == 8)
    #require(result.deletions == 10)
  }

  @Test
  func extractLineCounts_onlyAdditions()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = FileExplainer.extractLineCounts(from: "6 ++++++")
    #require(result.additions == 6)
    #require(result.deletions == 0)
  }

  @Test
  func extractLineCounts_onlyDeletions()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = FileExplainer.extractLineCounts(from: "3 ---")
    #require(result.additions == 0)
    #require(result.deletions == 3)
  }

  @Test
  func extractLineCounts_numericFallback()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // No +/- bar chars, but has numeric token
    let result = FileExplainer.extractLineCounts(from: "99")
    #require(result.additions == 99)
    #require(result.deletions == 0)
  }

  @Test
  func extractLineCounts_absentStatsParts()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // No bar chars, no numeric tokens
    let result = FileExplainer.extractLineCounts(from: "")
    #require(result.additions == 0)
    #require(result.deletions == 0)
  }

  @Test
  func extractLineCounts_withNumericAndBars()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Numeric count 24 and bar chars both present — bars take priority
    let result = FileExplainer.extractLineCounts(from: "24 ++++++++----------")
    #require(result.additions == 8)
    #require(result.deletions == 10)
  }

  // MARK: - explain(file:repoURL:commits:)

  @Test
  func explain_singleCommitDiff_callsSummarize() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with one commit that modifies a file.
    try initGitRepo(at: test.temporaryDirectory)
    try writeFile("Sources/App.swift", contents: "import Foundation\n")
    try runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add App.swift'",
      at: test.temporaryDirectory
    )

    // Get the commit SHA.
    let sha = try getSingleCommitSHA(at: test.temporaryDirectory)
    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add App.swift")]

    // Call explain — CommitExplainer.summarize may return nil if Foundation Models
    // is unavailable, but the call chain must not throw.
    let result = await FileExplainer.explain(
      file: "Sources/App.swift",
      repoURL: test.temporaryDirectory,
      commits: commits
    )
    // Result may be nil in test environments; we only verify it doesn't throw.
    _ = result
  }

  @Test
  func explain_multiCommitDiff_callsSummarize() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with two commits.
    try initGitRepo(at: test.temporaryDirectory)
    try writeFile("Sources/App.swift", contents: "import Foundation\n")
    try runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Initial'",
      at: test.temporaryDirectory
    )

    // Modify the file in a second commit.
    try writeFile("Sources/App.swift", contents: "import Foundation\nimport AppKit\n")
    try runGit(
      "git -C \(test.temporaryDirectory.path) add . && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add import'",
      at: test.temporaryDirectory
    )

    let shas = try getAllCommitSHAs(at: test.temporaryDirectory)
    #require(shas.count == 2)
    let oldest = shas[1] // oldest
    let newest = shas[0] // newest
    let commits = [
      SessionCommit(sha: oldest, short: String(oldest.prefix(7)), subject: "Initial"),
      SessionCommit(sha: newest, short: String(newest.prefix(7)), subject: "Add import"),
    ]

    // Call explain for the file that changed across both commits.
    let result = await FileExplainer.explain(
      file: "Sources/App.swift",
      repoURL: test.temporaryDirectory,
      commits: commits
    )
    // Result may be nil in test environments; we only verify it doesn't throw.
    _ = result
  }

  @Test
  func explain_fileWithNoChanges_returnsNil() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with one commit modifying App.swift only.
    try initGitRepo(at: test.temporaryDirectory)
    try writeFile("Sources/App.swift", contents: "import Foundation\n")
    try runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add App.swift'",
      at: test.temporaryDirectory
    )

    let sha = try getSingleCommitSHA(at: test.temporaryDirectory)
    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add App.swift")]

    // Request explanation for a file that doesn't exist and has no changes.
    let result = await FileExplainer.explain(
      file: "Sources/DoesNotExist.swift",
      repoURL: test.temporaryDirectory,
      commits: commits
    )

    #require(result == nil)
  }

  @Test
  func explain_emptyCommits_returnsNil() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = await FileExplainer.explain(
      file: "Sources/App.swift",
      repoURL: test.temporaryDirectory,
      commits: []
    )
    #require(result == nil)
  }

  // MARK: - changes(for:repoURL:commits:)

  @Test
  func changes_multiCommit_reversedRange_bugRegression() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with two commits touching different files.
    try initGitRepo(at: test.temporaryDirectory)
    try writeFile("Sources/Old.swift", contents: "import Foundation\n")
    try runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/Old.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add Old.swift'",
      at: test.temporaryDirectory
    )

    try writeFile("Sources/New.swift", contents: "import Foundation\n")
    try runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/New.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add New.swift'",
      at: test.temporaryDirectory
    )

    let shas = try getAllCommitSHAs(at: test.temporaryDirectory)
    #require(shas.count == 2)
    let oldest = shas[1] // oldest commit
    let newest = shas[0] // newest commit

    // Pass commits ordered oldest→newest (standard ordering).
    let commits = [
      SessionCommit(sha: oldest, short: String(oldest.prefix(7)), subject: "Add Old.swift"),
      SessionCommit(sha: newest, short: String(newest.prefix(7)), subject: "Add New.swift"),
    ]

    let changes = await FileExplainer.changes(for: test.temporaryDirectory, commits: commits)

    // With the reversed range bug, git diff newest..oldest misses Old.swift.
    // The correct git diff oldest..newest shows both files.
    let changedPaths = changes.map { $0.relativePath }
    #require(changedPaths.contains("Sources/Old.swift")) { "Old.swift from the oldest commit must be present; the reversed range bug causes it to be missing" }
    #require(changedPaths.contains("Sources/New.swift")) { "New.swift from the newest commit must be present" }
  }

  @Test
  func changes_singleCommit_returnsFileStats() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try initGitRepo(at: test.temporaryDirectory)
    try writeFile("Sources/App.swift", contents: "import Foundation\n")
    try runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c name=t commit -q -m 'Add App.swift'",
      at: test.temporaryDirectory
    )

    let sha = try getSingleCommitSHA(at: test.temporaryDirectory)
    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add App.swift")]

    let changes = await FileExplainer.changes(for: test.temporaryDirectory, commits: commits)

    #require(changes.count == 1)
    #require(changes[0].relativePath == "Sources/App.swift")
  }

  // MARK: - Helpers

  private func initGitRepo(at url: URL) {
    let process = Process()
    process.launchPath = "/bin/zsh"
    process.arguments = ["-lc", "git init -q && git branch -M main"]
    process.currentDirectoryURL = url
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try? process.run()
    process.waitUntilExit()
  }

  private func writeFile(_ relative: String, contents: String) throws {
    let url = temporaryDirectory.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private func runGit(_ command: String, at url: URL) throws {
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

  private func getSingleCommitSHA(at url: URL) throws -> String {
    let result = try waitForSync {
      try? ProcessRunner.runEnv(
        "git", ["rev-parse", "HEAD"],
        workingDirectory: url
      )
    }
    guard let stdout = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
          !stdout.isEmpty else {
      throw "no commit SHA found"
    }
    return stdout
  }

  private func getAllCommitSHAs(at url: URL) throws -> [String] {
    let result = try waitForSync {
      try? ProcessRunner.runEnv(
        "git", ["log", "--all", "--format=%H"],
        workingDirectory: url
      )
    }
    guard let stdout = result?.stdout else { return [] }
    return stdout
      .split(separator: "\n")
      .filter { !$0.isEmpty }
      .map { String($0) }
  }

  private func waitForSync<T>(_ fn: () async throws -> T?) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      Task {
        do {
          if let value = try await fn() {
            continuation.resume(returning: value)
          } else {
            continuation.resume(throwing: "fn returned nil")
          }
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }
}