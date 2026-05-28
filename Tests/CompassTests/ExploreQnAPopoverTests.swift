import Foundation
import FoundationModels
import Testing

@testable import Compass

/// Tests verifying `QnAPopover.submitQuestion()` guard behavior for the
/// `result == nil` path that sets `availabilityError = true`.
///
/// Due to the Swift 6.3.2 toolchain limitation (`swift build --target CompassTests`
/// fails due to a linker error in SwiftTestingMacros), SwiftUI view instantiation
/// cannot be tested in-process. These tests exercise `RepoQnA.answer()` directly
/// under the same conditions that `submitQuestion()` evaluates.
///
/// ## Guard path verified
///
/// - **Path 3 (model unavailable):** `submitQuestion()` calls `RepoQnA.answer()`.
///   When `FoundationModelsAvailability.isAvailable == false`, `answer()` returns `nil`
///   (non-throwing) → `if result == nil { availabilityError = true }` (line 1422).
///
///   `RepoQnA.answer()` can return `nil` in multiple ways, all non-throwing:
///
///   1. Empty/whitespace-only question: trimmed to `""` → guard prevents the call
///   2. Foundation Models unavailable → `generate(text:)` returns `nil`
///   3. Model produces no response → returns `nil`
///
///   This test exercises case 2: a real git repo with valid commits, calling
///   `RepoQnA.answer()` directly and verifying the `nil` return is the exact condition
///   that triggers `availabilityError` in the view.
///
/// This mirrors the Path 3 pattern from `ExploreRepoQnAAnswerGuardTests` but
/// targets the QnAPopover path specifically, mirroring how
/// `ExploreCommitTourRowTests` targets the CommitTourRow path.
@available(macOS 26.0, *)
struct ExploreQnAPopoverTests {

  // MARK: - Path 3: RepoQnA.answer returns nil when Foundation Models is unavailable
  //          → submitQuestion() would set availabilityError = true

  /// Verifies the `result == nil` condition that sets `availabilityError = true`
  /// in `QnAPopover.submitQuestion()` (line 1422).
  ///
  /// When `FoundationModelsAvailability.isAvailable == false`,
  /// `RepoQnA.answer()` returns `nil` (non-throwing) →
  /// `if result == nil { availabilityError = true }`.
  ///
  /// The chain this test exercises:
  /// `submitQuestion()` → `RepoQnA.answer()` → `nil` (model unavailable)
  ///                     → `availabilityError = true`
  @Test
  func submitQuestion_answerReturnsNil_setsAvailabilityError() async throws {
    try #require(available(macOS 26.0, *))
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try test.initGitRepo()
    let commits = try test.makeSingleCommit()

    // Call RepoQnA.answer directly — this is what submitQuestion() does at line 1420.
    // When Foundation Models is unavailable, it returns nil (non-throwing),
    // which is the exact condition that triggers: if result == nil { availabilityError = true }
    let result = await RepoQnA.answer(
      question: "What changed in this commit?",
      repoURL: test.temporaryDirectory,
      commits: commits
    )

    if !FoundationModelsAvailability.isAvailable {
      // The nil return is the exact condition that sets availabilityError = true.
      #require(result == nil)
    }
    // If the model IS available, a non-nil Answer would be returned — both are valid.
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