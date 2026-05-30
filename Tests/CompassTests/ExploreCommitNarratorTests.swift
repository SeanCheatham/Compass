import Foundation
import FoundationModels
import Testing

@testable import Compass

struct ExploreCommitNarratorTests {
  private var temporaryDirectory: URL!

  // MARK: - Setup helpers

  private mutating func narratorSetUp() {
    temporaryDirectory = try! makeTempDir()
  }

  private mutating func narratorTearDown() {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    temporaryDirectory = nil
  }

  private func narratorInitGitRepo(at url: URL) {
    let process = Process()
    process.launchPath = "/bin/zsh"
    process.arguments = ["-lc", "git init -q && git branch -M main"]
    process.currentDirectoryURL = url
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try? process.run()
    process.waitUntilExit()
  }

  private func narratorWriteFile(_ relative: String, contents: String) throws {
    let url = temporaryDirectory.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private func narratorRunGit(_ command: String, at url: URL) throws {
    let process = Process()
    process.launchPath = "/bin/zsh"
    process.arguments = ["-lc", command]
    process.currentDirectoryURL = url
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw TestHelperError.gitCommandFailed(status: process.terminationStatus)
    }
  }

  private func narratorCapture(_ command: String, at url: URL) throws -> String {
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
      throw TestHelperError.gitCommandFailed(status: process.terminationStatus)
    }
    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
  }

  // MARK: - narrate with mock returns a non-empty string

  @Test
  func narrate_withMockFoundationModels_returnsNonEmptyString() async throws {
    try await withMockFoundationModels(response: "Added a new helper method to process user input.") {
      let commit = SessionCommit(sha: "abc123", short: "abc123", subject: "Add helper method")
      let diff = """
        +func processUserInput(_ input: String) -> String {
        +    return input.trimmingCharacters(in: .whitespaces)
        +}
        """
      let result = await CommitNarrator.narrate(commit: commit, diff: diff)
      try #require(result != nil)
      try #require(!result!.isEmpty)
    }
  }

  // MARK: - narrate a real commit without crashing

  @Test
  func narrate_realCommitWithGitRepo_doesNotThrow() async throws {
    var test = Self()
    test.narratorSetUp()
    defer { test.narratorTearDown() }

    test.narratorInitGitRepo(at: test.temporaryDirectory)

    try test.narratorWriteFile("README.md", contents: "# Test\n")
    try test.narratorRunGit(
      "git -C \(test.temporaryDirectory.path) add . && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add README'",
      at: test.temporaryDirectory
    )

    let shaResult = try test.narratorCapture(
      "git -C \(test.temporaryDirectory.path) rev-parse HEAD",
      at: test.temporaryDirectory
    )
    let sha = shaResult.trimmingCharacters(in: .whitespacesAndNewlines)
    let commit = SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add README")

    // Build a real diff for the commit
    let diff = await CommitExplainer.gitDiff(sha: sha, repoURL: test.temporaryDirectory)

    // narrate must not throw; it may return nil if Foundation Models is unavailable
    let result = await CommitNarrator.narrate(commit: commit, diff: diff)
    // Result may be nil when Foundation Models is unavailable on the test host,
    // but the call itself must not throw.
    _ = result
  }

  // MARK: - narrate returns nil gracefully when FM unavailable

  @Test
  func narrate_whenFoundationModelsUnavailable_returnsNil() async throws {
    try await withMockFoundationModels(available: false) {
      let commit = SessionCommit(sha: "abc123", short: "abc123", subject: "Add helper method")
      let diff = """
        +func foo() {}
        """
      let result = await CommitNarrator.narrate(commit: commit, diff: diff)
      try #require(result == nil)
    }
  }

  // MARK: - narrate returns nil for empty diff

  @Test
  func narrate_emptyDiff_returnsNil() async throws {
    let commit = SessionCommit(sha: "abc123", short: "abc123", subject: "Add helper method")
    let result = await CommitNarrator.narrate(commit: commit, diff: "")
    try #require(result == nil)
  }

  // MARK: - narrate returns nil for whitespace-only diff

  @Test
  func narrate_whitespaceOnlyDiff_returnsNil() async throws {
    let commit = SessionCommit(sha: "abc123", short: "abc123", subject: "Add helper method")
    let result = await CommitNarrator.narrate(commit: commit, diff: "   \n\t  ")
    try #require(result == nil)
  }
}
