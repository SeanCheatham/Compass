import Foundation
import XCTest

@testable import Compass

final class CodemapRefresherTests: XCTestCase {
  private var workingDirectory: URL!
  private var cacheDirectory: URL!

  override func setUpWithError() throws {
    workingDirectory = try makeTempDir()
    cacheDirectory = workingDirectory.appendingPathComponent(".compass/codemap")
  }

  override func tearDownWithError() throws {
    if let workingDirectory {
      try? FileManager.default.removeItem(at: workingDirectory)
    }
    workingDirectory = nil
    cacheDirectory = nil
  }

  func testRefreshIndexesThenSummarizes() async throws {
    try writeFile("alpha.swift", contents: swiftFixture)
    try writeFile("beta.swift", contents: swiftFixture)

    let store = CodemapStore(directory: cacheDirectory)
    let indexer = CodemapIndexer(
      workingDirectory: workingDirectory,
      store: store,
      bashRunner: SkipGitBashRunner(),
      minFileBytes: 0
    )
    let recorder = SimpleChatRecorder()
    var settings = AgentRuntimeSettings()
    settings.apiKey = "test-key"
    settings.codemapModelOverride = "tiny-model"
    let summarizer = RepoSummarizer(
      workingDirectory: workingDirectory,
      store: store,
      settings: settings,
      chatRequest: recorder.chatRequest
    )

    let refresher = CodemapRefresher(
      workingDirectory: workingDirectory,
      store: store,
      indexer: indexer,
      summarizer: summarizer,
      summariesEnabled: true
    )

    let result = try await refresher.refresh()
    XCTAssertEqual(result.indexed, 2)
    XCTAssertEqual(result.pruned, 0)
    XCTAssertEqual(result.summariesGenerated, 2)
    let calls = await recorder.callCount()
    XCTAssertEqual(calls, 2)
  }

  func testRefreshSkipsSummariesWhenDisabled() async throws {
    try writeFile("alpha.swift", contents: swiftFixture)

    let store = CodemapStore(directory: cacheDirectory)
    let indexer = CodemapIndexer(
      workingDirectory: workingDirectory,
      store: store,
      bashRunner: SkipGitBashRunner(),
      minFileBytes: 0
    )
    let recorder = SimpleChatRecorder()
    let summarizer = RepoSummarizer(
      workingDirectory: workingDirectory,
      store: store,
      settings: AgentRuntimeSettings(),
      chatRequest: recorder.chatRequest
    )

    let refresher = CodemapRefresher(
      workingDirectory: workingDirectory,
      store: store,
      indexer: indexer,
      summarizer: summarizer,
      summariesEnabled: false
    )

    let result = try await refresher.refresh()
    XCTAssertEqual(result.indexed, 1)
    XCTAssertEqual(result.summariesGenerated, 0)
    let calls = await recorder.callCount()
    XCTAssertEqual(calls, 0)
  }

  func testRefreshPrunesEntriesAfterFileRemoval() async throws {
    try writeFile("alpha.swift", contents: swiftFixture)
    try writeFile("beta.swift", contents: swiftFixture)

    let store = CodemapStore(directory: cacheDirectory)
    let recorder = SimpleChatRecorder()
    let refresher = makeHostRefresher(store: store, recorder: recorder)

    _ = try await refresher.refresh()

    try FileManager.default.removeItem(
      at: workingDirectory.appendingPathComponent("beta.swift")
    )
    let result = try await refresher.refresh()
    XCTAssertEqual(result.pruned, 1)
    XCTAssertNil(store.loadEntry(forRelativePath: "beta.swift"))
  }

  // MARK: - Helpers

  private let swiftFixture = """
    import Foundation

    class Greeter {
      func hi() -> String { "hi" }
    }

    func topLevel() {}
    """

  private func writeFile(_ relative: String, contents: String) throws {
    let url = workingDirectory.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private func makeHostRefresher(
    store: CodemapStore,
    recorder: SimpleChatRecorder
  ) -> CodemapRefresher {
    let indexer = CodemapIndexer(
      workingDirectory: workingDirectory,
      store: store,
      bashRunner: SkipGitBashRunner(),
      minFileBytes: 0
    )
    var settings = AgentRuntimeSettings()
    settings.apiKey = "test-key"
    settings.codemapModelOverride = "tiny-model"
    let summarizer = RepoSummarizer(
      workingDirectory: workingDirectory,
      store: store,
      settings: settings,
      chatRequest: recorder.chatRequest
    )
    return CodemapRefresher(
      workingDirectory: workingDirectory,
      store: store,
      indexer: indexer,
      summarizer: summarizer,
      summariesEnabled: true
    )
  }
}

private struct SkipGitBashRunner: AgentBashRunner {
  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    ProcessResult(exitCode: 127, stdout: "", stderr: "skip git")
  }
}

private actor SimpleChatRecorder {
  private var calls = 0
  func callCount() -> Int { calls }
  func record() { calls += 1 }

  nonisolated var chatRequest: RepoSummarizer.ChatRequest {
    let actor = self
    return { @Sendable _, _ in
      await actor.record()
      return "ok"
    }
  }
}
