import Foundation

struct PlanSessionHistoryGuide: Equatable, Sendable {
  static let detailLimit = 260
  static let identifierLimit = 1_400

  enum Tone: String, Equatable, Sendable {
    case empty
    case steady
    case active
    case attention
  }

  struct Fact: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var detail: String
    var systemImageName: String
  }

  var title: String
  var detail: String
  var statusLabel: String
  var tone: Tone
  var systemImageName: String
  var facts: [Fact]
  var narrationIdentifier: String

  var allowsNarration: Bool {
    tone != .empty && !facts.isEmpty
  }

  init(
    display: PlanSessionHistoryDisplay,
    runCues: [Int: PlanReliabilityFeedback.RunCue] = [:]
  ) {
    let visibleItems = display.visibleItems
    let visibleRunCues = visibleItems.compactMap { runCues[$0.sessionNumber] }
    let attentionCount = visibleRunCues.count
    let activeCount = visibleItems.filter(Self.isActive).count
    let failedCount = visibleItems.filter { Self.needsFailureReview($0, runCues: runCues) }.count

    if display.unfilteredTotalCount == 0 {
      title = "No Runs Yet"
      detail =
        "Run History will become Compass's audit trail: plan, proof, route, notes, and commits appear here after the first run."
      statusLabel = "0 runs"
      tone = .empty
      systemImageName = "clock.arrow.circlepath"
    } else if visibleItems.isEmpty {
      title = "Filter Hides Runs"
      detail =
        "There are \(Self.countLabel(display.unfilteredTotalCount, singular: "run", plural: "runs")), but none match \(display.filter.title). Change the filter to inspect the audit trail."
      statusLabel = display.countSummary
      tone = .empty
      systemImageName = "line.3.horizontal.decrease.circle"
    } else if attentionCount > 0 {
      title = "Start With Attention"
      detail =
        "\(Self.countLabel(attentionCount, singular: "visible cue", plural: "visible cues")) need review. Open the newest cue before trusting older successes."
      statusLabel = display.countSummary
      tone = .attention
      systemImageName = "exclamationmark.triangle.fill"
    } else if activeCount > 0 {
      title = "Run Still Open"
      detail =
        "\(Self.countLabel(activeCount, singular: "visible run", plural: "visible runs")) are still planning, developing, or waiting for approval. Treat summaries as provisional until the run finishes."
      statusLabel = display.countSummary
      tone = .active
      systemImageName = "playpause.circle.fill"
    } else if visibleItems.first?.status == .succeeded {
      title = "Latest Run Succeeded"
      detail =
        "The newest visible run succeeded. Outcome, verification, commits, and route details stay here so you can audit before continuing."
      statusLabel = display.countSummary
      tone = .steady
      systemImageName = "checkmark.circle.fill"
    } else if failedCount > 0 {
      title = "Review The Failed Run"
      detail =
        "\(Self.countLabel(failedCount, singular: "visible failed run", plural: "visible failed runs")) remain in view. Start from the captured verify output or handoff detail."
      statusLabel = display.countSummary
      tone = .attention
      systemImageName = "xmark.octagon.fill"
    } else {
      title = "History Ready For Audit"
      detail =
        "The visible runs are finished and preserved. Use the handoff, verify command, and route badges to decide what to trust next."
      statusLabel = display.countSummary
      tone = .steady
      systemImageName = "text.magnifyingglass"
    }

    detail = Self.bounded(detail)
    facts = Self.facts(
      display: display,
      visibleItems: visibleItems,
      visibleRunCues: visibleRunCues,
      runCues: runCues
    )
    narrationIdentifier = Self.narrationIdentifier(
      title: title,
      detail: detail,
      statusLabel: statusLabel,
      tone: tone,
      facts: facts
    )
  }

  private static func facts(
    display: PlanSessionHistoryDisplay,
    visibleItems: [PlanSessionHistoryItem],
    visibleRunCues: [PlanReliabilityFeedback.RunCue],
    runCues: [Int: PlanReliabilityFeedback.RunCue]
  ) -> [Fact] {
    guard !visibleItems.isEmpty else {
      if display.unfilteredTotalCount == 0 {
        return [
          Fact(
            id: "auditTrail",
            label: "Audit trail",
            detail: "Plan, Develop, Verify, and commits will appear here.",
            systemImageName: "list.bullet.clipboard"
          )
        ]
      }

      return [
        Fact(
          id: "filter",
          label: display.filter.title,
          detail: "No visible runs match this filter.",
          systemImageName: display.filter.systemImage
        )
      ]
    }

    var facts: [Fact] = [
      Fact(
        id: "visible",
        label: display.countSummary,
        detail: display.mode == .all
          ? "Showing the full selected history." : "Showing recent runs first.",
        systemImageName: "number"
      )
    ]

    if let latest = visibleItems.first {
      facts.append(
        Fact(
          id: "latest",
          label: "Latest #\(latest.sessionNumber): \(latest.statusText)",
          detail: latestPrimaryDetail(latest),
          systemImageName: statusSystemImage(for: latest.status)
        )
      )
    }

    if let cue = visibleRunCues.first {
      facts.append(
        Fact(
          id: "attention",
          label: "Attention: \(cue.label)",
          detail: cue.detail,
          systemImageName: cue.systemImage
        )
      )
    }

    if let verify = visibleItems.first(where: { $0.verifyCommand != nil })?.verifyCommand {
      let summary = PlanVerifyCommandSummary(command: verify)
      facts.append(
        Fact(
          id: "proof",
          label: summary.title,
          detail: summary.detail,
          systemImageName: summary.systemImage
        )
      )
    }

    let commitCount = visibleItems.reduce(0) { $0 + $1.commits.count }
    if commitCount > 0 {
      facts.append(
        Fact(
          id: "commits",
          label: countLabel(commitCount, singular: "commit", plural: "commits"),
          detail: "Explore can open file changes, architecture, and Q&A for shipped commits.",
          systemImageName: "arrow.triangle.branch"
        )
      )
    }

    if display.hiddenCount > 0 {
      facts.append(
        Fact(
          id: "hidden",
          label: "\(display.hiddenCount) older hidden",
          detail: display.hiddenStatusSummary ?? "Switch to Show All to inspect older runs.",
          systemImageName: "archivebox"
        )
      )
    }

    return Array(facts.prefix(5)).map { fact in
      Fact(
        id: fact.id,
        label: bounded(fact.label, limit: 90),
        detail: bounded(fact.detail, limit: 180),
        systemImageName: fact.systemImageName
      )
    }
  }

  private static func latestPrimaryDetail(_ item: PlanSessionHistoryItem) -> String {
    if let cueDetail = item.failedVerify?.tail {
      return bounded(cueDetail, limit: 180)
    }
    if let outcome = item.handoffDigest.outcome {
      return outcome
    }
    if let excerpt = item.planExcerpt {
      return excerpt
    }
    return item.handoffDigest.detail
  }

  private static func isActive(_ item: PlanSessionHistoryItem) -> Bool {
    item.status == .planning
      || item.status == .developing
      || item.status == .awaitingApproval
  }

  private static func needsFailureReview(
    _ item: PlanSessionHistoryItem,
    runCues: [Int: PlanReliabilityFeedback.RunCue]
  ) -> Bool {
    if item.status == .failed || item.status == .rejectedByPlan {
      return true
    }

    switch runCues[item.sessionNumber]?.kind {
    case .rejectedPlan, .developFailed, .failedVerify, .dirtyWorktree, .promotionFailed:
      return true
    case .developBlocked, .resumeDevelop, nil:
      return false
    }
  }

  private static func statusSystemImage(for status: SessionStatus) -> String {
    switch status {
    case .planning:
      return "map"
    case .awaitingApproval:
      return "pause.circle"
    case .developing:
      return "hammer"
    case .succeeded:
      return "checkmark.circle"
    case .failed:
      return "xmark.octagon"
    case .cancelled:
      return "stop.circle"
    case .rejectedByPlan:
      return "exclamationmark.triangle"
    case .skipped:
      return "forward.end.circle"
    }
  }

  private static func narrationIdentifier(
    title: String,
    detail: String,
    statusLabel: String,
    tone: Tone,
    facts: [Fact]
  ) -> String {
    let raw = [
      "title:\(title)",
      "detail:\(detail)",
      "status:\(statusLabel)",
      "tone:\(tone.rawValue)",
      "facts:\(facts.map { "\($0.id):\($0.label):\($0.detail)" }.joined(separator: "|"))",
    ].joined(separator: "\n")
    return StringUtils.boundedText(raw, limit: identifierLimit)
  }

  private static func countLabel(_ count: Int, singular: String, plural: String) -> String {
    "\(count) \(count == 1 ? singular : plural)"
  }

  private static func bounded(_ text: String, limit: Int = detailLimit) -> String {
    StringUtils.boundedText(text, limit: limit)
  }
}

