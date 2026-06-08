import Foundation

struct TournamentAutomationProofTargetDebtMovement: Equatable, Sendable, Identifiable {
  var id: String { auditID }

  var auditID: String
  var endedAt: Double
  var executedStepIDs: [String]
  var evidenceRunIDs: [String]
  var startingProofDebtCount: Int
  var endingProofDebtCount: Int
  var startingProofDebtSummary: String?
  var endingProofDebtSummary: String?
  var userMessage: String

  var proofDebtDelta: Int {
    endingProofDebtCount - startingProofDebtCount
  }

  var startCountLabel: String {
    "\(startingProofDebtCount)"
  }

  var endCountLabel: String {
    "\(endingProofDebtCount)"
  }

  var deltaLabel: String {
    signedDelta
  }

  var movementLabel: String {
    if proofDebtDelta < 0 {
      return "Cleared \(abs(proofDebtDelta))"
    }
    if proofDebtDelta > 0 {
      return "Added \(proofDebtDelta)"
    }
    return "Unchanged"
  }

  var movementDetail: String {
    if proofDebtDelta < 0 {
      return "cleared \(abs(proofDebtDelta)) proof debt"
    }
    if proofDebtDelta > 0 {
      return "added \(proofDebtDelta) proof debt"
    }
    return "left proof debt unchanged"
  }

  var postResultStateSummary: String {
    if endingProofDebtCount == 0 {
      return "Proof debt clear"
    }
    if proofDebtDelta < 0 {
      return "Proof debt reduced"
    }
    if proofDebtDelta > 0 {
      return "Proof debt increased"
    }
    return "Proof debt unchanged"
  }

  var movementSystemImage: String {
    if proofDebtDelta < 0 {
      return "arrow.down.circle"
    }
    if proofDebtDelta > 0 {
      return "arrow.up.circle"
    }
    return "equal.circle"
  }

  var resultStripSummary: String {
    "Proof movement \(startCountLabel) -> \(endCountLabel) (\(deltaLabel)); \(movementDetail)"
  }

  init?(audit: TournamentAutomationCycleAudit) {
    guard
      let startingProofDebtCount = audit.startingProofDebtCount,
      let endingProofDebtCount = audit.endingProofDebtCount
    else { return nil }

    self.auditID = audit.id
    self.endedAt = audit.endedAt
    self.executedStepIDs = audit.executedStepIDs
    self.evidenceRunIDs = audit.evidenceRunIDs
    self.startingProofDebtCount = startingProofDebtCount
    self.endingProofDebtCount = endingProofDebtCount
    self.startingProofDebtSummary = audit.startingProofDebtSummary
    self.endingProofDebtSummary = audit.endingProofDebtSummary
    self.userMessage = audit.userMessage
  }

  var displaySummary: String {
    if proofDebtDelta < 0 {
      return
        "Latest audit cleared \(abs(proofDebtDelta)) proof debt (\(startingProofDebtCount) -> \(endingProofDebtCount))"
    }
    if proofDebtDelta > 0 {
      return
        "Latest audit added \(proofDebtDelta) proof debt (\(startingProofDebtCount) -> \(endingProofDebtCount))"
    }
    return
      "Latest audit left proof debt unchanged (\(startingProofDebtCount) -> \(endingProofDebtCount))"
  }

  var lastRunSummary: String {
    if proofDebtDelta < 0 {
      return "Last run cleared \(abs(proofDebtDelta)) proof debt"
    }
    if proofDebtDelta > 0 {
      return "Last run added \(proofDebtDelta) proof debt"
    }
    return "Last run left proof debt unchanged"
  }

  var lastRunContextSummary: String {
    if proofDebtDelta < 0 {
      return "cleared \(abs(proofDebtDelta)) proof debt"
    }
    if proofDebtDelta > 0 {
      return "added \(proofDebtDelta) proof debt"
    }
    return "left proof debt unchanged"
  }

  var contextSummary: String {
    var parts = [
      "latest_audit \(StringUtils.boundedText(auditID, limit: 80))",
      "proof_debt \(startingProofDebtCount) -> \(endingProofDebtCount) (\(signedDelta))",
    ]
    if !evidenceRunIDs.isEmpty {
      parts.append("evidence \(evidenceRunIDs.prefix(3).joined(separator: ", "))")
    }
    return parts.joined(separator: "; ")
  }

  var helpSummary: String {
    var parts = [
      displaySummary,
      "Audit \(auditID)",
    ]
    if !executedStepIDs.isEmpty {
      parts.append("Steps \(executedStepIDs.prefix(3).joined(separator: ", "))")
    }
    if !evidenceRunIDs.isEmpty {
      parts.append("Evidence \(evidenceRunIDs.prefix(4).joined(separator: ", "))")
    }
    if let startingProofDebtSummary {
      parts.append("Starting: \(StringUtils.boundedText(startingProofDebtSummary, limit: 260))")
    }
    if let endingProofDebtSummary {
      parts.append("Ending: \(StringUtils.boundedText(endingProofDebtSummary, limit: 260))")
    }
    parts.append(StringUtils.boundedText(userMessage, limit: 260))
    return parts.joined(separator: "\n")
  }

  private var signedDelta: String {
    proofDebtDelta > 0 ? "+\(proofDebtDelta)" : "\(proofDebtDelta)"
  }
}

struct TournamentAutomationProofTargetFocus: Equatable, Sendable {
  var row: TournamentAutomationProofTargetScoreboardRow
  var auditID: String
  var evidenceRunID: String?
  var planEvaluationID: String?
}

struct TournamentAutomationProofTargetScoreboardReadinessGroup: Equatable, Sendable, Identifiable {
  var id: String { bucket }

  var bucket: String
  var rows: [TournamentAutomationProofTargetScoreboardRow]
  var totalCount: Int? = nil

  var count: Int { totalCount ?? rows.count }

  var displaySummary: String {
    "\(bucket) \(count)"
  }

  var accessibilitySuffix: String {
    bucket.lowercased().replacingOccurrences(of: " ", with: "-")
  }

