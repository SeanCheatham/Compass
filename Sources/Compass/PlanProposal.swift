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
  static func recordingShippedIterations(
    into state: PlanState,
    sessions: [SessionRecord]
  ) -> PlanState {
    let shipped = shippedSessions(from: sessions)
    var updated = state
    for session in shipped.dropFirst(updated.completed.count) {
      updated.completed.append(completionSummary(for: session))
    }
    return updated
  }

  static func completionSummary(for session: SessionRecord) -> String {
    if let planLine = firstNonEmptyLine(session.plan) {
      return planLine
    }
    if let feedbackLine = firstNonEmptyLine(session.feedback) {
      return feedbackLine
    }
    return "Session \(session.session) completed"
  }

  private static func shippedSessions(from sessions: [SessionRecord]) -> [SessionRecord] {
    sessions
      .filter { session in
        session.status == .succeeded
          && firstNonEmptyLine(session.plan) != nil
      }
      .sorted { $0.session < $1.session }
  }

  private static func firstNonEmptyLine(_ text: String?) -> String? {
    guard let text else { return nil }
    for line in text.split(whereSeparator: \.isNewline) {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
    }
    return nil
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
      lines.append("#\(entry.iteration): \(entry.summary)")
    }
    if offset + showing < totalCount {
      lines.append(
        "more: call plan_history with offset \(offset + showing) to read older entries")
    }
    return lines.joined(separator: "\n")
  }
}
