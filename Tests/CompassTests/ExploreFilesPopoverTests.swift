import Foundation
import FoundationModels
import Testing

@testable import Compass

/// Tests verifying `ExploreFilesPopover.loadChanges()` guard behaviors.
///
/// Due to the Swift 6.3.2 toolchain limitation (`swift build --target CompassTests`
/// fails due to a linker error in SwiftTestingMacros), SwiftUI view instantiation
/// cannot be tested in-process. These tests exercise `FileExplainer.changes(for:)`
/// and `FileExplainer.explain()` directly under the same conditions that
/// `loadChanges()` evaluates.
///
/// ## Guard paths verified
///
/// - **Path 1 (empty commits → no changes):** `loadChanges()` calls
///   `FileExplainer.changes(for:)` at line 1504. When `item.commits` is empty,
///   `changes(for:)` returns `[]` early at line 323:
///   `guard let first = commits.first else { return [] }` — no git diff is run.
///   The popover renders the `changes.isEmpty` empty state ("No file changes found").
///
/// - **Path 3 (model unavailable):** `loadChanges()` calls
///   `FileExplainer.explain(file:repoURL:commits:)` for each loaded file (line 1528).
///   When Foundation Models is unavailable, `CommitExplainer.summarize(diff:)`
///   returns `nil` (non-throwing) → `explanation` stays `nil` for each file.
///
/// This mirrors the structure of `ExplorePerCommitNarrativesPopoverTests` (which
/// tests `CommitExplainer.explain()` empty-commits guard) and
/// `ExploreQnAPopoverTests` (which tests `RepoQnA.answer()` model-unavailable path).
@available(macOS 26.0, *)
struct ExploreFilesPopoverTests {

  // MARK: - Path 1: empty commits → FileExplainer.changes(for:) returns []

  /// Verifies `FileExplainer.changes(for:)` returns `[]` when commits is empty.
  ///
  /// `loadChanges()` calls `FileExplainer.changes(for:)` at line 1504. When
  /// `item.commits` is empty, `changes(for:)` hits the guard at line 323:
  /// `guard let first = commits.first else { return [] }` — no git diff is run.
  ///
  /// The popover would then render the `changes.isEmpty` empty state:
  /// "No file changes found in these commits."
  @Test
  func loadChanges_emptyCommits_returnsEmptyChanges() async throws {
    try #require(available(macOS 26.0, *))
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try test.initGitRepo()

    let emptyCommits: [SessionCommit] = []

    // When commits is empty, changes(for:) returns [] at the guard (line 323)
    // before any git diff is run. The popover would show the empty state.
    let result = await FileExplainer.changes(for: test.temporaryDirectory, commits: emptyCommits)

    #require(result.isEmpty)
  }

  // MARK: - Path 3: FileExplainer.explain returns nil when Foundation Models is unavailable
  //          → loadChanges() would leave explanation = nil for each file

  /// Verifies `FileExplainer.explain()` returns `nil` when Foundation Models is unavailable.
  ///
  /// `loadChanges()` calls `FileExplainer.explain(file:repoURL:commits:)` for each
  /// file at line 1528. When Foundation Models is unavailable,
  /// `CommitExplainer.summarize(diff:)` returns `nil` (non-throwing), so
  /// `explain()` propagates `nil` → `explanation` stays `nil` for each file.
  ///
  /// The chain this test exercises:
  /// `loadChanges()` → `FileExplainer.explain()` → `CommitExplainer.summarize(diff:)`
  ///                   → `nil` (model unavailable) → `explanation = nil`
  @Test
  func loadChanges_explainReturnsNil_leavesExplanationNil() async throws {
    try #require(available(macOS 26.0, *))
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try test.initGitRepo()
    let commits = try test.makeSingleCommit()

    // Call explain directly — this is what loadChanges() does at line 1528.
    // When Foundation Models is unavailable, it returns nil (non-throwing),
    // which leaves the per-file explanation nil in the loaded changes array.
    let result = await FileExplainer.explain(
      file: "Sources/App.swift",
      repoURL: test.temporaryDirectory,
      commits: commits
    )

    if !FoundationModelsAvailability.isAvailable {
      // The nil return is the expected result when the model is unavailable.
      #require(result == nil)
    }
    // If the model IS available, a non-nil string would be returned — both are valid.
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
      throw "git init failed with status \(process.terminationStatus)"
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
      throw "git command failed with status \(process.terminationStatus)"
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

  private func getSingleCommitSHA() throws -> String {
    let result = try waitForSync {
      try? ProcessRunner.runEnv(
        "git", ["rev-parse", "HEAD"],
        workingDirectory: temporaryDirectory
      )
    }
    guard let stdout = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
          !stdout.isEmpty else {
      throw "no commit SHA found"
    }
    return stdout
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
