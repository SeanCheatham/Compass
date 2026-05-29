import Foundation
import FoundationModels
import Testing

@testable import Compass

/// Compile-only test file covering the `isAvailable` guard path in
/// ``ArchitectureGraph/explain(graph:repoURL:)``.
///
/// ## Guard path covered
///
/// `ArchitectureGraph.explain(graph:repoURL:)` at line 264:
///
/// ```swift
/// guard FoundationModelsAvailability.isAvailable else { return nil }
/// ```
///
/// When Foundation Models is unavailable (e.g. on an older macOS version or
/// a simulator), the guard fires and `explain` returns `nil` without
/// attempting to contact the model. This mirrors the guard-path pattern
/// established in `ExploreCommitExplainerTests.summarize_returnsNilWhenModelUnavailable`
/// and `ExploreFileExplainerGuardPathTests.whyGenerated_returnsNilWhenModelUnavailable`.
///
/// This test uses the same `setUp`/`tearDown`/`initGitRepo`/`makeSingleCommit`
/// helper pattern established across all other Explore guard-path test files.
struct ExploreArchitectureGraphGuardPathTests {

  // MARK: - isAvailable guard

  /// Verifies `explain` returns `nil` when Foundation Models is unavailable.
  ///
  /// `ArchitectureGraph.explain(graph:repoURL:)` has a
  /// `guard FoundationModelsAvailability.isAvailable else { return nil }`
  /// guard at line 264. When the model is unavailable the guard fires and
  /// `explain` returns `nil` without throwing.
  @Test
  func explain_returnsNilWhenModelUnavailable() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try test.initGitRepo()
    _ = try test.makeSingleCommit()

    // Build a minimal non-empty ImportGraph with at least one node and edge.
    let node = ImportGraph.Node(path: "Sources/App.swift")
    let edge = ImportGraph.Edge(source: node, target: node, rawImport: "import Foundation")
    let graph = ImportGraph(nodes: [node], edges: [edge])

    let result = await ArchitectureGraph.explain(graph: graph, repoURL: test.temporaryDirectory)
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
