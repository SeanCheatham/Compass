import Foundation
import XCTest

@testable import Compass

final class RepoSummarizerTests: XCTestCase {
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

  func testSummarizesEachEntryWithMissingSummary() async throws {
    let store = CodemapStore(directory: cacheDirectory)
    try await primeFile("alpha.swift", contents: swiftFixture)
    try await primeFile("beta.swift", contents: swiftFixture)

    let indexer = makeIndexer(store: store)
    _ = try await indexer.indexAll()

    let recorder = ChatRecorder()
    let summarizer = makeSummarizer(store: store, recorder: recorder)
    let result = await summarizer.summarizeMissing()

    XCTAssertEqual(result.generated, 2)
    XCTAssertEqual(result.failed, 0)
    let calls = await recorder.callCount()
    XCTAssertEqual(calls, 2)

    let alpha = try XCTUnwrap(store.loadEntry(forRelativePath: "alpha.swift"))
    XCTAssertEqual(alpha.summary, "mocked-summary")
    XCTAssertEqual(alpha.summaryContentHash, alpha.contentHash)
    XCTAssertEqual(alpha.summaryModel, "test-summary-model")
  }

  func testCachedSummaryIsLeftAloneWhenContentUnchanged() async throws {
    let store = CodemapStore(directory: cacheDirectory)
    try await primeFile("alpha.swift", contents: swiftFixture)

    let indexer = makeIndexer(store: store)
    _ = try await indexer.indexAll()

    let recorder = ChatRecorder()
    let summarizer = makeSummarizer(store: store, recorder: recorder)
    _ = await summarizer.summarizeMissing()
    let firstPass = await recorder.callCount()
    XCTAssertEqual(firstPass, 1)

    // Re-run: same hash, same model → no new call.
    _ = await summarizer.summarizeMissing()
    let secondPass = await recorder.callCount()
    XCTAssertEqual(secondPass, 1)
  }

  func testChangedContentInvalidatesSummary() async throws {
    let store = CodemapStore(directory: cacheDirectory)
    try await primeFile("alpha.swift", contents: swiftFixture)

    let indexer = makeIndexer(store: store)
    _ = try await indexer.indexAll()

    let recorder = ChatRecorder()
    let summarizer = makeSummarizer(store: store, recorder: recorder)
    _ = await summarizer.summarizeMissing()

    try await primeFile("alpha.swift", contents: swiftFixture + "\nfunc more() {}\n")
    _ = try await indexer.indexAll()  // re-parse, clears summary

    let entryAfterReparse = try XCTUnwrap(
      store.loadEntry(forRelativePath: "alpha.swift")
    )
    XCTAssertNil(entryAfterReparse.summary)

    _ = await summarizer.summarizeMissing()
    let calls = await recorder.callCount()
    XCTAssertEqual(calls, 2)
  }

  func testSkipsFilesWithNoExtractedSymbols() async throws {
    let store = CodemapStore(directory: cacheDirectory)
    // Long enough to clear minFileBytes but no recognized symbols (just
    // comments). The extractor returns empty symbols, so the summarizer
    // skips the entry.
    let commentsOnly = String(
      repeating: "// just a comment line\n", count: 80
    )
    try await primeFile("comments.swift", contents: commentsOnly)
    let indexer = makeIndexer(store: store)
    _ = try await indexer.indexAll()

    let recorder = ChatRecorder()
    let summarizer = makeSummarizer(store: store, recorder: recorder)
    let result = await summarizer.summarizeMissing()
    XCTAssertEqual(result.generated, 0)
    let calls = await recorder.callCount()
    XCTAssertEqual(calls, 0)
  }

  func testMissingAPIKeyShortCircuits() async throws {
    let store = CodemapStore(directory: cacheDirectory)
    try await primeFile("alpha.swift", contents: swiftFixture)
    let indexer = makeIndexer(store: store)
    _ = try await indexer.indexAll()

    let recorder = ChatRecorder()
    var settings = AgentRuntimeSettings()
    settings.apiKey = ""  // explicit
    settings.codemapModelOverride = "test-summary-model"
    let summarizer = RepoSummarizer(
      workingDirectory: workingDirectory,
      store: store,
      settings: settings,
      maxInFlight: 2,
      chatRequest: recorder.chatRequest
    )
    let result = await summarizer.summarizeMissing()
    XCTAssertEqual(result.failed, 1)
    let calls = await recorder.callCount()
    XCTAssertEqual(calls, 0)
  }

