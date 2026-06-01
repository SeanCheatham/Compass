import Foundation

/// Active planning fields agents may propose. Completed history is owned
/// by Compass and is not part of the Plan/Reflect submit_result contract.
struct PlanProposal: Codable, Equatable {
  var immediate: PlanNext?
  var midTerm: String
  var longTerm: String

  enum CodingKeys: String, CodingKey {
    case immediate
    case next
    case nextImmediate
    case immediatePlan
    case midTerm
    case midterm
    case mid_term
    case nearTerm
    case nearTermQueue
    case longTerm
    case longterm
    case long_term
    case strategicArc
  }

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

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    immediate = try Self.decodeRequiredOptionalPlanNext(
      from: container,
      preferredKey: .immediate,
      aliases: [.next, .nextImmediate, .immediatePlan],
      fieldName: "immediate"
    )
    midTerm = try Self.decodeRequiredString(
      from: container,
      preferredKey: .midTerm,
      aliases: [.midterm, .mid_term, .nearTerm, .nearTermQueue],
      fieldName: "midTerm"
    )
    longTerm = try Self.decodeRequiredString(
      from: container,
      preferredKey: .longTerm,
      aliases: [.longterm, .long_term, .strategicArc],
      fieldName: "longTerm"
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(immediate, forKey: .immediate)
    if immediate == nil {
      try container.encodeNil(forKey: .immediate)
    }
    try container.encode(midTerm, forKey: .midTerm)
    try container.encode(longTerm, forKey: .longTerm)
  }

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

  private static func decodeRequiredOptionalPlanNext(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferredKey: CodingKeys,
    aliases: [CodingKeys],
    fieldName: String
  ) throws -> PlanNext? {
    var sawPresentKey = false
    var decodedNull = false
    var firstTypeError: Error?

    for key in [preferredKey] + aliases where container.contains(key) {
      sawPresentKey = true
      do {
        if let value = try container.decodeIfPresent(PlanNext.self, forKey: key) {
          return value
        }
        decodedNull = true
      } catch {
        firstTypeError = firstTypeError ?? error
      }
    }

    if !sawPresentKey {
      throw DecodingError.keyNotFound(
        preferredKey,
        .init(
          codingPath: container.codingPath,
          debugDescription: "PlanProposal requires \(fieldName)."
        )
      )
    }
    if decodedNull {
      return nil
    }
    if let firstTypeError {
      throw firstTypeError
    }
    return nil
  }

  private static func decodeRequiredString(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferredKey: CodingKeys,
    aliases: [CodingKeys],
    fieldName: String
  ) throws -> String {
    var sawPresentKey = false
    var firstTypeError: Error?

    for key in [preferredKey] + aliases where container.contains(key) {
      sawPresentKey = true
      do {
        return try FlexibleModelDecoder.decodeRequiredString(from: container, forKey: key)
      } catch {
        firstTypeError = firstTypeError ?? error
      }
    }

    if !sawPresentKey {
      throw DecodingError.keyNotFound(
        preferredKey,
        .init(
          codingPath: container.codingPath,
          debugDescription: "PlanProposal requires \(fieldName)."
        )
      )
    }
    if let firstTypeError {
      throw firstTypeError
    }
    return ""
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
