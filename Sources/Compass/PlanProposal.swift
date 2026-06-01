import Foundation

/// Active planning fields agents may propose. Completed history is owned
/// by Compass and is not part of the Plan/Reflect submit_result contract.
struct PlanProposal: Codable, Equatable {
  var immediate: PlanNext?
  var midTerm: String
  var longTerm: String

  init(immediate: PlanNext?, midTerm: String, longTerm: String) {
    self.immediate = immediate
    self.midTerm = midTerm
    self.longTerm = longTerm
  }

  init(from state: PlanState) {
    immediate = state.immediate
    midTerm = state.midTerm
    longTerm = state.longTerm
  }

  static let empty = PlanProposal(immediate: nil, midTerm: "", longTerm: "")

  func applying(to state: PlanState) -> PlanState {
    PlanState(
      completed: state.completed,
      immediate: immediate,
      midTerm: midTerm,
      longTerm: longTerm
    )
  }

  func removingHostXcodeRequirement() -> PlanProposal {
    guard var immediate else { return self }
    immediate.requiresHostXcode = false
    return PlanProposal(immediate: immediate, midTerm: midTerm, longTerm: longTerm)
  }
}

enum PlanCompletionRecorder {
  private static let completionSummaryLimit = 180
  private static let genericSectionHeadings: Set<String> = [
    "acceptance checks",
    "dead code removal",
    "implementation",
    "key sections",
    "note",
    "notes",
    "outcome",
    "rationale",
    "steps",
    "tests to add",
    "verify",
    "what to change",
    "what to implement",
    "why it matters",
  ]

  static func recordingShippedIterations(
    into state: PlanState,
    sessions: [SessionRecord]
  ) -> PlanState {
    let shipped = shippedSessions(from: sessions)
    var updated = state
    for (index, session) in shipped.enumerated() {
      let summary = completionSummary(for: session)
      if index < updated.completed.count {
        if shouldReplaceStoredSummary(updated.completed[index], with: summary) {
          updated.completed[index] = summary
        }
      } else {
        updated.completed.append(summary)
      }
    }
    return updated
  }

  static func completionSummary(for session: SessionRecord) -> String {
    if let planLine = firstMeaningfulLine(session.plan) {
      return planLine
    }
    if let feedbackLine = firstMeaningfulLine(session.feedback) {
      return feedbackLine
    }
    return "Session \(session.session) completed"
  }

  private static func shippedSessions(from sessions: [SessionRecord]) -> [SessionRecord] {
    sessions
      .filter { session in
        session.status == .succeeded
          && firstMeaningfulLine(session.plan) != nil
      }
      .sorted { $0.session < $1.session }
  }

  private static func firstMeaningfulLine(_ text: String?) -> String? {
    guard let text else { return nil }
    for line in text.split(whereSeparator: \.isNewline) {
      let trimmed = cleanedSummaryLine(String(line))
      guard !trimmed.isEmpty else { continue }
      if genericSectionHeadings.contains(normalizedHeadingKey(trimmed)) {
        continue
      }
      return boundedCompletionSummary(trimmed)
    }
    return nil
  }

  private static func shouldReplaceStoredSummary(_ existing: String, with replacement: String) -> Bool {
    guard existing != replacement else { return false }
    let cleaned = cleanedSummaryLine(existing)
    let key = normalizedHeadingKey(cleaned)
    return existing.count > completionSummaryLimit
      || existing.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#")
      || genericSectionHeadings.contains(key)
  }

  private static func cleanedSummaryLine(_ line: String) -> String {
    var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    while trimmed.first == "#" {
      trimmed.removeFirst()
      trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
      trimmed.removeFirst()
      trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return trimmed
  }

  private static func normalizedHeadingKey(_ line: String) -> String {
    line
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: ":`*_ "))
      .lowercased()
  }

  private static func boundedCompletionSummary(_ line: String) -> String {
    let normalized = StringUtils.boundedText(line, limit: Int.max)
    guard normalized.count > completionSummaryLimit else { return normalized }
    guard completionSummaryLimit > 3 else {
      return String(normalized.prefix(completionSummaryLimit))
    }
    return String(normalized.prefix(completionSummaryLimit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

struct PlanHistoryPage: Equatable {
  struct Entry: Equatable {
    /// One-based iteration number matching state.completed indices.
    var iteration: Int
    var summary: String
  }

  var totalCount: Int
  var offset: Int
  var limit: Int
  var entries: [Entry]

  static let defaultLimit = 10
  static let maxLimit = 50
  private static let summaryDisplayLimit = 220

  static func read(
    entries: [String],
    offset: Int = 0,
    limit: Int = defaultLimit
  ) -> PlanHistoryPage {
    let clampedOffset = max(0, offset)
    let clampedLimit = min(max(1, limit), maxLimit)
    let reversed = Array(entries.enumerated().reversed())
    let slice = reversed.dropFirst(clampedOffset).prefix(clampedLimit)
    let pageEntries = slice.enumerated().map { sliceIndex, entry in
      Entry(iteration: entries.count - clampedOffset - sliceIndex, summary: entry.1)
    }
    return PlanHistoryPage(
      totalCount: entries.count,
      offset: clampedOffset,
      limit: clampedLimit,
      entries: pageEntries
    )
  }

  func formatted() -> String {
    if totalCount == 0 {
      return "plan history: empty"
    }
    let showing = entries.count
    var lines = [
      "plan history: \(totalCount) total, showing \(showing) (offset \(offset) from newest)"
    ]
    for entry in entries {
      let summary = StringUtils.boundedText(entry.summary, limit: Self.summaryDisplayLimit)
      lines.append("#\(entry.iteration): \(summary)")
    }
    if offset + showing < totalCount {
      lines.append(
        "more: call plan_history with offset \(offset + showing) to read older entries")
    }
    return lines.joined(separator: "\n")
  }
}
