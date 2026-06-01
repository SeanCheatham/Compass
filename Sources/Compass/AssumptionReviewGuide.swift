import Foundation

struct AssumptionReviewGuide: Equatable, Sendable {
  enum Tone: String, Equatable, Sendable {
    case empty
    case review
    case steady
    case correction
  }

  struct Step: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var detail: String
    var systemImageName: String
    var tone: Tone
  }

  struct QueueItem: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var detail: String
  }

  var title: String
  var detail: String
  var promptEffect: String
  var tone: Tone
  var steps: [Step]
  var queue: [QueueItem]
  var narrationIdentifier: String

  init(ledger: AssumptionLedger) {
    let active = ledger.activeAssumptions
    let implicit = Self.records(status: .implicit, in: active)
    let affirmed = Self.records(status: .affirmed, in: active)
    let denied = Self.records(status: .denied, in: active)

    if active.isEmpty {
      title = "No Memory Yet"
      detail =
        "When Compass makes a consequential guess, it will appear here before it becomes durable guidance."
      promptEffect = "Future prompts are not receiving assumption guidance yet."
      tone = .empty
    } else if !implicit.isEmpty {
      title = "Review Needed"
      detail =
        "\(Self.countLabel(implicit.count, singular: "guess", plural: "guesses")) need a quick yes-or-no check before Compass treats them as reliable."
      promptEffect =
        "Implicit assumptions are still sent to agents, but marked as lower confidence."
      tone = .review
    } else if !denied.isEmpty {
      title = "Corrections Active"
      detail =
        "Compass is carrying \(Self.countLabel(denied.count, singular: "correction", plural: "corrections")) so future agents avoid repeating known-wrong assumptions."
      promptEffect = "Denied assumptions are injected as corrections agents must not rely on."
      tone = .correction
    } else {
      title = "Guidance Ready"
      detail =
        "\(Self.countLabel(affirmed.count, singular: "confirmed assumption", plural: "confirmed assumptions")) are ready to guide future planning and development."
      promptEffect = "Affirmed assumptions are injected as strong user guidance."
      tone = .steady
    }

    steps = Self.steps(implicit: implicit, affirmed: affirmed, denied: denied)
    queue = implicit.prefix(3).map { record in
      QueueItem(
        id: record.id,
        label: record.text,
        detail: Self.queueDetail(for: record)
      )
    }
    narrationIdentifier = Self.narrationIdentifier(
      title: title,
      detail: detail,
      promptEffect: promptEffect,
      tone: tone,
      active: active,
      steps: steps,
      queue: queue
    )
  }

  private static func records(
    status: AssumptionRecord.Status,
    in records: [AssumptionRecord]
  ) -> [AssumptionRecord] {
    records
      .filter { $0.status == status }
      .sorted { lhs, rhs in
        if lhs.updatedAt != rhs.updatedAt {
          return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id < rhs.id
      }
  }

  private static func steps(
    implicit: [AssumptionRecord],
    affirmed: [AssumptionRecord],
    denied: [AssumptionRecord]
  ) -> [Step] {
    var steps: [Step] = []

    if !implicit.isEmpty {
      steps.append(
        Step(
          id: "reviewImplicit",
          label:
            "Review \(countLabel(implicit.count, singular: "open guess", plural: "open guesses"))",
          detail: "Affirm what is true; deny anything wrong with a short correction.",
          systemImageName: "questionmark.circle",
          tone: .review
        )
      )
    }

    if !denied.isEmpty {
      steps.append(
        Step(
          id: "keepCorrections",
          label:
            "Keep \(countLabel(denied.count, singular: "correction", plural: "corrections")) visible",
          detail: "These protect future runs from repeating known-bad reasoning.",
          systemImageName: "xmark.circle",
          tone: .correction
        )
      )
    }

    if !affirmed.isEmpty {
      steps.append(
        Step(
          id: "reuseGuidance",
          label:
            "Reuse \(countLabel(affirmed.count, singular: "confirmed fact", plural: "confirmed facts"))",
          detail: "These are strong signals for planning, implementation, and review prompts.",
          systemImageName: "checkmark.circle",
          tone: .steady
        )
      )
    }

    if steps.isEmpty {
      steps.append(
        Step(
          id: "waitForSignals",
          label: "No review needed",
          detail: "Compass will add entries here when a run relies on a durable guess.",
          systemImageName: "sparkle.magnifyingglass",
          tone: .empty
        )
      )
    }

    return steps
  }

  private static func queueDetail(for record: AssumptionRecord) -> String {
    var parts = [record.scope.displayName]
    if let session = record.createdInSession {
      parts.append("session \(session)")
    }
    if !record.impact.isEmpty {
      parts.append(record.impact)
    } else if !record.rationale.isEmpty {
      parts.append(record.rationale)
    }
    return StringUtils.boundedText(parts.joined(separator: " - "), limit: 220)
  }

  private static func narrationIdentifier(
    title: String,
    detail: String,
    promptEffect: String,
    tone: Tone,
    active: [AssumptionRecord],
    steps: [Step],
    queue: [QueueItem]
  ) -> String {
    let raw = [
      "title:\(title)",
      "detail:\(detail)",
      "prompt:\(promptEffect)",
      "tone:\(tone.rawValue)",
      "active:\(active.map { "\($0.id):\($0.status.rawValue):\($0.updatedAt)" }.joined(separator: ","))",
      "steps:\(steps.map(\.id).joined(separator: ","))",
      "queue:\(queue.map(\.id).joined(separator: ","))",
    ].joined(separator: "|")
    return StringUtils.boundedText(raw, limit: 1_200)
  }

  private static func countLabel(_ count: Int, singular: String, plural: String) -> String {
    "\(count) \(count == 1 ? singular : plural)"
  }
}
