import Foundation

public struct LiveActivitySummary: Equatable, Sendable {
  public var clusterKey: String
  public var text: String
  public var source: Source

  public enum Source: String, Equatable, Sendable {
    case deterministic
    case generated
  }

  public init(clusterKey: String, text: String, source: Source) {
    self.clusterKey = clusterKey
    self.text = LiveActivitySummaryService.fittedSummary(text)
    self.source = source
  }
}

public struct LiveActivityTakeaway: Equatable, Sendable {
  public struct Badge: Equatable, Identifiable, Sendable {
    public var label: String

    public var id: String { label }
  }

  public enum Tone: String, Equatable, Sendable {
    case neutral
    case progress
    case changed
    case warning
    case danger
    case complete
  }

  public var label: String
  public var detail: String
  public var badges: [Badge]
  public var tone: Tone
  public var systemImageName: String

  public init(cluster: LiveActivityCluster) {
    let commandCount = cluster.lines.filter { $0.kind == .command }.count
    let fileChangeCount = cluster.lines.filter { $0.kind == .fileChange }.count
    let agentMessageCount = cluster.lines.filter { $0.kind == .agentMessage }.count
    let failureLines = cluster.lines.filter { $0.status == .failed || $0.level == .error }
    let warningCount = cluster.lines.filter { $0.level == .warning }.count
    let lifecycleLine = cluster.lines.last { $0.kind == .lifecycle && $0.status != .running }
    let primaryFailureInsight = failureLines.compactMap { LiveFailureInsight(line: $0) }.first

    if let primaryFailureInsight {
      label = primaryFailureInsight.title
      detail = primaryFailureInsight.nextStep
      tone = .danger
      systemImageName = primaryFailureInsight.systemImageName
    } else if !failureLines.isEmpty {
      label = "Needs Review"
      detail = "Start with the failed live event before rerunning the smallest proof."
      tone = .danger
      systemImageName = "exclamationmark.triangle.fill"
    } else if warningCount > 0 {
      label = "Review Warnings"
      detail = "Warnings are preserved here so the next run can start from evidence."
      tone = .warning
      systemImageName = "exclamationmark.triangle.fill"
    } else if fileChangeCount > 0 {
      label = "Files Changed"
      detail =
        "Review the touched files, then let Verify or Critic decide whether the slice is ready."
      tone = .changed
      systemImageName = "doc.badge.gearshape"
    } else if lifecycleLine != nil {
      label = "Phase Complete"
      detail = Self.lifecycleDetail(from: lifecycleLine)
      tone = .complete
      systemImageName = "flag.checkered"
    } else if commandCount > 0 {
      label = "Commands Ran"
      detail = "Compass captured command output for this batch."
      tone = .progress
      systemImageName = "terminal"
    } else if agentMessageCount > 0 {
      label = "Agent Note"
      detail = "The agent left context for this run."
      tone = .neutral
      systemImageName = "sparkles"
    } else {
      label = "Activity Logged"
      detail = "Compass preserved these events as handoff context."
      tone = .neutral
      systemImageName = "info.circle"
    }

    badges = Self.badges(
      failureCount: failureLines.count,
      warningCount: warningCount,
      fileChangeCount: fileChangeCount,
      commandCount: commandCount,
      agentMessageCount: agentMessageCount
    )
  }

  private static func lifecycleDetail(from line: LiveLine?) -> String {
    let raw = firstLine(line?.detail) ?? line?.text ?? "The phase reached a boundary."
    let normalized = LiveActivitySummaryService.normalizedPlainText(raw)
    guard !normalized.isEmpty else {
      return "The phase reached a boundary."
    }
    return normalized
  }

  private static func badges(
    failureCount: Int,
    warningCount: Int,
    fileChangeCount: Int,
    commandCount: Int,
    agentMessageCount: Int
  ) -> [Badge] {
    [
      countBadge(failureCount, singular: "failure", plural: "failures"),
      countBadge(warningCount, singular: "warning", plural: "warnings"),
      countBadge(fileChangeCount, singular: "file", plural: "files"),
      countBadge(commandCount, singular: "command", plural: "commands"),
      countBadge(agentMessageCount, singular: "note", plural: "notes"),
    ]
    .compactMap { $0 }
  }

  private static func countBadge(
    _ count: Int,
    singular: String,
    plural: String
  ) -> Badge? {
    guard count > 0 else { return nil }
    return Badge(label: "\(count) \(count == 1 ? singular : plural)")
  }
}

public struct LiveActivityCluster: Equatable, Identifiable {
  public var key: String
  public var lines: [LiveLine]
  public var freezeReason: FreezeReason

  public var id: String { key }

  public enum FreezeReason: String, Equatable {
    case lifecycleBoundary
    case quietGap
    case elapsedSinceStart
  }

  public init(lines: [LiveLine], freezeReason: FreezeReason) {
    self.lines = lines
    self.freezeReason = freezeReason
    key = Self.key(for: lines)
  }

