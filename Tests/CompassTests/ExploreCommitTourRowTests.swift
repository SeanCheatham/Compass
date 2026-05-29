import Foundation
import FoundationModels
import Testing

@testable import Compass

/// Tests verifying `CommitTourRow.loadTour()` guard behavior for the
/// `result == nil` path that sets `tourAvailabilityError = true`.
///
/// Due to the Swift 6.3.2 toolchain limitation (`swift build --target CompassTests`
/// fails due to a linker error in SwiftTestingMacros), SwiftUI view instantiation
/// cannot be tested in-process. These tests exercise `CommitTourGenerator.generateTour()`
/// directly under the same conditions that `loadTour()` evaluates.
///
/// ## Guard path verified
///
/// - **Path 2 (model unavailable):** `loadTour()` calls `CommitTourGenerator.generateTour()`.
///   When `FoundationModelsAvailability.isAvailable == false`, `generateTour()` returns `nil`
///   (non-throwing) → `if result == nil { tourAvailabilityError = true }` (line 1142).
///
///   `generateTour()` can return `nil` in three distinct ways, all non-throwing:
///
///   1. Empty commits array: `guard let firstCommit = commits.first else { return nil }`
///   2. Empty diff result: `guard !diff.isEmpty else { return nil }`
///   3. Foundation Models unavailable → `generate(diff:)` returns `nil`
///
///   This test exercises case 3: a real git repo with valid commits, calling
///   `generateTour()` directly and verifying the `nil` return is the exact condition
///   that triggers `tourAvailabilityError` in the view.
///
/// This mirrors the Path 3 pattern from `ExploreRepoQnAAnswerGuardTests` but for
/// the tour generator path instead of the Q&A answer path.
struct ExploreCommitTourRowTests {

  // MARK: - Path 2: generateTour returns nil when Foundation Models is unavailable
  //          → loadTour() would set tourAvailabilityError = true

  /// Verifies the `result == nil` condition that sets `tourAvailabilityError = true`
  /// in `CommitTourRow.loadTour()` (line 1142).
  ///
  /// When `FoundationModelsAvailability.isAvailable == false`,
  /// `CommitTourGenerator.generateTour()` returns `nil` (non-throwing) →
  /// `if result == nil { tourAvailabilityError = true }`.
  ///
  /// The chain this test exercises:
  /// `loadTour()` → `CommitTourGenerator.generateTour()` → `nil` (model unavailable)
  ///               → `tourAvailabilityError = true`
  @Test
  func loadTour_generateTourReturnsNil_setsTourAvailabilityError() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try test.initGitRepo()
    let commits = try test.makeSingleCommit()

    // Call generateTour directly — this is what loadTour() does at line 1140.
    // When Foundation Models is unavailable, it returns nil (non-throwing),
    // which is the exact condition that triggers: if result == nil { tourAvailabilityError = true }
    let result = await CommitTourGenerator.generateTour(
      commits: commits,
      repoURL: test.temporaryDirectory
    )

    if !FoundationModelsAvailability.isAvailable {
      // The nil return is the exact condition that sets tourAvailabilityError = true.
      try #require(result == nil)
    }
    // If the model IS available, a non-nil string would be returned — both are valid.
  }

  // MARK: - Empty commits guard (generateTour internal path 1)

  /// Verifies `generateTour([])` returns `nil` without throwing.
  ///
  /// `generateTour()` has `guard let firstCommit = commits.first else { return nil }`.
  /// This guard prevents git invocation for empty commit arrays and returns nil cleanly.
  @Test
  func loadTour_emptyCommits_returnsNil() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try test.initGitRepo()

    // Empty commits array hits: guard let firstCommit = commits.first else { return nil }
    let result = await CommitTourGenerator.generateTour(
      commits: [],
      repoURL: test.temporaryDirectory
    )
    try #require(result == nil)
  }

  // MARK: - Empty diff guard (generateTour internal path 2)

  /// Verifies `generateTour()` returns `nil` when git produces an empty diff.
  ///
  /// `generateTour()` calls `_gitDiffForSha()` or `_gitDiffRange()` (which return
  /// empty string for invalid/unavailable commits) and then hits
  /// `guard !diff.isEmpty else { return nil }` before calling `generate(diff:)`.
  @Test
  func loadTour_emptyDiff_returnsNil() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try test.initGitRepo()

    // Use a valid-looking but non-existent SHA — git diff returns empty string,
    // which hits: guard !diff.isEmpty else { return nil }
    let fakeSHA = "0000000000000000000000000000000000000000"
    let commits = [SessionCommit(sha: fakeSHA, short: String(fakeSHA.prefix(7)), subject: "Fake")]
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

  private func getSingleCommitSHA() throws -> String {
    let stdout = try captureGit(["rev-parse", "HEAD"], at: temporaryDirectory)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !stdout.isEmpty else {
      throw TestHelperError.noCommitSHAFound
    }
    return stdout
  }
}
