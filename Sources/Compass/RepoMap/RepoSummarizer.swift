import Foundation

/// Drives the per-file summary pass. Inputs come from the on-disk
/// `CodemapStore` (which `CodemapIndexer` populates with symbols); for any
/// entry whose `summary` is missing or whose `summaryContentHash` no longer
/// matches `contentHash`, the summarizer reads the file via
/// `AgentFilesystem`, builds a deterministic summary, and persists it back
/// into the store entry.
struct RepoSummarizer: Sendable {
  /// Hard cap on in-flight chat calls. Tuned so a 500-file repo on a
  /// home connection finishes in ~minutes without saturating any
  /// upstream rate limit Compass has been pointed at.
  static let defaultMaxInFlight = 8
  /// Files past this size get truncated before being sent. The model
  /// rarely produces a meaningfully different summary past ~60 kB.
  static let defaultMaxCharsPerCall = 60_000
  /// Cap on the model's reply token budget. Three sentences fit easily.
  static let maxSummaryTokens = 256
  /// Skip files smaller than this when picking targets — almost always
  /// trivial re-exports / stubs whose symbol list says enough.
  static let defaultMinSourceChars = 80

  struct Result: Sendable, Equatable {
    var generated: Int
    var skipped: Int
    var failed: Int
    var unchanged: Int
  }

  enum SummarizerError: Error, LocalizedError, Equatable {
    case emptyResponse
    case readFailure(String)

    var errorDescription: String? {
      switch self {
      case .emptyResponse: return "Codemap model returned an empty summary."
      case .readFailure(let detail): return "Could not read file: \(detail)"
      }
    }
  }

  /// Given a prompt and model name, return the summary string. Kept injectable
  /// so tests can override the deterministic default.
  typealias ChatRequest = @Sendable (_ prompt: String, _ model: String) async throws -> String

  let workingDirectory: URL
  let store: CodemapStore
  let filesystem: AgentFilesystem
  let settings: AgentRuntimeSettings
  let maxInFlight: Int
  let maxCharsPerCall: Int
  let minSourceChars: Int
  let chatRequest: ChatRequest

  init(
    workingDirectory: URL,
    store: CodemapStore,
    settings: AgentRuntimeSettings,
    filesystem: AgentFilesystem = AgentHostFilesystem(),
    maxInFlight: Int = RepoSummarizer.defaultMaxInFlight,
    maxCharsPerCall: Int = RepoSummarizer.defaultMaxCharsPerCall,
    minSourceChars: Int = RepoSummarizer.defaultMinSourceChars,
    chatRequest: ChatRequest? = nil
  ) {
    self.workingDirectory = workingDirectory.standardizedFileURL
    self.store = store
    self.filesystem = filesystem
    self.settings = settings
    self.maxInFlight = max(1, maxInFlight)
    self.maxCharsPerCall = maxCharsPerCall
    self.minSourceChars = minSourceChars
    self.chatRequest = chatRequest ?? RepoSummarizer.makeDefaultChatRequest(settings: settings)
  }