  var primaryRow: TournamentAutomationProofTargetScoreboardRow? {
    rows.first
  }

  var primaryActionRow: TournamentAutomationProofTargetScoreboardRow? {
    rows.first { $0.nextStep?.canExecute == true }
  }

  var primaryActionStep: TournamentAutomationStep? {
    primaryActionRow?.nextStep
  }

  var actionButtonTitle: String {
    guard let primaryActionStep else { return "Select" }
    switch primaryActionStep.kind {
    case .applyDecision:
      return "Apply Decision"
    case .applyRoundTransition:
      return "Apply Transition"
    case .applyRevision:
      return "Apply Revision"
    case .prepareWorktree:
      return "Prepare Worktree"
    case .runPlanProof, .runCohort:
      return "Run Proof"
    case .blocked:
      return "Select"
    }
  }

  var actionSystemImage: String {
    primaryActionRow?.nextStepSystemImage ?? "scope"
  }

  var actionHelpSummary: String {
    if let primaryActionRow {
      return [
        "\(bucket): \(primaryActionRow.contenderTitle)",
        primaryActionRow.nextStepSummary,
        primaryActionRow.nextStepDetail,
      ].joined(separator: "\n")
    }
    if let primaryRow {
      return "Select \(primaryRow.contenderTitle) to inspect \(bucket.lowercased())."
    }
    return "No targets in \(bucket.lowercased())."
  }

  var actionContextSummary: String {
    if let primaryActionRow {
      return [
        "\(bucket) \(StringUtils.boundedText(primaryActionRow.contenderTitle, limit: 80))",
        StringUtils.boundedText(primaryActionRow.nextStepSummary, limit: 120),
      ].joined(separator: ": ")
    }
    if let primaryRow {
      return [
        "\(bucket) \(StringUtils.boundedText(primaryRow.contenderTitle, limit: 80))",
        "select \(StringUtils.boundedText(primaryRow.nextStatusLabel, limit: 80))",
      ].joined(separator: ": ")
    }
    return "\(bucket): none"
  }

  func actionAuditSummary(
    anchorRow: TournamentAutomationProofTargetScoreboardRow? = nil
  ) -> String {
    guard let row = anchorRow ?? primaryActionRow ?? primaryRow else {
      return "pressure_group \(bucket); anchor none"
    }
    return [
      "pressure_group \(bucket)",
      "anchor \(StringUtils.boundedText(row.selectionID, limit: 220))",
      "contender \(StringUtils.boundedText(row.contenderTitle, limit: 80))",
      "status \(StringUtils.boundedText(row.nextStatusLabel, limit: 80))",
      "next \(StringUtils.boundedText(row.nextStepSummary, limit: 120))",
    ].joined(separator: "; ")
  }

  var latestMovementRow: TournamentAutomationProofTargetScoreboardRow? {
    rows
      .compactMap {
        row -> (
          row: TournamentAutomationProofTargetScoreboardRow,
          movement: TournamentAutomationProofTargetDebtMovement
        )? in
        guard let movement = row.latestDebtMovement else { return nil }
        return (row, movement)
      }
      .sorted { lhs, rhs in
        if lhs.movement.endedAt != rhs.movement.endedAt {
          return lhs.movement.endedAt > rhs.movement.endedAt
        }
        return lhs.row.scoreboardSortsBefore(rhs.row)
      }
      .first?
      .row
  }

  var latestMovement: TournamentAutomationProofTargetDebtMovement? {
    latestMovementRow?.latestDebtMovement
  }

  var latestMovementSummary: String {
    guard let latestMovementRow, let latestMovement else {
      return "No group proof movement yet"
    }
    return
      "\(latestMovementRow.contenderTitle): \(latestMovement.movementLabel) proof debt \(latestMovement.startCountLabel) -> \(latestMovement.endCountLabel)"
  }

  var latestMovementStatusLabel: String {
    latestMovement?.postResultStateSummary ?? "No movement"
  }

  var latestMovementSystemImage: String {
    latestMovement?.movementSystemImage ?? "circle.dashed"
  }

  var latestMovementHelpSummary: String {
    guard let latestMovementRow, let latestMovement else {
      return "No audited proof movement for \(bucket.lowercased()) yet."
    }
    return [
      "\(bucket): \(latestMovementRow.contenderTitle)",
      latestMovement.helpSummary,
      "Current next step: \(latestMovementRow.nextStepSummary)",
    ].joined(separator: "\n")
  }

  var latestMovementContextSummary: String {
    guard let latestMovementRow, let latestMovement else {
      return "\(bucket): latest_result none"
    }
    return [
      "\(bucket) \(StringUtils.boundedText(latestMovementRow.contenderTitle, limit: 80))",
      "latest_result \(latestMovement.lastRunContextSummary)",
      "audit \(StringUtils.boundedText(latestMovement.auditID, limit: 80))",
      "proof_debt \(latestMovement.startingProofDebtCount) -> \(latestMovement.endingProofDebtCount) (\(latestMovement.deltaLabel))",
      "next \(StringUtils.boundedText(latestMovementRow.nextStepSummary, limit: 120))",
    ].joined(separator: "; ")
  }

  func containsRow(
    selectionID: String?
  ) -> Bool {
    guard let selectionID else { return false }
    return rows.contains { $0.selectionID == selectionID }
  }
}

struct TournamentAutomationProofTargetScoreboardRow: Equatable, Sendable, Identifiable {
  static let nextStatusSummaryBucketOrder = [
    "Ready decisions",
    "Ready transitions",
    "Ready revisions",
    "Prepare worktrees",
    "Proof runs",
    "Blocked",
    "No queued proof",
  ]

  var id: String { selectionID }

