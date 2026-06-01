import Foundation

struct ReflectSessionBrief: Equatable {
  static let defaultSessionLimit = 5
  static let textLimit = 220
  static let tailLimit = 180
  static let noteLimit = 2

  var text: String

  init(
    sessions: [SessionRecord],
    sessionLimit: Int = Self.defaultSessionLimit
  ) {
    let items = PlanSessionHistory.displayItems(
      for: sessions,
      planExcerptLimit: PlanHandoffDigest.textLimit
    )
    guard !items.isEmpty else {
      text = "_(no recent sessions recorded)_"
      return
    }

    let boundedSessionLimit = max(1, sessionLimit)
    var lines: [String] = [
      "Use this brief to spot patterns before reading the raw session JSON.",
      "Raw JSON below remains authoritative.",
      "Status mix: \(Self.statusMix(for: items)).",
    ]

    for item in items.prefix(boundedSessionLimit) {
      lines.append(contentsOf: Self.lines(for: item))
    }

    let omittedCount = items.count - boundedSessionLimit
    if omittedCount > 0 {
      lines.append(
        "Omitted \(omittedCount) older \(PlanSessionHistoryDisplay.runWord(for: omittedCount)) from this brief."
      )
    }

    text = lines.joined(separator: "\n")
  }

  private static func lines(for item: PlanSessionHistoryItem) -> [String] {
    var lines: [String] = [
      "- Session #\(item.sessionNumber): \(item.statusText)"
    ]

    switch item.handoffDigest.status {
    case .missingPlan:
      if let planExcerpt = item.planExcerpt {
        lines.append("  Plan excerpt: \(bounded(planExcerpt))")
      } else {
        lines.append("  Plan: none recorded.")
      }
    case .needsDetail, .ready:
      lines.append("  Handoff: \(item.handoffDigest.title). \(item.handoffDigest.detail)")
      if let outcome = item.handoffDigest.outcome {
        lines.append("  Outcome: \(bounded(outcome))")
      }
      if let whyItMatters = item.handoffDigest.whyItMatters {
        lines.append("  Why it matters: \(bounded(whyItMatters))")
      }
      if !item.handoffDigest.acceptanceChecks.isEmpty {
        lines.append(
          "  Acceptance: \(bounded(item.handoffDigest.acceptanceChecks.joined(separator: "; ")))"
        )
      }
    }

    if let verifyCommand = item.verifyCommand {
      let verify = PlanVerifyCommandSummary(command: verifyCommand)
      lines.append("  Verify: \(verify.title). \(verify.detail)")
    } else {
      lines.append("  Verify: none recorded.")
    }

    if let failedVerify = item.failedVerify {
      lines.append(
        "  Result: verify failed \(failedVerify.exitCodeText). Tail: \(bounded(failedVerify.tail, limit: tailLimit))"
      )
    } else {
      lines.append("  Result: \(resultText(for: item.status)).")
    }

    if !item.commits.isEmpty {
      lines.append(
        "  Commits: \(item.commits.count) \(item.commits.count == 1 ? "commit" : "commits")."
      )
    }

    if let feedback = item.feedback {
      lines.append("  Feedback: \(bounded(feedback))")
    }

    for note in item.notes.prefix(noteLimit) {
      lines.append("  Note: \(bounded(note))")
    }

    let omittedNotes = item.notes.count - noteLimit
    if omittedNotes > 0 {
      lines.append("  Notes: \(omittedNotes) older notes omitted.")
    }

    return lines
  }

  private static func statusMix(for items: [PlanSessionHistoryItem]) -> String {
    var order: [String] = []
    var counts: [String: Int] = [:]
    for item in items {
      let status = item.statusText.lowercased()
      if counts[status] == nil {
        order.append(status)
      }
      counts[status, default: 0] += 1
    }

    return order.compactMap { status in
      guard let count = counts[status] else { return nil }
      return "\(count) \(status)"
    }
    .joined(separator: ", ")
  }

  private static func resultText(for status: SessionStatus) -> String {
    switch status {
    case .planning:
      return "planning is still running"
    case .awaitingApproval:
      return "waiting for Develop approval"
    case .developing:
      return "develop is still running"
    case .succeeded:
      return "session succeeded"
    case .failed:
      return "session failed before a verify tail was captured"
    case .cancelled:
      return "session was cancelled"
    case .rejectedByPlan:
      return "plan was rejected before Develop"
    case .skipped:
      return "session was skipped"
    }
  }

  private static func bounded(_ text: String, limit: Int = textLimit) -> String {
    let normalized =
      text
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.count > limit else {
      return normalized
    }
    guard limit > 3 else {
      return String(normalized.prefix(limit))
    }
    return String(normalized.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