struct PlanSessionHistoryGuideNarration: Equatable, Sendable {
  var guideIdentifier: String
  var text: String
}

enum PlanSessionHistoryGuideNarrator {
  static let maxCharacters = 360

  static func narrate(
    guide: PlanSessionHistoryGuide
  ) async -> PlanSessionHistoryGuideNarration? {
    guard guide.allowsNarration else { return nil }
    guard FoundationModelsAvailability.isAvailable else { return nil }

    if #available(macOS 26.0, *) {
      guard
        let generated = await FoundationModelsAvailability._streamText(
          prompt: prompt(for: guide)
        )
      else {
        return nil
      }
      let text = sanitized(generated)
      guard !text.isEmpty else { return nil }
      return PlanSessionHistoryGuideNarration(
        guideIdentifier: guide.narrationIdentifier,
        text: text
      )
    }

    return nil
  }

  static func prompt(for guide: PlanSessionHistoryGuide) -> String {
    """
    You are Compass explaining Run History to a non-engineer.
    Use only the facts below. Do not invent files, commands, outcomes, errors, or next steps.
    Return one calm paragraph under 50 words. No Markdown.

    Title: \(guide.title)
    Detail: \(guide.detail)
    Badge: \(guide.statusLabel)
    Tone: \(guide.tone.rawValue)
    Facts: \(guide.facts.map { "\($0.label) - \($0.detail)" }.joined(separator: " | "))
    """
  }

  private static func sanitized(_ text: String) -> String {
    let normalized = StringUtils.boundedText(
      text
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " "),
      limit: maxCharacters
    )
    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))

    guard
      !normalized.contains("{"),
      !normalized.contains("}"),
      !normalized.contains("```"),
      !normalized.hasPrefix("- "),
      !normalized.hasPrefix("* "),
      !normalized.lowercased().contains("http://"),
      !normalized.lowercased().contains("https://")
    else {
      return ""
    }

    return normalized
  }
}