  var experimentID: String
  var tournamentID: String?
  var roundID: String?
  var contenderID: String?
  var contenderTitle: String
  var targetLabel: String
  var cohortID: String?
  var targetScenarioID: String?
  var targetPersonaID: String?
  var targetPersonaName: String?
  var targetDecision: ProductTournamentExperimentDecision?
  var readinessScore: Int
  var urgencyScore: Int
  var debtSummary: String
  var nextActionTitle: String?
  var tournamentPositionSummary: String?
  var nextStep: TournamentAutomationStep?
  var latestDebtMovement: TournamentAutomationProofTargetDebtMovement?

  var displaySummary: String {
    var parts = [
      targetLabel,
      "score \(readinessScore)/100",
    ]
    if let nextActionTitle {
      parts.append("next \(nextActionTitle)")
    }
    if let tournamentPositionSummary {
      parts.append(tournamentPositionSummary)
    }
    if let latestDebtMovement {
      parts.append(latestDebtMovement.displaySummary)
    }
    return parts.joined(separator: " - ")
  }

  var contextSummary: String {
    var parts = [
      "contender \(contenderID ?? experimentID)",
      "target \(targetLabel)",
      "score \(readinessScore)/100",
    ]
    if let nextActionTitle {
      parts.append("next \(StringUtils.boundedText(nextActionTitle, limit: 80))")
    }
    if let nextStep {
      let status = nextStep.canExecute ? "ready" : "blocked"
      parts.append("step \(status) \(nextStep.kind.rawValue)")
    }
    parts.append(runPairContextSummary)
    if let latestDebtMovement {
      parts.append(latestDebtMovement.contextSummary)
    } else {
      parts.append("latest_audit none")
    }
    parts.append("debt \(StringUtils.boundedText(debtSummary, limit: 120))")
    if let tournamentPositionSummary {
      parts.append("position \(StringUtils.boundedText(tournamentPositionSummary, limit: 120))")
    }
    return parts.joined(separator: "; ")
  }

  var latestDebtMovementSummary: String {
    latestDebtMovement?.displaySummary ?? "No audited proof-debt movement"
  }

  var firstEvidenceRunID: String? {
    latestDebtMovement?.evidenceRunIDs.first
  }

  var selectionID: String {
    [
      roundID ?? "unknown-round",
      experimentID,
      targetScenarioID ?? cohortID ?? targetPersonaID ?? contenderID ?? targetLabel,
    ].joined(separator: ":")
  }

  var workbenchAccessibilityID: String {
    "proof-target-scoreboard-row-\(selectionID)"
  }

  var runSelectedStepAccessibilityID: String {
    "\(workbenchAccessibilityID)-run-selected-step"
  }

  var proofMovementAccessibilityID: String {
    "\(workbenchAccessibilityID)-proof-movement"
  }

  var nextStatusAccessibilityID: String {
    "\(workbenchAccessibilityID)-next-status"
  }

  var runPairSummary: String {
    "\(lastRunSummary) -> \(nextStepSummary)"
  }

  var runPairContextSummary: String {
    let lastRun =
      latestDebtMovement
      .map {
        "\($0.lastRunContextSummary) audit \(StringUtils.boundedText($0.auditID, limit: 80))"
      }
      ?? "no audited proof run"
    let next = StringUtils.boundedText(nextStepSummary, limit: 140)
    return "run_pair last \(lastRun); next \(next); next_status \(postMovementNextStatusLabel)"
  }

  var helpSummary: String {
    var parts = [
      contenderTitle,
      displaySummary,
      runPairSummary,
      "Debt: \(debtSummary)",
      "Next step: \(nextStepSummary)",
      nextStepDetail,
    ]
    if let latestDebtMovement {
      parts.append(latestDebtMovement.helpSummary)
    }
    return parts.joined(separator: "\n")
  }

  var postMovementNextSummary: String {
    guard let latestDebtMovement else {
      return "No audited proof movement; next \(nextStepSummary)"
    }
    return "\(latestDebtMovement.postResultStateSummary); next \(nextStepSummary)"
  }

  var postMovementNextDetail: String {
    guard let latestDebtMovement else { return nextStepDetail }
    return "\(latestDebtMovement.resultStripSummary). Current next step: \(nextStepDetail) "
      + "Readiness: \(postMovementNextStatusLabel)."
  }

  var postMovementNextStatusLabel: String {
    guard let nextStep else { return "No queued proof" }
    guard nextStep.canExecute else { return "Blocked" }
    switch nextStep.kind {
    case .applyDecision:
      switch nextStep.action.targetDecision {
      case .promote:
        return "Promotion ready"
      case .kill:
        return "Kill ready"
      default:
        return "Decision ready"
      }
    case .applyRoundTransition:
      return "Transition ready"
    case .prepareWorktree:
      return "Prepare worktree"
    case .runPlanProof, .runCohort:
      return "More proof"
    case .applyRevision:
      return "Revision ready"
    case .blocked:
      return "Blocked"
    }
  }

  var postMovementNextStatusSystemImage: String {
    guard let nextStep else { return "checkmark.seal" }
    guard nextStep.canExecute else { return "exclamationmark.triangle" }
    switch nextStep.kind {
    case .applyDecision:
      switch nextStep.action.targetDecision {
      case .promote:
        return "arrow.up.circle"
      case .kill:
        return "xmark.circle"
      default:
        return "checkmark.circle"
      }
    case .applyRoundTransition:
      return "arrow.turn.down.right"
    case .prepareWorktree:
      return "hammer"
    case .runPlanProof, .runCohort:
      return nextStepSystemImage
    case .applyRevision:
      return "wand.and.stars"
    case .blocked:
      return "exclamationmark.triangle"
    }
  }

  var nextStatusLabel: String {
    postMovementNextStatusLabel
  }

  var nextStatusSystemImage: String {
    postMovementNextStatusSystemImage
  }

  var nextStatusSummaryBucket: String {
    guard let nextStep else { return "No queued proof" }
    guard nextStep.canExecute else { return "Blocked" }
    switch nextStep.kind {
    case .applyDecision:
      return "Ready decisions"
    case .applyRoundTransition:
      return "Ready transitions"
    case .applyRevision:
      return "Ready revisions"
    case .prepareWorktree:
      return "Prepare worktrees"
    case .runCohort, .runPlanProof:
      return "Proof runs"
    case .blocked:
      return "Blocked"
    }
  }