  static func makeDefaultChatRequest(settings: AgentRuntimeSettings) -> ChatRequest {
    _ = settings
    return { @Sendable prompt, _ in
      let lines =
        prompt
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && !$0.hasPrefix("```") }
      let fileLine = lines.first { $0.hasPrefix("File: ") } ?? "File: source"
      let sample =
        lines
        .drop { !$0.hasPrefix("```") }
        .dropFirst()
        .prefix(8)
        .joined(separator: " ")
      let summary = "\(fileLine.replacingOccurrences(of: "File: ", with: "")) provides source code. Key local context: \(sample)"
      return String(summary.prefix(500)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  /// Generate summaries for every entry that's missing one. Returns
  /// counts so callers can render a `42 generated, 3 failed` status row.
  /// `progress` fires after each call (success or failure) with running
  /// (done, total) totals.
  func summarizeMissing(
    progress: @Sendable @escaping (_ done: Int, _ total: Int) -> Void = { _, _ in }
  ) async -> Result {
    let targets = pickTargets()
    guard !targets.isEmpty else {
      return Result(generated: 0, skipped: 0, failed: 0, unchanged: 0)
    }

    let counters = SummaryCounters()
    let total = targets.count
    let model = settings.codemapModel
    let captured = self

    await withTaskGroup(of: Void.self) { group in
      var inFlight = 0
      var iter = targets.makeIterator()
      while let next = iter.next() {
        if inFlight >= captured.maxInFlight {
          await group.next()
          inFlight -= 1
        }
        let entry = next
        group.addTask {
          await captured.summarizeOne(entry: entry, model: model, counters: counters)
          let done = await counters.totalSeen()
          progress(done, total)
        }
        inFlight += 1
      }
      await group.waitForAll()
    }

    let snapshot = await counters.snapshot()
    return Result(
      generated: snapshot.generated,
      skipped: snapshot.skipped,
      failed: snapshot.failed,
      unchanged: snapshot.unchanged
    )
  }

  /// Generate the summary for a single relative path. Exposed so the
  /// `summary` agent tool can prime a missing entry on first request.
  func ensureSummary(forRelativePath relativePath: String) async throws -> String? {
    guard let entry = store.loadEntry(forRelativePath: relativePath) else {
      return nil
    }
    if let summary = entry.summary,
      entry.summaryContentHash == entry.contentHash,
      entry.summaryModel == settings.codemapModel
    {
      return summary
    }
    return try await runSummary(for: entry, model: settings.codemapModel)
  }

  // MARK: - Internals

  /// Strip `<think>` blocks reasoning models may embed in
  /// `content` when the endpoint does not split reasoning out.
  static func cleanedSummaryText(_ text: String) -> String {
    let (cleaned, _) = AgentExecutor.stripThinkBlocks(text)
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func pickTargets() -> [CodemapEntry] {
    let codemapModel = settings.codemapModel
    return store.loadAllEntries().filter { entry in
      // No symbols → effectively empty file; summary buys nothing.
      guard !entry.symbols.isEmpty else { return false }
      // Already current for the configured model: leave it.
      if let summary = entry.summary,
        !summary.isEmpty,
        entry.summaryContentHash == entry.contentHash,
        entry.summaryModel == codemapModel
      {
        return false
      }
      return true
    }
    .sorted { $0.relativePath < $1.relativePath }
  }

  private func summarizeOne(
    entry: CodemapEntry,
    model: String,
    counters: SummaryCounters
  ) async {
    do {
      let summary = try await runSummary(for: entry, model: model)
      if summary.isEmpty {
        await counters.recordFailed()
      } else {
        await counters.recordGenerated()
      }
    } catch SummarizerError.readFailure {
      await counters.recordSkipped()
    } catch {
      await counters.recordFailed()
    }
  }

  /// Read the file, build the prompt, hit the model, and write the
  /// summary back into the store. Returns the generated summary (or
  /// throws). Pulled out from `summarizeOne` so `ensureSummary(...)`
  /// can share the logic for on-demand single-file requests.
  private func runSummary(for entry: CodemapEntry, model: String) async throws -> String {
    let absolute = workingDirectory.appendingPathComponent(entry.relativePath)
    let data: Data
    do {
      data = try await filesystem.readFile(at: absolute)
    } catch {
      throw SummarizerError.readFailure(error.localizedDescription)
    }
    let raw = String(decoding: data, as: UTF8.self)
    guard raw.count >= minSourceChars else {
      throw SummarizerError.readFailure("file too small to summarize")
    }
    let snippet: String
    if raw.count > maxCharsPerCall {
      snippet = String(raw.prefix(maxCharsPerCall)) + "\n…(truncated)…"
    } else {
      snippet = raw
    }

    let prompt = """
      Summarize this file in 2–3 sentences. Focus on what it provides, not how.

      File: \(entry.relativePath)

      ```
      \(snippet)
      ```
      """

    let text = try await chatRequest(prompt, model)
    let trimmed = Self.cleanedSummaryText(text)
    guard !trimmed.isEmpty else { throw SummarizerError.emptyResponse }

    var updated = entry
    updated.summary = trimmed
    updated.summaryModel = model
    updated.summaryContentHash = entry.contentHash
    try store.saveEntry(updated)
    return trimmed
  }
}

/// Tiny actor that gathers per-file outcomes from the fan-out so the main
/// summarizer can build a `Result` without sharing mutable state across
/// task boundaries.
private actor SummaryCounters {
  struct Snapshot {
    var generated: Int
    var skipped: Int
    var failed: Int
    var unchanged: Int
  }

  private var generated = 0
  private var skipped = 0
  private var failed = 0
  private var unchanged = 0

  func recordGenerated() { generated += 1 }
  func recordSkipped() { skipped += 1 }
  func recordFailed() { failed += 1 }
  func recordUnchanged() { unchanged += 1 }

  func totalSeen() -> Int { generated + skipped + failed + unchanged }
  func snapshot() -> Snapshot {
    Snapshot(generated: generated, skipped: skipped, failed: failed, unchanged: unchanged)
  }
}
