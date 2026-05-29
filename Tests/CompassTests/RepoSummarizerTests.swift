import Foundation
import Testing

@testable import Compass

struct RepoSummarizerTests: ~Copyable {
  private var workingDirectory: URL!
  private var cacheDirectory: URL!

  init() throws {
    workingDirectory = try makeTempDir()
    cacheDirectory = workingDirectory.appendingPathComponent(".compass/codemap")
  }

  deinit {
    if let workingDirectory {
      try? FileManager.default.removeItem(at: workingDirectory)
    }
  }

  @Test
  func testSummarizesEachEntryWithMissingSummary() async throws {
    let store = CodemapStore(directory: cacheDirectory)
    try await primeFile("alpha.swift", contents: swiftFixture)
    try await primeFile("beta.swift", contents: swiftFixture)

    let indexer = makeIndexer(store: store)
    _ = try await indexer.indexAll()

    let recorder = ChatRecorder()
    let summarizer = makeSummarizer(store: store, recorder: recorder)
    let result = await summarizer.summarizeMissing()

    try #require(result.generated == 2)
    try #require(result.failed == 0)
    let calls = await recorder.callCount()
    try #require(calls == 2)

    let alpha = try #require(store.loadEntry(forRelativePath: "alpha.swift"))
    try #require(alpha.summary == "mocked-summary")
    try #require(alpha.summaryContentHash == alpha.contentHash)
    try #require(alpha.summaryModel == "test-summary-model")
  }

  @Test
  func testCachedSummaryIsLeftAloneWhenContentUnchanged() async throws {
    let store = CodemapStore(directory: cacheDirectory)
    try await primeFile("alpha.swift", contents: swiftFixture)

    let indexer = makeIndexer(store: store)
    _ = try await indexer.indexAll()

    let recorder = ChatRecorder()
    let summarizer = makeSummarizer(store: store, recorder: recorder)
    _ = await summarizer.summarizeMissing()
    let firstPass = await recorder.callCount()
    try #require(firstPass == 1)

    // Re-run: same hash, same model → no new call.
    _ = await summarizer.summarizeMissing()
    let secondPass = await recorder.callCount()
    try #require(secondPass == 1)
  }

  @Test
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

    let entryAfterReparse = try #require(
      store.loadEntry(forRelativePath: "alpha.swift")
    )
    try #require(entryAfterReparse.summary == nil)

    _ = await summarizer.summarizeMissing()
    let calls = await recorder.callCount()
    try #require(calls == 2)
  }

  @Test
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
    try #require(result.generated == 0)
    let calls = await recorder.callCount()
    try #require(calls == 0)
  }

  @Test
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
    try #require(result.failed == 1)
    let calls = await recorder.callCount()
    try #require(calls == 0)
  }

  @Test
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
    try #require(peak <= 2)
    let calls = await recorder.callCount()
    try #require(calls == fileCount)
  }

  @Test
  func testEnsureSummaryReturnsCachedWhenFresh() async throws {
    let store = CodemapStore(directory: cacheDirectory)
    try await primeFile("alpha.swift", contents: swiftFixture)
    let indexer = makeIndexer(store: store)
    _ = try await indexer.indexAll()

    let recorder = ChatRecorder()
    let summarizer = makeSummarizer(store: store, recorder: recorder)
    let first = try await summarizer.ensureSummary(forRelativePath: "alpha.swift")
    try #require(first == "mocked-summary")
    let firstCalls = await recorder.callCount()
    try #require(firstCalls == 1)

    let second = try await summarizer.ensureSummary(forRelativePath: "alpha.swift")
    try #require(second == "mocked-summary")
    let secondCalls = await recorder.callCount()
    try #require(secondCalls == 1)
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