  var nextStatusSortPriority: Int {
    guard let nextStep else { return 0 }
    guard nextStep.canExecute else { return 20 }
    switch nextStep.kind {
    case .applyDecision:
      return 100
    case .applyRoundTransition:
      return 90
    case .applyRevision, .prepareWorktree:
      return 80
    case .runCohort, .runPlanProof:
      return 50
    case .blocked:
      return 20
    }
  }

  func scoreboardSortsBefore(_ other: TournamentAutomationProofTargetScoreboardRow) -> Bool {
    if nextStatusSortPriority != other.nextStatusSortPriority {
      return nextStatusSortPriority > other.nextStatusSortPriority
    }
    if urgencyScore != other.urgencyScore {
      return urgencyScore > other.urgencyScore
    }
    if readinessScore != other.readinessScore {
      return readinessScore > other.readinessScore
    }
    return contenderTitle < other.contenderTitle
  }

  private var lastRunSummary: String {
    latestDebtMovement?.lastRunSummary ?? "No audited proof run yet"
  }

  var nextStepSummary: String {
    guard let nextStep else {
      return "No automation step queued"
    }
    let prefix = nextStep.canExecute ? "Ready" : "Blocked"
    return "\(prefix): \(nextStep.queueTitle)"
  }

  var nextStepDetail: String {
    guard let nextStep else { return debtSummary }
    if let blockedReason = nextStep.blockedReason {
      return blockedReason
    }
    return nextStep.detail
  }

  var nextStepSystemImage: String {
    guard let nextStep else { return "questionmark.circle" }
    switch nextStep.kind {
    case .applyDecision:
      return "checkmark.circle"
    case .applyRoundTransition:
      return "arrow.turn.down.right"
    case .prepareWorktree:
      return "hammer"
    case .runPlanProof:
      return "text.badge.checkmark"
    case .runCohort:
      return "play.rectangle.on.rectangle"
    case .applyRevision:
      return "wand.and.stars"
    case .blocked:
      return "exclamationmark.triangle"
    }
  }

  var selectedActionButtonTitle: String {
    guard let nextStep else { return "No Step" }
    switch nextStep.kind {
    case .prepareWorktree:
      return "Prepare Selected Proof"
    case .blocked:
      return "Blocked Proof"
    case .applyDecision, .applyRoundTransition, .runPlanProof, .runCohort, .applyRevision:
      return "Run Selected Proof"
    }
  }
}

struct TournamentAutomationProofTargetScoreboardItem: Equatable, Sendable, Identifiable {
  var id: String { "\(tournamentID ?? "unknown-tournament"):\(roundID ?? "unknown-round")" }

  var tournamentID: String?
  var roundID: String?
  var roundTitle: String
  var contenderCount: Int
  var rows: [TournamentAutomationProofTargetScoreboardRow]

  var targetCount: Int { rows.count }

  var topActionRow: TournamentAutomationProofTargetScoreboardRow? {
    rows
      .filter { $0.nextStep != nil }
      .sorted { $0.scoreboardSortsBefore($1) }
      .first
  }

  var topActionStep: TournamentAutomationStep? {
    topActionRow?.nextStep
  }

  var displayTitle: String {
    roundTitle
  }

  var displaySubtitle: String {
    "\(targetCount)/\(contenderCount) contender proof target(s)"
  }

  var readinessSummaryAccessibilityID: String {
    "\(workbenchAccessibilityID)-readiness-summary"
  }

  var readinessSummaryParts: [String] {
    let parts = readinessGroups.map(\.displaySummary)
    return parts.isEmpty ? ["No proof pressure"] : parts
  }

  var readinessSummary: String {
    readinessSummaryParts.joined(separator: ", ")
  }

  var readinessGroups: [TournamentAutomationProofTargetScoreboardReadinessGroup] {
    guard !rows.isEmpty else { return [] }
    let grouped = Dictionary(grouping: rows, by: \.nextStatusSummaryBucket)
    return TournamentAutomationProofTargetScoreboardRow.nextStatusSummaryBucketOrder
      .compactMap { bucket in
        guard let bucketRows = grouped[bucket], !bucketRows.isEmpty else { return nil }
        return TournamentAutomationProofTargetScoreboardReadinessGroup(
          bucket: bucket,
          rows: bucketRows.sorted { $0.scoreboardSortsBefore($1) }
        )
      }
  }

  func displayReadinessGroups(
    limit: Int = 4
  ) -> [TournamentAutomationProofTargetScoreboardReadinessGroup] {
    guard limit > 0 else { return [] }
    var remaining = limit
    var groups: [TournamentAutomationProofTargetScoreboardReadinessGroup] = []
    for group in readinessGroups {
      guard remaining > 0 else { break }
      let visibleRows = Array(group.rows.prefix(remaining))
      guard !visibleRows.isEmpty else { continue }
      groups.append(
        TournamentAutomationProofTargetScoreboardReadinessGroup(
          bucket: group.bucket,
          rows: visibleRows,
          totalCount: group.count
        )
      )
      remaining -= visibleRows.count
    }
    return groups
  }

  var displayDetail: String {
    guard !rows.isEmpty else { return "No proof targets queued for this round." }
    return rows.prefix(4)
      .map { "\($0.contenderTitle): \($0.targetLabel)" }
      .joined(separator: "; ")
  }

  var workbenchAccessibilityID: String {
    "proof-target-scoreboard-\(roundID ?? "unknown-round")"
  }

  var runTopStepAccessibilityID: String {
    "\(workbenchAccessibilityID)-run-top-step"
  }

  func readinessGroupActionAccessibilityID(
    _ group: TournamentAutomationProofTargetScoreboardReadinessGroup
  ) -> String {
    "\(workbenchAccessibilityID)-group-\(group.accessibilitySuffix)-action"
  }

