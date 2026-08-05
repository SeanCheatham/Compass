import Foundation

public struct PlanSessionHistoryGuide: Equatable, Sendable {
  public static let detailLimit = 260

  public enum Tone: String, Equatable, Sendable {
    case empty
    case steady
    case active
    case attention
  }

  public struct Fact: Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var detail: String
    public var systemImageName: String
  }

  public struct AuditCoverage: Equatable, Sendable {
    public var coveredCount: Int
    public var totalCount: Int
    public var fraction: Double
    public var label: String
    public var detail: String
    public var missingLabels: [String]
  }

  public var title: String
  public var detail: String
  public var statusLabel: String
  public var tone: Tone
  public var systemImageName: String
  public var facts: [Fact]
  public var auditCoverage: AuditCoverage

  public init(
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
    auditCoverage = Self.auditCoverage(for: visibleItems.first)
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

    if let latest = visibleItems.first, !latest.auditArtifacts.isEmpty {
      let firstArtifact = latest.auditArtifacts[0]
      facts.append(
        Fact(
          id: "artifacts",
          label: countLabel(
            latest.auditArtifacts.count,
            singular: "audit artifact",
            plural: "audit artifacts"
          ),
          detail: "\(firstArtifact.label) is saved with the session audit manifest.",
          systemImageName: "archivebox"
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

  private static func auditCoverage(for latest: PlanSessionHistoryItem?) -> AuditCoverage {
    guard let latest else {
      return AuditCoverage(
        coveredCount: 0,
        totalCount: 4,
        fraction: 0,
        label: "No visible audit",
        detail: "Run History has no visible run to audit yet.",
        missingLabels: ["Plan", "Verify", "Runtime route", "Result"]
      )
    }

    let anchors: [(label: String, isCovered: Bool)] = [
      ("Plan", latest.handoffDigest.status != .missingPlan),
      ("Verify", latest.verifyCommand != nil || latest.failedVerify != nil),
      (
        "Runtime route",
        latest.runtimeRouteDescriptor.isSnapshotAvailable || latest.runtimeRouteSummary != nil
      ),
      (
        "Result",
        latest.status == .succeeded || latest.status == .failed || latest.failedVerify != nil
          || !latest.commits.isEmpty || !latest.notes.isEmpty || latest.feedback != nil
      ),
    ]

    let coveredCount = anchors.filter { $0.isCovered }.count
    let totalCount = anchors.count
    let missingLabels = anchors.filter { !$0.isCovered }.map(\.label)
    let label =
      coveredCount == totalCount
      ? "Audit trail complete"
      : "\(coveredCount) of \(totalCount) audit anchors"
    let detail =
      missingLabels.isEmpty
      ? "Latest run includes plan, verify proof, runtime route, and result."
      : "Latest run is missing: \(missingLabels.joined(separator: ", "))."

    return AuditCoverage(
      coveredCount: coveredCount,
      totalCount: totalCount,
      fraction: totalCount == 0 ? 0 : Double(coveredCount) / Double(totalCount),
      label: label,
      detail: bounded(detail, limit: 180),
      missingLabels: missingLabels
    )
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

  private static func countLabel(_ count: Int, singular: String, plural: String) -> String {
    "\(count) \(count == 1 ? singular : plural)"
  }

  private static func bounded(_ text: String, limit: Int = detailLimit) -> String {
    StringUtils.boundedText(text, limit: limit)
  }
}