  public var startDate: Date? {
    lines.first?.date
  }

  public var endDate: Date? {
    lines.last?.completedAt ?? lines.last?.date
  }

  public static func key(for lines: [LiveLine]) -> String {
    var hasher = StableLiveActivityHasher()
    for line in lines {
      hasher.combine(line.id.uuidString)
      hasher.combine(eventFingerprint(for: line))
    }
    return "live-summary-v1-\(hasher.hexDigest)"
  }

  public static func eventFingerprint(for line: LiveLine) -> String {
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

public enum LiveActivitySummaryItem: Equatable, Identifiable {
  case frozenCluster(LiveActivityCluster)
  case line(LiveLine)

  public var id: String {
    switch self {
    case .frozenCluster(let cluster):
      return "cluster-\(cluster.key)"
    case .line(let line):
      return "line-\(line.id.uuidString)"
    }
  }
}

public struct LiveActivitySummaryPlan: Equatable {
  public var items: [LiveActivitySummaryItem]
  public var frozenClusters: [LiveActivityCluster]
}

public enum LiveActivitySummaryPlanner {
  public static let quietGap: TimeInterval = 30.0
  public static let maximumClusterAge: TimeInterval = 30.0
  public static let minimumFrozenRowCount = 3

  public static func plan(
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

  public static func inputIdentifier(for lines: [LiveLine]) -> String {
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

public struct LiveActivitySummaryCachePlan: Equatable {
  public var requestedClusters: [LiveActivityCluster]
  public var staleCacheKeys: Set<String>
  public var staleInFlightKeys: Set<String>
}

public enum LiveActivitySummaryCachePlanner {
  public static func plan(
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

public enum LiveActivitySummaryService {
  public static let summaryMaxCharacters = 400
  public static let modelPromptMaxEvents = 32
  public static let modelPromptEventMaxCharacters = 180

  public static func makeSummary(for cluster: LiveActivityCluster) async -> LiveActivitySummary {
    return deterministicSummary(for: cluster)
  }

  public static func deterministicSummary(for cluster: LiveActivityCluster) -> LiveActivitySummary {
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
      sentences.append(
        "The agent logged \(cluster.lines.count) \(pluralize("event", cluster.lines.count)).")
    }

    if failureCount > 0 {
      sentences.append(
        "\(capitalizedCount(failureCount)) \(pluralize("failure", failureCount)) reported."
      )
      if let insight = primaryFailureInsight(in: cluster.lines) {
        sentences.append("Primary failure: \(insight.title).")
      }
    } else if warningCount > 0 {
      sentences.append(
        "\(capitalizedCount(warningCount)) \(pluralize("warning", warningCount)) noted."
      )
    }

    if let lifecycleLine,
      let lifecycleText = firstLine(lifecycleLine.detail) ?? Optional(lifecycleLine.text),
      !lifecycleText.isEmpty
    {
      sentences.append("Phase: " + normalizedPlainText(lifecycleText) + ".")
    }

    let body = sentences.joined(separator: " ")
    return LiveActivitySummary(
      clusterKey: cluster.key,
      text: body,
      source: .deterministic
    )
  }

  public static func parseGeneratedSummary(
    _ raw: String,
    cluster: LiveActivityCluster
  ) -> LiveActivitySummary? {
    let collapsed =
      raw
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

  public static func fittedSummary(_ text: String) -> String {
    fittedPlainText(normalizedPlainText(text), maxCharacters: summaryMaxCharacters)
  }

  public static func normalizedPlainText(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func modelPromptLines(for cluster: LiveActivityCluster) -> [String] {
    boundedModelLines(cluster.lines).enumerated().map { index, line in
      let promptText = fittedPlainText(
        promptText(for: line),
        maxCharacters: modelPromptEventMaxCharacters
      )
      return "\(index + 1). \(promptText)"
    }
  }

  private static func promptText(for line: LiveLine) -> String {
    var parts = [statusName(line.status), kindName(line.kind), line.text]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    if let insight = LiveFailureInsight(line: line) {
      parts.append("failure insight: \(insight.title) - \(insight.nextStep)")
    }
    if let detail = firstLine(line.detail)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !detail.isEmpty
    {
      parts.append(detail)
    }
    return parts.joined(separator: " | ")
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

  private static func primaryFailureInsight(in lines: [LiveLine]) -> LiveFailureInsight? {
    for line in lines {
      if let insight = LiveFailureInsight(line: line) {
        return insight
      }
    }
    return nil
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

private struct StableLiveActivityHasher {
  private var value: UInt64 = 14_695_981_039_346_656_037

  public var hexDigest: String {
    String(value, radix: 16)
  }

  public mutating func combine(_ string: String) {
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

public extension LiveLine.Level {
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

public extension LiveLine.Kind {
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

public extension LiveLine.Status {
  fileprivate var summaryName: String {
    switch self {
    case .none: return "noted"
    case .running: return "running"
    case .completed: return "completed"
    case .failed: return "failed"
    }
  }
}