  func readinessGroupResultAccessibilityID(
    _ group: TournamentAutomationProofTargetScoreboardReadinessGroup
  ) -> String {
    "\(workbenchAccessibilityID)-group-\(group.accessibilitySuffix)-result"
  }

  func readinessGroupSelectionAccessibilityID(
    _ group: TournamentAutomationProofTargetScoreboardReadinessGroup
  ) -> String {
    "\(workbenchAccessibilityID)-group-\(group.accessibilitySuffix)-selection"
  }

  func readinessGroup(
    containingRowSelectionID selectionID: String?
  ) -> TournamentAutomationProofTargetScoreboardReadinessGroup? {
    guard let selectionID else { return nil }
    return readinessGroups.first { $0.containsRow(selectionID: selectionID) }
  }

  var readinessGroupActionSummary: String {
    let summary =
      readinessGroups
      .prefix(4)
      .map { StringUtils.boundedText($0.actionContextSummary, limit: 140) }
      .joined(separator: " | ")
    return summary.isEmpty ? "none" : summary
  }

  var readinessGroupResultSummary: String {
    let summary =
      readinessGroups
      .prefix(4)
      .map { StringUtils.boundedText($0.latestMovementContextSummary, limit: 180) }
      .joined(separator: " | ")
    return summary.isEmpty ? "none" : summary
  }

  var topActionSummary: String {
    guard let topActionRow else { return "No automation step queued" }
    return "\(topActionRow.contenderTitle): \(topActionRow.nextStepSummary)"
  }

  var topActionStatusLabel: String {
    topActionRow?.nextStatusLabel ?? "No queued proof"
  }

  var topActionStatusSystemImage: String {
    topActionRow?.nextStatusSystemImage ?? "checkmark.seal"
  }

  var topActionStatusAccessibilityID: String {
    "\(workbenchAccessibilityID)-top-action-status"
  }

  var topActionDetail: String {
    guard let topActionRow else { return "No automation step queued for this round." }
    return [
      "\(topActionRow.contenderTitle): \(topActionRow.nextStepDetail)",
      "Readiness: \(topActionRow.nextStatusLabel)",
      topActionRow.latestDebtMovement?.helpSummary,
    ]
    .compactMap { $0 }
    .joined(separator: "\n")
  }

  var topActionButtonTitle: String {
    guard let topActionStep else { return "No Step" }
    switch topActionStep.kind {
    case .prepareWorktree:
      return "Prepare Top Proof"
    case .blocked:
      return "Blocked Proof"
    case .applyDecision, .applyRoundTransition, .runPlanProof, .runCohort, .applyRevision:
      return "Run Top Proof"
    }
  }

  var contextLine: String {
    let rowText = rows.prefix(4).map(\.contextSummary).joined(separator: " | ")
    let topAction =
      topActionRow.map { row in
        let title = StringUtils.boundedText(row.contenderTitle, limit: 80)
        let summary = StringUtils.boundedText(row.nextStepSummary, limit: 140)
        return "top_action \(title): \(summary); top_action_status \(row.nextStatusLabel)"
      } ?? "top_action none"
    let scope = [
      "tournament \(tournamentID ?? "unknown_tournament")",
      "targets \(targetCount)/\(contenderCount)",
      "pressure \(StringUtils.boundedText(readinessSummary, limit: 160))",
      "group_actions \(readinessGroupActionSummary)",
      "group_results \(readinessGroupResultSummary)",
      topAction,
    ]
    .joined(separator: ", ")
    return
      "- proof_target_scoreboard \(roundID ?? "unknown_round") [\(scope)]: \(StringUtils.boundedText(rowText, limit: 420))."
  }
}

