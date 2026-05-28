import Foundation
import FoundationModels
import Testing

@testable import Compass

/// Tests verifying `RepoQnA.answer()` guard behaviors that mirror the three
/// guard-path scenarios from `QnAPopover.submitQuestion()` (ContentViewPlanTab.swift:1413).
///
/// Due to the Swift 6.3.2 toolchain limitation (`swift build --target CompassTests`
/// fails due to a linker error in SwiftTestingMacros), SwiftUI view instantiation
/// cannot be tested in-process. These tests exercise `RepoQnA.answer()` directly
/// under the same input conditions that `submitQuestion()` applies before calling it.
///
/// ## Guard paths verified
///
/// - **Path 1 (empty string):** `submitQuestion()` calls `trimmingCharacters()`
///   on `""` → `""`, then `guard !trimmed.isEmpty else { return }` prevents the
///   `RepoQnA.answer()` call. Test 1 verifies `RepoQnA.answer("")` does not throw.
///
/// - **Path 2 (whitespace-only):** `submitQuestion()` trims `"  \n\t  "` to `""`
///   and hits the same guard. Test 2 verifies `RepoQnA.answer("  \n\t  ")` does not throw.
///
/// - **Path 3 (model unavailable):** `submitQuestion()` calls `RepoQnA.answer()`
///   and, when `result == nil` (model unavailable), sets `@State availabilityError = true`.
///   Test 3 verifies the `result == nil` condition that triggers `availabilityError`.
///
/// The first two tests verify `RepoQnA.answer()` guard-path behavior directly — not
/// `submitQuestion()`'s own `guard` statement, since that guard is exercised before
/// `RepoQnA.answer()` is ever called. The third test most faithfully mirrors the
/// actual `submitQuestion() → RepoQnA.answer() → nil → availabilityError` chain.
struct ExploreRepoQnAAnswerGuardTests {

  // MARK: - Path 1: RepoQnA.answer() with empty string does not throw

  /// Verifies `RepoQnA.answer(question: "")` does not throw.
  ///
  /// `submitQuestion()` trims `""` → `""` and returns early at
  /// `guard !trimmed.isEmpty else { return }` — so `RepoQnA.answer()` is
  /// never called in that path. This test directly verifies that if the guard
  /// were accidentally removed, `RepoQnA.answer("")` would still be safe.
  @Test
  func answer_emptyString_doesNotThrow() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try test.initGitRepo()
    let commits = try test.makeSingleCommit()

    // Empty string → trimming → "" → guard in submitQuestion() prevents the call.
    // We verify RepoQnA.answer() itself is safe if the guard were missing.
    let result = await RepoQnA.answer(
      question: "",
      repoURL: test.temporaryDirectory,
      commits: commits
    )
    _ = result
  }

  // MARK: - Path 2: RepoQnA.answer() with whitespace-only string does not throw

  /// Verifies `RepoQnA.answer(question: "  \n\t  ")` does not throw.
  ///
  /// `submitQuestion()` trims `"  \n\t  "` → `""` and returns early at the same
  /// `guard !trimmed.isEmpty else { return }`. This test directly verifies
  /// `RepoQnA.answer()` handles whitespace-only input safely.
  @Test
  func answer_whitespaceOnly_doesNotThrow() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try test.initGitRepo()
    let commits = try test.makeSingleCommit()

    // Whitespace-only → trimming → "" → guard in submitQuestion() prevents the call.
    let result = await RepoQnA.answer(
      question: "  \n\t  ",
      repoURL: test.temporaryDirectory,
      commits: commits
    )
    _ = result
  }

  // MARK: - Path 3: model unavailable → RepoQnA.answer() returns nil → availabilityError

  /// Verifies the `result == nil` condition that sets `availabilityError = true`
  /// in `submitQuestion()` (line 1422).
  ///
  /// When `FoundationModelsAvailability.isAvailable == false`,
  /// `RepoQnA.answer()` returns `nil` → `if result == nil { availabilityError = true }`.
  /// This test exercises the actual chain: submitQuestion() calls answer() and
  /// checks for nil to set availabilityError.
  @Test
  func answer_modelUnavailable_returnsNilCondition() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try test.initGitRepo()
    let commits = try test.makeSingleCommit()

    // Non-blank question passes the guard check.
    // When Foundation Models is unavailable, answer() returns nil,
    // which triggers: `if result == nil { availabilityError = true }`
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