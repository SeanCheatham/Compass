import Foundation

struct AssumptionReviewGuide: Equatable, Sendable {
  static let reviewCommentPlaceholder = "Correction or reason before Deny or Archive"

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

  struct ReviewProgress: Equatable, Sendable {
    static let labelLimit = 48
    static let detailLimit = 180

    var reviewedCount: Int
    var activeCount: Int
    var fraction: Double
    var label: String
    var detail: String
  }

  struct PromptLane: Equatable, Sendable {
    static let labelLimit = 56
    static let detailLimit = 220

    var label: String
    var detail: String
  }

  var title: String
  var detail: String
  var promptEffect: String
  var tone: Tone
  var reviewProgress: ReviewProgress
  var promptLane: PromptLane
  var steps: [Step]
  var queue: [QueueItem]
  var narrationIdentifier: String

  init(ledger: AssumptionLedger) {
    let active = ledger.activeAssumptions
    let implicit = Self.records(status: .implicit, in: active)
    let affirmed = Self.records(status: .affirmed, in: active)
    let denied = Self.records(status: .denied, in: active)
    let archivedCount = ledger.archivedCount

    if active.isEmpty && archivedCount > 0 {
      let archivedVerb = archivedCount == 1 ? "is" : "are"
      let archivedSteeringVerb = archivedCount == 1 ? "does not" : "do not"
      title = "All Assumptions Archived"
      detail =
        "\(Self.countLabel(archivedCount, singular: "archived assumption", plural: "archived assumptions")) \(archivedVerb) kept in history and \(archivedSteeringVerb) steer future runs."
      promptEffect = "Future prompts are not receiving active assumption guidance."
      tone = .empty
    } else if active.isEmpty {
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

    reviewProgress = Self.reviewProgress(
      implicitCount: implicit.count,
      affirmedCount: affirmed.count,
      deniedCount: denied.count,
      archivedCount: archivedCount
    )
    promptLane = Self.promptLane(
      implicitCount: implicit.count,
      affirmedCount: affirmed.count,
      deniedCount: denied.count,
      archivedCount: archivedCount
    )
    steps = Self.steps(
      implicit: implicit,
      affirmed: affirmed,
      denied: denied,
      archivedCount: archivedCount
    )
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
      reviewProgress: reviewProgress,
      promptLane: promptLane,
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
    denied: [AssumptionRecord],
    archivedCount: Int
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

    if steps.isEmpty && archivedCount > 0 {
      steps.append(
        Step(
          id: "archivedOnly",
          label: "No active guidance",
          detail: "Archived assumptions stay in history and are excluded from agent prompts.",
          systemImageName: "archivebox",
          tone: .empty
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

  private static func reviewProgress(
    implicitCount: Int,
    affirmedCount: Int,
    deniedCount: Int,
    archivedCount: Int
  ) -> ReviewProgress {
    let activeCount = implicitCount + affirmedCount + deniedCount
    let reviewedCount = affirmedCount + deniedCount

    if activeCount == 0 {
      let detail =
        archivedCount > 0
        ? "Archived assumptions are preserved in history and excluded from active prompts."
        : "Compass has not recorded active assumption memory yet."
      return ReviewProgress(
        reviewedCount: 0,
        activeCount: 0,
        fraction: 1,
        label: "No active memory",
        detail: StringUtils.boundedText(detail, limit: ReviewProgress.detailLimit)
      )
    }

    if implicitCount == 0 {
      return ReviewProgress(
        reviewedCount: reviewedCount,
        activeCount: activeCount,
        fraction: 1,
        label: StringUtils.boundedText(
          "All \(activeCount) active reviewed",
          limit: ReviewProgress.labelLimit
        ),
        detail: "Every active assumption is affirmed or corrected for future prompts."
      )
    }

    let label = "\(reviewedCount) of \(activeCount) active reviewed"
    let detail =
      "\(countLabel(implicitCount, singular: "guess", plural: "guesses")) still need a yes-or-no check."
    return ReviewProgress(
      reviewedCount: reviewedCount,
      activeCount: activeCount,
      fraction: Double(reviewedCount) / Double(activeCount),
      label: StringUtils.boundedText(label, limit: ReviewProgress.labelLimit),
      detail: StringUtils.boundedText(detail, limit: ReviewProgress.detailLimit)
    )
  }

  private static func promptLane(
    implicitCount: Int,
    affirmedCount: Int,
    deniedCount: Int,
    archivedCount: Int
  ) -> PromptLane {
    let activeCount = implicitCount + affirmedCount + deniedCount
    guard activeCount > 0 else {
      let detail =
        archivedCount > 0
        ? "Archived assumptions stay in history, but no assumptions are injected into future prompts."
        : "No assumptions are injected into future prompts yet."
      return PromptLane(
        label: "No active prompt signals",
        detail: StringUtils.boundedText(detail, limit: PromptLane.detailLimit)
      )
    }

    var lanes: [String] = []
    if affirmedCount > 0 {
      lanes.append(
        countLabel(
          affirmedCount,
          singular: "strong guidance item",
          plural: "strong guidance items"
        )
      )
    }
    if implicitCount > 0 {
      lanes.append(countLabel(implicitCount, singular: "tentative guess", plural: "tentative guesses"))
    }
    if deniedCount > 0 {
      lanes.append(countLabel(deniedCount, singular: "correction", plural: "corrections"))
    }

    let reviewSuffix =
      implicitCount > 0
      ? " Review tentative guesses before load-bearing work."
      : ""
    return PromptLane(
      label: StringUtils.boundedText(
        countLabel(
          activeCount,
          singular: "active prompt signal",
          plural: "active prompt signals"
        ),
        limit: PromptLane.labelLimit
      ),
      detail: StringUtils.boundedText(
        "Prompts carry \(joinedList(lanes)).\(reviewSuffix)",
        limit: PromptLane.detailLimit
      )
    )
  }

  private static func narrationIdentifier(
    title: String,
    detail: String,
    promptEffect: String,
    tone: Tone,
    reviewProgress: ReviewProgress,
    promptLane: PromptLane,
    active: [AssumptionRecord],
    steps: [Step],
    queue: [QueueItem]
  ) -> String {
    let raw = [
      "title:\(title)",
      "detail:\(detail)",
      "prompt:\(promptEffect)",
      "lane:\(promptLane.label):\(promptLane.detail)",
      "tone:\(tone.rawValue)",
      "progress:\(reviewProgress.label):\(reviewProgress.reviewedCount)/\(reviewProgress.activeCount)",
      "active:\(active.map { "\($0.id):\($0.status.rawValue):\($0.updatedAt)" }.joined(separator: ","))",
      "steps:\(steps.map(\.id).joined(separator: ","))",
      "queue:\(queue.map(\.id).joined(separator: ","))",
    ].joined(separator: "|")
    return StringUtils.boundedText(raw, limit: 1_200)
  }

  private static func countLabel(_ count: Int, singular: String, plural: String) -> String {
    "\(count) \(count == 1 ? singular : plural)"
  }

  private static func joinedList(_ values: [String]) -> String {
    switch values.count {
    case 0:
      return "no active assumptions"
    case 1:
      return values[0]
    case 2:
      return values.joined(separator: " and ")
    default:
      return values.dropLast().joined(separator: ", ") + ", and \(values.last ?? "")"
    }
  }
}

struct AssumptionReviewClipboardPayload: Equatable, Sendable {
  static let textLimit = 4_000
  private static let bucketRecordLimit = 6
  private static let evidenceLimit = 3

  var text: String

  init(ledger: AssumptionLedger, guide: AssumptionReviewGuide) {
    guard !ledger.assumptions.isEmpty else {
      text = ""
      return
    }

    let active = ledger.activeAssumptions
    var sections: [String] = [
      "Compass Assumptions Handoff",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded, user-reviewable assumption memory. Do not invent "
        + "files, credentials, product intent, user preferences, or extra decisions.",
      "- Affirmed assumptions are strong guidance. Implicit assumptions need verification "
        + "or a user check before load-bearing work.",
      "- Denied assumptions are corrections; do not rely on them, and repair any work that "
        + "depends on them.",
      "",
      "Status: \(guide.title)",
      "Detail: \(guide.detail)",
      "Prompt effect: \(guide.promptEffect)",
      "Prompt lane: \(guide.promptLane.label) - \(guide.promptLane.detail)",
      "Review progress: \(guide.reviewProgress.label) - \(guide.reviewProgress.detail)",
      "Counts: \(ledger.implicitCount) implicit, \(ledger.affirmedCount) affirmed, "
        + "\(ledger.deniedCount) denied, \(ledger.archivedCount) archived",
    ]

    if !guide.queue.isEmpty {
      sections.append("")
      sections.append("Needs review first:")
      for item in guide.queue {
        sections.append("- \(item.label)")
        sections.append("  Context: \(item.detail)")
      }
    }

    Self.appendBucket(
      title: "User-affirmed assumptions (strong guidance)",
      records: Self.records(status: .affirmed, in: active),
      to: &sections
    )
    Self.appendBucket(
      title: "Implicit assumptions (verify before relying)",
      records: Self.records(status: .implicit, in: active),
      to: &sections
    )
    Self.appendBucket(
      title: "Denied assumptions (corrections; do not rely)",
      records: Self.records(status: .denied, in: active),
      to: &sections
    )

    if ledger.archivedCount > 0 {
      sections.append("")
      sections.append("Archived assumptions: \(ledger.archivedCount)")
      sections.append("Archived entries are preserved in history but excluded from active prompts.")
    }

    text = AssumptionReviewClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

  private static func appendBucket(
    title: String,
    records: [AssumptionRecord],
    to sections: inout [String]
  ) {
    guard !records.isEmpty else { return }

    sections.append("")
    sections.append(title)
    for record in records.prefix(bucketRecordLimit) {
      sections.append("- [\(record.id)] \(singleLine(record.text))")
      sections.append("  Scope: \(record.scope.displayName)\(sessionSuffix(for: record))")
      appendDetail("Impact", record.impact, to: &sections)
      appendDetail("Rationale", record.rationale, to: &sections)
      appendDetail("Invalidated by", record.invalidation, to: &sections)
      appendDetail("User comment", record.userComment ?? "", to: &sections)
      if !record.evidence.isEmpty {
        sections.append("  Evidence:")
        for item in record.evidence.prefix(evidenceLimit) {
          sections.append("    - \(singleLine(item))")
        }
        if record.evidence.count > evidenceLimit {
          sections.append(
            "    - ...\(record.evidence.count - evidenceLimit) more evidence items not shown")
        }
      }
    }

    if records.count > bucketRecordLimit {
      sections.append("- ...\(records.count - bucketRecordLimit) more assumptions not shown")
    }
  }

  private static func appendDetail(_ label: String, _ value: String, to sections: inout [String]) {
    let bounded = singleLine(value)
    guard !bounded.isEmpty else { return }
    sections.append("  \(label): \(bounded)")
  }

  private static func sessionSuffix(for record: AssumptionRecord) -> String {
    guard let session = record.createdInSession else { return "" }
    return ", session #\(session)"
  }

  private static func singleLine(_ text: String) -> String {
    StringUtils.boundedText(text, limit: 320)
  }
}

private enum AssumptionReviewClipboardText {
  static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
