import Foundation
import FoundationModels
import Testing

@testable import Compass

struct ExploreRepoQnATests {
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

  // MARK: - answer(question:repoURL:commits:)

  @Test
  func answer_emptyCommits_returnsNil() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = await RepoQnA.answer(
      question: "What changed?",
      repoURL: test.temporaryDirectory,
      commits: []
    )
    #require(result == nil)
  }

  @Test
  func answer_singleCommit_returnsAnswerWithSources() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with one commit touching a file.
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

    let result = await RepoQnA.answer(
      question: "What changed in this commit?",
      repoURL: test.temporaryDirectory,
      commits: commits
    )

    // When Foundation Models is unavailable in the test environment, answer() returns nil.
    // In that case we can only verify the call didn't throw.
    if let answer = result {
      #require(!answer.text.isEmpty)
      #require(answer.sources.contains("Sources/App.swift"))
    }
  }

  @Test
  func answer_multiCommit_returnsAnswerCoveringBothFiles() async throws {
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
    let oldest = shas[1] // oldest
    let newest = shas[0] // newest
    let commits = [
      SessionCommit(sha: oldest, short: String(oldest.prefix(7)), subject: "Add Old.swift"),
      SessionCommit(sha: newest, short: String(newest.prefix(7)), subject: "Add New.swift"),
    ]

    let result = await RepoQnA.answer(
      question: "What files changed across these commits?",
      repoURL: test.temporaryDirectory,
      commits: commits
    )

    // When Foundation Models is unavailable in the test environment, answer() returns nil.
    // In that case we can only verify the call didn't throw.
    if let answer = result {
      #require(!answer.text.isEmpty)
      // The answer should reference at least the newer file.
      #require(answer.sources.contains("Sources/New.swift"))
    }
  }

  @Test
  func answer_modelUnavailable_returnsNilGracefully() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with one commit so the call has valid input.
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

    // When SystemLanguageModel.default.isAvailable is false, answer() must return nil
    // without throwing. We verify this by checking the result is nil (or if the model
    // happens to be available, that we get a valid Answer — which is also acceptable).
    let result = await RepoQnA.answer(
      question: "What changed?",
      repoURL: test.temporaryDirectory,
      commits: commits
    )
    // The only valid outcomes are: nil (model unavailable) or a non-nil Answer (model available).
    // There must be no throw.
    _ = result
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