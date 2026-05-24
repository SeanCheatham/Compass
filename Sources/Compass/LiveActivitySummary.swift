import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

struct LiveActivitySummary: Equatable, Sendable {
  var clusterKey: String
  var text: String
  var source: Source

  enum Source: String, Equatable, Sendable {
    case deterministic
    case generated
  }

  init(clusterKey: String, text: String, source: Source) {
    self.clusterKey = clusterKey
    self.text = LiveActivitySummaryService.fittedSummary(text)
    self.source = source
  }
}

struct LiveActivityCluster: Equatable, Identifiable {
  var key: String
  var lines: [LiveLine]
  var freezeReason: FreezeReason

  var id: String { key }

  enum FreezeReason: String, Equatable {
    case lifecycleBoundary
    case quietGap
    case elapsedSinceStart
  }

  init(lines: [LiveLine], freezeReason: FreezeReason) {
    self.lines = lines
    self.freezeReason = freezeReason
    key = Self.key(for: lines)
  }

  var startDate: Date? {
    lines.first?.date
  }

  var endDate: Date? {
    lines.last?.completedAt ?? lines.last?.date
  }

  static func key(for lines: [LiveLine]) -> String {
    var hasher = StableLiveActivityHasher()
    for line in lines {
      hasher.combine(line.id.uuidString)
      hasher.combine(eventFingerprint(for: line))
    }
    return "live-summary-v1-\(hasher.hexDigest)"
  }

  static func eventFingerprint(for line: LiveLine) -> String {
    [
      line.status.summaryName,
      line.kind.summaryName,
      line.level.summaryName,
      boundedFingerprintText(line.text),
      boundedFingerprintText(firstLine(line.detail) ?? ""),
    ]
    .joined(separator: "|")
  }

  private static func boundedFingerprintText(_ text: String) -> String {
    let normalized = LiveActivitySummaryService.normalizedPlainText(text)
    guard normalized.count > 72 else { return normalized }
    return String(normalized.prefix(72))
  }
}

enum LiveActivitySummaryItem: Equatable, Identifiable {
  case frozenCluster(LiveActivityCluster)
  case line(LiveLine)

  var id: String {
    switch self {
    case .frozenCluster(let cluster):
      return "cluster-\(cluster.key)"
    case .line(let line):
      return "line-\(line.id.uuidString)"
    }
  }
}

struct LiveActivitySummaryPlan: Equatable {
  var items: [LiveActivitySummaryItem]
  var frozenClusters: [LiveActivityCluster]
}

enum LiveActivitySummaryPlanner {
  static let quietGap: TimeInterval = 30.0
  static let maximumClusterAge: TimeInterval = 30.0
  static let minimumFrozenRowCount = 3

  static func plan(
    lines: [LiveLine],
    now: Date = Date(),
    quietGap: TimeInterval = Self.quietGap,
    maximumClusterAge: TimeInterval = Self.maximumClusterAge,
    minimumFrozenRowCount: Int = Self.minimumFrozenRowCount
  ) -> LiveActivitySummaryPlan {
    let minimumFrozenRowCount = max(1, minimumFrozenRowCount)
    var items: [LiveActivitySummaryItem] = []
    var frozenClusters: [LiveActivityCluster] = []
    var pendingLines: [LiveLine] = []

    for index in lines.indices {
      let line = lines[index]
      pendingLines.append(line)

      guard pendingLines.count >= minimumFrozenRowCount,
        pendingLines.allSatisfy({ !isBlockingRunningLine($0) }),
        let firstDate = pendingLines.first?.date
      else {
        continue
      }

      let nextLine =
        lines.index(after: index) < lines.endIndex
        ? lines[lines.index(after: index)]
        : nil
      guard
        let freezeReason = freezeReason(
          endingWith: line,
          firstDate: firstDate,
          nextLine: nextLine,
          now: now,
          quietGap: quietGap,
          maximumClusterAge: maximumClusterAge
        )
      else {
        continue
      }

      let cluster = LiveActivityCluster(
        lines: pendingLines,
        freezeReason: freezeReason
      )
      items.append(.frozenCluster(cluster))
      frozenClusters.append(cluster)
      pendingLines.removeAll()
    }

    items.append(contentsOf: pendingLines.map(LiveActivitySummaryItem.line))
    return LiveActivitySummaryPlan(items: items, frozenClusters: frozenClusters)
  }