  func testRespectsParallelismCap() async throws {
    let store = CodemapStore(directory: cacheDirectory)
    let fileCount = 6
    for i in 0..<fileCount {
      try await primeFile("file\(i).swift", contents: swiftFixture)
    }
    let indexer = makeIndexer(store: store)
    _ = try await indexer.indexAll()

    let recorder = ChatRecorder(callDelay: 0.05)
    let summarizer = makeSummarizer(store: store, recorder: recorder, maxInFlight: 2)
    _ = await summarizer.summarizeMissing()

    let peak = await recorder.peakConcurrency()
    XCTAssertLessThanOrEqual(peak, 2)
    let calls = await recorder.callCount()
    XCTAssertEqual(calls, fileCount)
  }

  func testEnsureSummaryReturnsCachedWhenFresh() async throws {
    let store = CodemapStore(directory: cacheDirectory)
    try await primeFile("alpha.swift", contents: swiftFixture)
    let indexer = makeIndexer(store: store)
    _ = try await indexer.indexAll()

    let recorder = ChatRecorder()
    let summarizer = makeSummarizer(store: store, recorder: recorder)
    let first = try await summarizer.ensureSummary(forRelativePath: "alpha.swift")
    XCTAssertEqual(first, "mocked-summary")
    let firstCalls = await recorder.callCount()
    XCTAssertEqual(firstCalls, 1)

    let second = try await summarizer.ensureSummary(forRelativePath: "alpha.swift")
    XCTAssertEqual(second, "mocked-summary")
    let secondCalls = await recorder.callCount()
    XCTAssertEqual(secondCalls, 1)
  }

  // MARK: - Helpers

  private let swiftFixture = """
    import Foundation

    class Greeter {
      func hi() -> String { "hi" }
    }

    func topLevel() {}
    """

  private func primeFile(_ relative: String, contents: String) async throws {
    let url = workingDirectory.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private func makeIndexer(store: CodemapStore) -> CodemapIndexer {
    CodemapIndexer(
      workingDirectory: workingDirectory,
      store: store,
      filesystem: AgentHostFilesystem(),
      bashRunner: FailingBashRunner(),
      minFileBytes: 0,
      parallelism: 4
    )
  }

  private func makeSummarizer(
    store: CodemapStore,
    recorder: ChatRecorder,
    maxInFlight: Int = 4
  ) -> RepoSummarizer {
    var settings = AgentRuntimeSettings()
    settings.apiKey = "test-key"
    settings.codemapModelOverride = "test-summary-model"
    return RepoSummarizer(
      workingDirectory: workingDirectory,
      store: store,
      settings: settings,
      maxInFlight: maxInFlight,
      chatRequest: recorder.chatRequest
    )
  }
}

private struct FailingBashRunner: AgentBashRunner {
  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    ProcessResult(exitCode: 127, stdout: "", stderr: "disabled")
  }
}

private actor ChatRecorder {
  private var calls: Int = 0
  private var current: Int = 0
  private var peak: Int = 0
  nonisolated let delay: TimeInterval

  init(callDelay: TimeInterval = 0) {
    self.delay = callDelay
  }

  func callCount() -> Int { calls }
  func peakConcurrency() -> Int { peak }

  func record() {
    calls += 1
    current += 1
    if current > peak { peak = current }
  }

  func release() {
    current -= 1
  }

  /// Closure handed to `RepoSummarizer` as its `chatRequest`. Captures
  /// the actor to track invocation count and in-flight peak.
  nonisolated var chatRequest: RepoSummarizer.ChatRequest {
    let actor = self
    let pause = delay
    return { @Sendable _, _ in
      await actor.record()
      if pause > 0 {
        try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
      }
      await actor.release()
      return "mocked-summary"
    }
  }
}