enum TournamentAutomationProofTargetScoreboard {
  static func items(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    limit: Int = 4,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> [TournamentAutomationProofTargetScoreboardItem] {
    guard limit > 0 else { return [] }
    let readModel = ProductTournamentReadModel(config: config)
    let targets = TournamentAutomationProofTargetAdvisor.targets(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
    guard !targets.isEmpty else { return [] }
    var nextStepsByExperimentID: [String: TournamentAutomationStep] = [:]
    for step in TournamentAutomationPlanner.steps(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: isPersonaModelAvailable
    ) {
      if nextStepsByExperimentID[step.experimentID] == nil {
        nextStepsByExperimentID[step.experimentID] = step
      }
    }
    var latestDebtMovementByExperimentID: [String: TournamentAutomationProofTargetDebtMovement] =
      [:]
    for target in targets {
      guard latestDebtMovementByExperimentID[target.experimentID] == nil else { continue }
      latestDebtMovementByExperimentID[target.experimentID] = latestDebtMovement(
        for: target,
        config: config
      )
    }

    let grouped = Dictionary(grouping: targets) { target in
      scopeKey(for: target, config: config)
    }
    return grouped.map { key, targets in
      item(
        for: key,
        targets: targets,
        config: config,
        readModel: readModel,
        nextStepsByExperimentID: nextStepsByExperimentID,
        latestDebtMovementByExperimentID: latestDebtMovementByExperimentID
      )
    }
    .sorted { lhs, rhs in
      let lhsMaxUrgency = lhs.rows.map(\.urgencyScore).max() ?? 0
      let rhsMaxUrgency = rhs.rows.map(\.urgencyScore).max() ?? 0
      if lhsMaxUrgency == rhsMaxUrgency {
        if lhs.targetCount == rhs.targetCount {
          return lhs.displayTitle < rhs.displayTitle
        }
        return lhs.targetCount > rhs.targetCount
      }
      return lhsMaxUrgency > rhsMaxUrgency
    }
    .prefix(limit)
    .map { $0 }
  }

  static func contextLines(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    limit: Int = 3,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> [String] {
    let items = items(
      config: config,
      evidenceIndex: evidenceIndex,
      limit: limit,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
    guard !items.isEmpty else { return [] }
    return ["Tournament automation proof scoreboard:"] + items.map(\.contextLine)
  }

  static func focus(
    after audit: TournamentAutomationCycleAudit,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    preferredStep: TournamentAutomationStep? = nil,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> TournamentAutomationProofTargetFocus? {
    if let validationFocus = actedRevisionValidationFocus(
      after: audit,
      config: config,
      evidenceIndex: evidenceIndex,
      preferredStep: preferredStep,
      isPersonaModelAvailable: isPersonaModelAvailable
    ) {
      return validationFocus
    }
    guard
      let row = rowMatchingLatestAudit(
        audit,
        config: config,
        evidenceIndex: evidenceIndex,
        preferredStep: preferredStep,
        isPersonaModelAvailable: isPersonaModelAvailable
      )
    else { return nil }
    let outcomeIDs = row.latestDebtMovement?.evidenceRunIDs ?? audit.evidenceRunIDs
    return TournamentAutomationProofTargetFocus(
      row: row,
      auditID: audit.id,
      evidenceRunID: firstKnownEvidenceRunID(
        in: outcomeIDs,
        row: row,
        evidenceIndex: evidenceIndex
      ),
      planEvaluationID: firstKnownPlanEvaluationID(
        in: outcomeIDs,
        row: row,
        evidenceIndex: evidenceIndex
      )
    )
  }

  static func rowMatchingLatestAudit(
    _ audit: TournamentAutomationCycleAudit,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    preferredStep: TournamentAutomationStep? = nil,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> TournamentAutomationProofTargetScoreboardRow? {
    let rows = items(
      config: config,
      evidenceIndex: evidenceIndex,
      limit: Int.max,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
    .flatMap(\.rows)
    let candidates = rows.filter { row in
      row.latestDebtMovement?.auditID == audit.id
    }
    guard !candidates.isEmpty else { return nil }
    if let preferredStep,
      let preferred = candidates.first(where: { row in
        scoreboardRow(row, matches: preferredStep)
      })
    {
      return preferred
    }
    if let experimentID = audit.experimentIDs.first,
      let experimentMatch = candidates.first(where: { $0.experimentID == experimentID })
    {
      return experimentMatch
    }
    return candidates.first
  }

  static func firstKnownEvidenceRunID(
    for row: TournamentAutomationProofTargetScoreboardRow,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> String? {
    if let context = TournamentAutomationCycleWorkbenchFacts.actedRevisionValidationRunContext(
      config: config,
      evidenceIndex: evidenceIndex,
      scoreboardItems: [],
      isPersonaModelAvailable: isPersonaModelAvailable
    ),
      context.matches(row),
      let evidenceRunID = context.latestEvidenceRunID,
      firstKnownEvidenceRunID(in: [evidenceRunID], row: row, evidenceIndex: evidenceIndex) != nil
    {
      return evidenceRunID
    }
    return firstKnownEvidenceRunID(for: row, evidenceIndex: evidenceIndex)
  }

  static func firstKnownEvidenceRunID(
    for row: TournamentAutomationProofTargetScoreboardRow,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> String? {
    firstKnownEvidenceRunID(
      in: row.latestDebtMovement?.evidenceRunIDs ?? [],
      row: row,
      evidenceIndex: evidenceIndex
    )
  }

  static func firstKnownPlanEvaluationID(
    for row: TournamentAutomationProofTargetScoreboardRow,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> String? {
    firstKnownPlanEvaluationID(
      in: row.latestDebtMovement?.evidenceRunIDs ?? [],
      row: row,
      evidenceIndex: evidenceIndex
    )
  }

  private static func actedRevisionValidationFocus(
    after audit: TournamentAutomationCycleAudit,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    preferredStep: TournamentAutomationStep?,
    isPersonaModelAvailable: Bool
  ) -> TournamentAutomationProofTargetFocus? {
    guard
      let context = TournamentAutomationCycleWorkbenchFacts.actedRevisionValidationRunContext(
        config: config,
        evidenceIndex: evidenceIndex,
        currentStep: preferredStep,
        scoreboardItems: [],
        isPersonaModelAvailable: isPersonaModelAvailable
      ),
      let evidenceRunID = context.latestEvidenceRunID,
      audit.evidenceRunIDs.contains(evidenceRunID),
      let row = rowMatchingActedRevisionValidation(
        context,
        config: config,
        evidenceIndex: evidenceIndex,
        preferredStep: preferredStep,
        isPersonaModelAvailable: isPersonaModelAvailable
      )
    else { return nil }
    return TournamentAutomationProofTargetFocus(
      row: row,
      auditID: audit.id,
      evidenceRunID: evidenceRunID,
      planEvaluationID: nil
    )
  }

  private static func rowMatchingActedRevisionValidation(
    _ context: TournamentAutomationActedRevisionValidationRunContext,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    preferredStep: TournamentAutomationStep?,
    isPersonaModelAvailable: Bool
  ) -> TournamentAutomationProofTargetScoreboardRow? {
    let rows = items(
      config: config,
      evidenceIndex: evidenceIndex,
      limit: Int.max,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
    .flatMap(\.rows)
    let candidates = rows.filter { context.matches($0) }
    guard !candidates.isEmpty else { return nil }
    if let preferredStep,
      let preferred = candidates.first(where: { scoreboardRow($0, matches: preferredStep) })
    {
      return preferred
    }
    return candidates.first
  }

  private struct ScopeKey: Hashable {
    var tournamentID: String?
    var roundID: String?
  }

  private static func item(
    for key: ScopeKey,
    targets: [TournamentAutomationProofTarget],
    config: ProductTournamentConfig,
    readModel: ProductTournamentReadModel,
    nextStepsByExperimentID: [String: TournamentAutomationStep],
    latestDebtMovementByExperimentID: [String: TournamentAutomationProofTargetDebtMovement]
  ) -> TournamentAutomationProofTargetScoreboardItem {
    let tournament = key.tournamentID.flatMap(readModel.tournament)
    let round = key.roundID.flatMap(readModel.round)
    let contenderCount = max(
      1,
      activeContenderCount(round: round, tournament: tournament, config: config)
    )
    let rows =
      targets
      .map { target in
        row(
          for: target,
          readModel: readModel,
          nextStep: nextStepsByExperimentID[target.experimentID],
          latestDebtMovement: latestDebtMovementByExperimentID[target.experimentID]
        )
      }
      .sorted { $0.scoreboardSortsBefore($1) }
    return TournamentAutomationProofTargetScoreboardItem(
      tournamentID: key.tournamentID,
      roundID: key.roundID,
      roundTitle: round?.title ?? "Tournament proof targets",
      contenderCount: contenderCount,
      rows: rows
    )
  }

  private static func row(
    for target: TournamentAutomationProofTarget,
    readModel: ProductTournamentReadModel,
    nextStep: TournamentAutomationStep?,
    latestDebtMovement: TournamentAutomationProofTargetDebtMovement?
  ) -> TournamentAutomationProofTargetScoreboardRow {
    let contender = target.contenderID.flatMap(readModel.contender)
    return TournamentAutomationProofTargetScoreboardRow(
      experimentID: target.experimentID,
      tournamentID: target.tournamentID,
      roundID: target.roundID,
      contenderID: target.contenderID,
      contenderTitle: contender?.title ?? target.contenderID ?? target.experimentID,
      targetLabel: target.label,
      cohortID: target.cohortID,
      targetScenarioID: target.targetScenarioID,
      targetPersonaID: target.targetPersonaID,
      targetPersonaName: target.targetPersonaName,
      targetDecision: target.targetDecision,
      readinessScore: target.readinessScore,
      urgencyScore: target.urgencyScore,
      debtSummary: target.debtSummary,
      nextActionTitle: target.nextActionTitle,
      tournamentPositionSummary: target.tournamentPositionSummary,
      nextStep: nextStep,
      latestDebtMovement: latestDebtMovement
    )
  }

  private static func latestDebtMovement(
    for target: TournamentAutomationProofTarget,
    config: ProductTournamentConfig
  ) -> TournamentAutomationProofTargetDebtMovement? {
    config.tournamentAutomationCycleAudits
      .sorted { lhs, rhs in
        if lhs.endedAt == rhs.endedAt { return lhs.id < rhs.id }
        return lhs.endedAt > rhs.endedAt
      }
      .first(where: { audit in matches(audit, target: target) })
      .flatMap(TournamentAutomationProofTargetDebtMovement.init(audit:))
  }

  private static func matches(
    _ audit: TournamentAutomationCycleAudit,
    target: TournamentAutomationProofTarget
  ) -> Bool {
    guard audit.proofDebtDelta != nil else { return false }
    let searchable = auditSearchText(audit)
    let experimentMatches =
      audit.experimentIDs.contains(target.experimentID)
      || audit.executedStepIDs.contains { $0.hasPrefix("\(target.experimentID):") }
      || searchable.contains(target.experimentID)
    guard experimentMatches else { return false }

    if audit.proofTargetSummaries.contains(where: { proofTargetSummary($0, matches: target) }) {
      return true
    }
    if let scopedMatch = scopedAuditText(searchable, matches: target) {
      return scopedMatch
    }
    if let nextActionKind = target.nextActionKind {
      return audit.executedStepIDs.contains {
        $0.hasPrefix("\(target.experimentID):\(nextActionKind.rawValue)")
      }
    }
    return !targetHasScopeHints(target)
  }

  private static func auditSearchText(_ audit: TournamentAutomationCycleAudit) -> String {
    (audit.executedStepIDs + audit.experimentIDs + audit.messages + audit.evidenceRunIDs
      + audit.decisionCandidateSummaries + audit.evidenceTensionSummaries
      + audit.proofTargetSummaries + audit.targetedProofOutcomeSummaries
      + audit.personaRationaleSignalSummaries + audit.revisionBriefSummaries
      + [
        audit.startingProofDebtSummary,
        audit.endingProofDebtSummary,
        audit.stopStepID,
        audit.stopStepTitle,
        audit.stopDetail,
        audit.userMessage,
      ].compactMap { $0 })
      .joined(separator: " ")
  }

  private static func proofTargetSummary(
    _ summary: String,
    matches target: TournamentAutomationProofTarget
  ) -> Bool {
    guard summary.localizedCaseInsensitiveContains(target.label) else { return false }
    if let targetScenarioID = target.targetScenarioID,
      !summary.contains("scenario \(targetScenarioID)") && !summary.contains(targetScenarioID)
    {
      return false
    }
    if let cohortID = target.cohortID,
      !summary.contains("cohort \(cohortID)") && !summary.contains(cohortID)
    {
      return false
    }
    if let roundID = target.roundID,
      !summary.contains("round \(roundID)") && !summary.contains(roundID)
    {
      return false
    }
    if let contenderID = target.contenderID,
      !summary.contains("contender \(contenderID)") && !summary.contains(contenderID)
    {
      return false
    }
    if let targetDecision = target.targetDecision,
      !summary.contains("target_decision \(targetDecision.rawValue)")
    {
      return false
    }
    if let requiredSimulationMode = target.requiredSimulationMode,
      !summary.contains("required_mode \(requiredSimulationMode.rawValue)")
    {
      return false
    }
    if let targetPersonaName = target.targetPersonaName,
      !summary.localizedCaseInsensitiveContains(targetPersonaName)
    {
      return false
    }
    return true
  }

  private static func scopedAuditText(
    _ text: String,
    matches target: TournamentAutomationProofTarget
  ) -> Bool? {
    let lowercased = text.lowercased()
    var sawScopeMarker = false

    if lowercased.contains("contender ") {
      sawScopeMarker = true
      guard let contenderID = target.contenderID,
        lowercased.contains("contender \(contenderID.lowercased())")
          || lowercased.contains(contenderID.lowercased())
      else { return false }
    }
    if lowercased.contains("round ") {
      sawScopeMarker = true
      guard let roundID = target.roundID,
        lowercased.contains("round \(roundID.lowercased())")
          || lowercased.contains(
            roundID.lowercased()
          )
      else { return false }
    }
    if lowercased.contains("scenario ") {
      sawScopeMarker = true
      guard let targetScenarioID = target.targetScenarioID,
        lowercased.contains("scenario \(targetScenarioID.lowercased())")
          || lowercased.contains(targetScenarioID.lowercased())
      else { return false }
    }
    if lowercased.contains("cohort ") {
      sawScopeMarker = true
      guard let cohortID = target.cohortID,
        lowercased.contains("cohort \(cohortID.lowercased())")
          || lowercased.contains(cohortID.lowercased())
      else { return false }
    }
    if lowercased.contains("target_decision ") {
      sawScopeMarker = true
      guard let targetDecision = target.targetDecision,
        lowercased.contains("target_decision \(targetDecision.rawValue)")
      else { return false }
    }
    if lowercased.contains("required_mode ") {
      sawScopeMarker = true
      guard let requiredSimulationMode = target.requiredSimulationMode,
        lowercased.contains("required_mode \(requiredSimulationMode.rawValue)")
      else { return false }
    }

    return sawScopeMarker ? true : nil
  }

  private static func targetHasScopeHints(_ target: TournamentAutomationProofTarget) -> Bool {
    target.tournamentID != nil
      || target.contenderID != nil
      || target.roundID != nil
      || target.cohortID != nil
      || target.targetScenarioID != nil
      || target.targetPersonaID != nil
      || target.targetPersonaName != nil
      || target.targetDecision != nil
      || target.requiredSimulationMode != nil
  }

  private static func scoreboardRow(
    _ row: TournamentAutomationProofTargetScoreboardRow,
    matches step: TournamentAutomationStep
  ) -> Bool {
    guard row.experimentID == step.experimentID else { return false }
    if let stepRoundID = step.roundID,
      let rowRoundID = row.roundID,
      rowRoundID != stepRoundID
    {
      return false
    }
    if let stepContenderID = step.contenderID,
      let rowContenderID = row.contenderID,
      rowContenderID != stepContenderID
    {
      return false
    }
    if let stepScenarioID = step.targetScenarioID,
      let rowScenarioID = row.targetScenarioID,
      rowScenarioID != stepScenarioID
    {
      return false
    }
    if let stepCohortID = step.cohortID,
      let rowCohortID = row.cohortID,
      rowCohortID != stepCohortID
    {
      return false
    }
    if let stepTargetDecision = step.action.targetDecision,
      let rowTargetDecision = row.targetDecision,
      rowTargetDecision != stepTargetDecision
    {
      return false
    }
    return true
  }

  private static func firstKnownEvidenceRunID(
    in outcomeIDs: [String],
    row: TournamentAutomationProofTargetScoreboardRow,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> String? {
    outcomeIDs.first { runID in
      evidenceIndex.summaries.contains { summary in
        summary.runID == runID && evidenceSummary(summary, matches: row)
      }
    }
  }

  private static func firstKnownPlanEvaluationID(
    in outcomeIDs: [String],
    row: TournamentAutomationProofTargetScoreboardRow,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> String? {
    outcomeIDs.first { evaluationID in
      evidenceIndex.planEvaluationSummaries.contains { summary in
        summary.evaluationID == evaluationID && planEvaluationSummary(summary, matches: row)
      }
    }
  }

  private static func evidenceSummary(
    _ summary: ProductTournamentEvidenceSummary,
    matches row: TournamentAutomationProofTargetScoreboardRow
  ) -> Bool {
    guard summary.experimentID == row.experimentID else { return false }
    if let rowRoundID = row.roundID,
      let summaryRoundID = summary.roundID,
      summaryRoundID != rowRoundID
    {
      return false
    }
    if let rowContenderID = row.contenderID,
      let summaryContenderID = summary.contenderID,
      summaryContenderID != rowContenderID
    {
      return false
    }
    if let rowScenarioID = row.targetScenarioID, summary.scenarioID != rowScenarioID {
      return false
    }
    if let rowTargetDecision = row.targetDecision,
      summary.decisionIntent?.targetDecision != rowTargetDecision
    {
      return false
    }
    return true
  }

  private static func planEvaluationSummary(
    _ summary: ProductTournamentPlanEvaluationSummary,
    matches row: TournamentAutomationProofTargetScoreboardRow
  ) -> Bool {
    if let experimentID = summary.experimentID, experimentID != row.experimentID {
      return false
    }
    if let rowRoundID = row.roundID, summary.roundID != rowRoundID {
      return false
    }
    if let rowContenderID = row.contenderID, summary.contenderID != rowContenderID {
      return false
    }
    return true
  }

  private static func scopeKey(
    for target: TournamentAutomationProofTarget,
    config: ProductTournamentConfig
  ) -> ScopeKey {
    let contender =
      target.contenderID.flatMap { contenderID in
        config.tournamentContenders.first { $0.id == contenderID }
      } ?? config.tournamentContenders.first { $0.experimentID == target.experimentID }
    let tournamentID = target.tournamentID ?? contender?.tournamentID
    let tournament = tournamentID.flatMap { id in config.tournaments.first { $0.id == id } }
    let roundID = target.roundID ?? tournament?.currentRoundID
    return ScopeKey(tournamentID: tournamentID, roundID: roundID)
  }

  private static func activeContenderCount(
    round: ProductTournamentRound?,
    tournament: ProductTournament?,
    config: ProductTournamentConfig
  ) -> Int {
    let roundContenderIDs: [String]
    if let round, !round.contenderIDs.isEmpty {
      roundContenderIDs = round.contenderIDs
    } else {
      roundContenderIDs = tournament?.contenderIDs ?? []
    }
    let contendersByID = Dictionary(
      uniqueKeysWithValues: config.tournamentContenders.map { ($0.id, $0) }
    )
    let roundContenders = roundContenderIDs.compactMap { contendersByID[$0] }
    let active = roundContenders.filter { contender in
      switch contender.status {
      case .competing, .narrowed, .needsRevision:
        return true
      case .eliminated, .winner, .archived:
        return false
      }
    }
    return active.isEmpty ? roundContenders.count : active.count
  }
}