  static func inputIdentifier(for lines: [LiveLine]) -> String {
    var hasher = StableLiveActivityHasher()
    for line in lines {
      hasher.combine(line.id.uuidString)
      hasher.combine(String(line.date.timeIntervalSince1970))
      hasher.combine(LiveActivityCluster.eventFingerprint(for: line))
    }
    return "live-input-v1-\(hasher.hexDigest)"
  }

  private static func isBlockingRunningLine(_ line: LiveLine) -> Bool {
    // Lifecycle markers (e.g. "Agent iteration N") are emitted with
    // status .running but never receive a matching completion event,
    // so they are sentinels rather than in-flight work.
    line.status == .running && line.kind != .lifecycle
  }

  private static func freezeReason(
    endingWith line: LiveLine,
    firstDate: Date,
    nextLine: LiveLine?,
    now: Date,
    quietGap: TimeInterval,
    maximumClusterAge: TimeInterval
  ) -> LiveActivityCluster.FreezeReason? {
    if line.kind == .lifecycle, line.status != .running {
      return .lifecycleBoundary
    }

    let gap: TimeInterval
    if let nextLine {
      gap = nextLine.date.timeIntervalSince(line.date)
    } else {
      gap = now.timeIntervalSince(line.date)
    }
    if gap > quietGap {
      return .quietGap
    }

    let referenceDate = nextLine?.date ?? now
    if referenceDate.timeIntervalSince(firstDate) >= maximumClusterAge {
      return .elapsedSinceStart
    }

    return nil
  }
}

struct LiveActivitySummaryCachePlan: Equatable {
  var requestedClusters: [LiveActivityCluster]
  var staleCacheKeys: Set<String>
  var staleInFlightKeys: Set<String>
}

enum LiveActivitySummaryCachePlanner {
  static func plan(
    clusters: [LiveActivityCluster],
    cachedKeys: Set<String>,
    inFlightKeys: Set<String>
  ) -> LiveActivitySummaryCachePlan {
    let activeKeys = Set(clusters.map(\.key))
    let requestedClusters = clusters.filter {
      !cachedKeys.contains($0.key) && !inFlightKeys.contains($0.key)
    }

    return LiveActivitySummaryCachePlan(
      requestedClusters: requestedClusters,
      staleCacheKeys: cachedKeys.subtracting(activeKeys),
      staleInFlightKeys: inFlightKeys.subtracting(activeKeys)
    )
  }
}

enum LiveActivitySummaryService {
  static let summaryMaxCharacters = 400
  static let modelPromptMaxEvents = 32
  static let modelPromptEventMaxCharacters = 180

  static func makeSummary(for cluster: LiveActivityCluster) async -> LiveActivitySummary {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        if let generated = try? await FoundationModelLiveActivitySummaryGenerator.generate(
          cluster: cluster
        ) {
          return generated
        }
      }
    #endif

    return deterministicSummary(for: cluster)
  }

  static func deterministicSummary(for cluster: LiveActivityCluster) -> LiveActivitySummary {
    let commandCount = cluster.lines.filter { $0.kind == .command }.count
    let fileChangeCount = cluster.lines.filter { $0.kind == .fileChange }.count
    let agentMessageCount = cluster.lines.filter { $0.kind == .agentMessage }.count
    let failureCount = cluster.lines.filter { $0.status == .failed || $0.level == .error }
      .count
    let warningCount = cluster.lines.filter { $0.level == .warning }.count
    let lifecycleLine = cluster.lines.last { $0.kind == .lifecycle && $0.status != .running }

    var phrases: [String] = []
    if commandCount > 0 {
      phrases.append("ran \(commandCount) \(pluralize("command", commandCount))")
    }
    if fileChangeCount > 0 {
      phrases.append("touched \(fileChangeCount) \(pluralize("file", fileChangeCount))")
    }
    if agentMessageCount > 0 {
      phrases.append(
        "posted \(agentMessageCount) agent \(pluralize("note", agentMessageCount))"
      )
    }

    var sentences: [String] = []
    if !phrases.isEmpty {
      sentences.append("The agent " + joinPhrases(phrases) + ".")
    } else {
      sentences.append("The agent logged \(cluster.lines.count) \(pluralize("event", cluster.lines.count)).")
    }

    if failureCount > 0 {
      sentences.append(
        "\(capitalizedCount(failureCount)) \(pluralize("failure", failureCount)) reported."
      )
    } else if warningCount > 0 {
      sentences.append(
        "\(capitalizedCount(warningCount)) \(pluralize("warning", warningCount)) noted."
      )
    }

    if let lifecycleLine,
      let lifecycleText = firstLine(lifecycleLine.detail) ?? Optional(lifecycleLine.text),
      !lifecycleText.isEmpty {
      sentences.append("Phase: " + normalizedPlainText(lifecycleText) + ".")
    }

    let body = sentences.joined(separator: " ")
    return LiveActivitySummary(
      clusterKey: cluster.key,
      text: body,
      source: .deterministic
    )
  }

  static func parseGeneratedSummary(
    _ raw: String,
    cluster: LiveActivityCluster
  ) -> LiveActivitySummary? {
    let collapsed = raw
      .replacingOccurrences(of: "\r", with: "\n")
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")

    let stripped: String
    if collapsed.lowercased().hasPrefix("summary:") {
      stripped = stripLabel(from: collapsed)
    } else {
      stripped = collapsed
    }

    let clean = normalizeGeneratedText(stripped)
    guard validateGeneratedSummary(clean) else { return nil }
    return LiveActivitySummary(
      clusterKey: cluster.key,
      text: clean,
      source: .generated
    )
  }

  static func fittedSummary(_ text: String) -> String {
    fittedPlainText(normalizedPlainText(text), maxCharacters: summaryMaxCharacters)
  }

  static func normalizedPlainText(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func modelPromptLines(for cluster: LiveActivityCluster) -> [String] {
    boundedModelLines(cluster.lines).enumerated().map { index, line in
      let promptText = fittedPlainText(
        promptText(for: line),
        maxCharacters: modelPromptEventMaxCharacters
      )
      return "\(index + 1). \(promptText)"
    }
  }

  private static func promptText(for line: LiveLine) -> String {
    [statusName(line.status), kindName(line.kind), line.text, firstLine(line.detail)]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " | ")
  }

  private static func kindName(_ kind: LiveLine.Kind) -> String {
    switch kind {
    case .message: return "message"
    case .lifecycle: return "lifecycle"
    case .command: return "command"
    case .agentMessage: return "agent"
    case .fileChange: return "file change"
    }
  }

  private static func statusName(_ status: LiveLine.Status) -> String {
    switch status {
    case .none: return "noted"
    case .running: return "running"
    case .completed: return "completed"
    case .failed: return "failed"
    }
  }

  private static func validateGeneratedSummary(_ text: String) -> Bool {
    guard (8...summaryMaxCharacters).contains(text.count),
      isPlainGeneratedProse(text)
    else {
      return false
    }
    return true
  }

  private static func isPlainGeneratedProse(_ text: String) -> Bool {
    let lowercased = text.lowercased()
    guard !lowercased.contains("http://"),
      !lowercased.contains("https://"),
      !lowercased.contains("www."),
      !text.contains("```"),
      !text.contains("`"),
      !text.contains("{"),
      !text.contains("}"),
      !text.hasPrefix("#"),
      !text.hasPrefix("- "),
      !text.hasPrefix("* "),
      !text.hasPrefix(">")
    else {
      return false
    }
    return true
  }

  private static func normalizeGeneratedText(_ text: String) -> String {
    normalizedPlainText(text)
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
  }

  private static func boundedModelLines(_ lines: [LiveLine]) -> [LiveLine] {
    guard lines.count > modelPromptMaxEvents else { return lines }
    let headCount = modelPromptMaxEvents / 2
    let tailCount = modelPromptMaxEvents - headCount
    return Array(lines.prefix(headCount)) + Array(lines.suffix(tailCount))
  }

  private static func fittedPlainText(_ text: String, maxCharacters: Int) -> String {
    let normalized = normalizedPlainText(text)
    guard normalized.count > maxCharacters else { return normalized }

    let prefix = normalized.prefix(maxCharacters)
    if let lastSpace = prefix.lastIndex(where: { $0 == " " }), lastSpace > prefix.startIndex {
      return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func stripLabel(from line: String) -> String {
    guard let colon = line.firstIndex(of: ":") else { return line }
    return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
  }

  private static func pluralize(_ word: String, _ count: Int) -> String {
    count == 1 ? word : word + "s"
  }

  private static func joinPhrases(_ phrases: [String]) -> String {
    switch phrases.count {
    case 0: return ""
    case 1: return phrases[0]
    case 2: return phrases[0] + " and " + phrases[1]
    default:
      let head = phrases.dropLast().joined(separator: ", ")
      return head + ", and " + phrases.last!
    }
  }

  private static func capitalizedCount(_ count: Int) -> String {
    switch count {
    case 1: return "One"
    case 2: return "Two"
    case 3: return "Three"
    case 4: return "Four"
    case 5: return "Five"
    case 6: return "Six"
    case 7: return "Seven"
    case 8: return "Eight"
    case 9: return "Nine"
    default: return String(count)
    }
  }
}

#if canImport(FoundationModels)
  @available(macOS 26.0, *)
  private enum FoundationModelLiveActivitySummaryGenerator {
    static func generate(cluster: LiveActivityCluster) async throws -> LiveActivitySummary? {
      let model = SystemLanguageModel.default
      guard model.isAvailable else { return nil }

      let session = LanguageModelSession(
        instructions: """
          You summarize a batch of recent Compass live activity for a macOS software factory.
          Return a single paragraph of 2 to 3 plain-text sentences describing what happened.
          Write in past tense, third person, present a calm narrative of the work.
          Ground every claim in the supplied events; you may reference file names, commands, counts, and outcomes that appear in those events.
          Do not use markdown, code fences, JSON, bullet points, or URLs.
          """)

      let events = LiveActivitySummaryService.modelPromptLines(for: cluster)
        .joined(separator: "\n")

      let response = try await session.respond(
        to: """
          Events since the last summary:
          \(events)

          Write 2 to 3 sentences summarizing what the agent did in this batch.
          """,
        options: GenerationOptions(temperature: 0.4, maximumResponseTokens: 220)
      )

      return LiveActivitySummaryService.parseGeneratedSummary(
        response.content,
        cluster: cluster
      )
    }
  }
#endif

private struct StableLiveActivityHasher {
  private var value: UInt64 = 14_695_981_039_346_656_037

  var hexDigest: String {
    String(value, radix: 16)
  }

  mutating func combine(_ string: String) {
    for byte in string.utf8 {
      value ^= UInt64(byte)
      value &*= 1_099_511_628_211
    }
    value ^= UInt64(0xff)
    value &*= 1_099_511_628_211
  }
}

private func firstLine(_ text: String?) -> String? {
  text?
    .split(whereSeparator: \.isNewline)
    .first
    .map(String.init)
}

extension LiveLine.Level {
  fileprivate var summaryName: String {
    switch self {
    case .info: return "info"
    case .success: return "success"
    case .warning: return "warning"
    case .error: return "error"
    case .raw: return "raw"
    }
  }
}

extension LiveLine.Kind {
  fileprivate var summaryName: String {
    switch self {
    case .message: return "message"
    case .lifecycle: return "lifecycle"
    case .command: return "command"
    case .agentMessage: return "agent"
    case .fileChange: return "file change"
    }
  }
}

extension LiveLine.Status {
  fileprivate var summaryName: String {
    switch self {
    case .none: return "noted"
    case .running: return "running"
    case .completed: return "completed"
    case .failed: return "failed"
    }
  }
}
