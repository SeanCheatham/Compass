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
    return "Latest audit left proof debt unchanged (\(startingProofDebtCount) -> \(endingProofDebtCount))"
  }

  var contextSummary: String {
    var parts = [
      "latest_audit \(StringUtils.boundedText(auditID, limit: 80))",
      "proof_debt \(startingProofDebtCount) -> \(endingProofDebtCount) (\(signedDelta))",
    ]
    if !evidenceRunIDs.isEmpty {
      parts.append("evidence \(evidenceRunIDs.prefix(3).joined(separator: ", "))")
    }
    if let startingProofDebtSummary {
      parts.append("starting \(StringUtils.boundedText(startingProofDebtSummary, limit: 140))")
    }
    if let endingProofDebtSummary {
      parts.append("ending \(StringUtils.boundedText(endingProofDebtSummary, limit: 140))")
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

struct TournamentAutomationProofTargetScoreboardRow: Equatable, Sendable, Identifiable {
  var id: String { experimentID }

  var experimentID: String
  var contenderID: String?
  var contenderTitle: String
  var targetLabel: String
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
      "debt \(StringUtils.boundedText(debtSummary, limit: 120))",
    ]
    if let nextActionTitle {
      parts.append("next \(StringUtils.boundedText(nextActionTitle, limit: 80))")
    }
    if let tournamentPositionSummary {
      parts.append("position \(StringUtils.boundedText(tournamentPositionSummary, limit: 120))")
    }
    if let nextStep {
      let status = nextStep.canExecute ? "ready" : "blocked"
      parts.append("step \(status) \(nextStep.kind.rawValue)")
    }
    if let latestDebtMovement {
      parts.append(latestDebtMovement.contextSummary)
    } else {
      parts.append("latest_audit none")
    }
    return parts.joined(separator: "; ")
  }

  var latestDebtMovementSummary: String {
    latestDebtMovement?.displaySummary ?? "No audited proof-debt movement"
  }

  var helpSummary: String {
    var parts = [
      contenderTitle,
      displaySummary,
      "Debt: \(debtSummary)",
      "Next step: \(nextStepSummary)",
      nextStepDetail,
    ]
    if let latestDebtMovement {
      parts.append(latestDebtMovement.helpSummary)
    }
    return parts.joined(separator: "\n")
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
    rows.first { $0.nextStep != nil }
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

  var topActionSummary: String {
    guard let topActionRow else { return "No automation step queued" }
    return "\(topActionRow.contenderTitle): \(topActionRow.nextStepSummary)"
  }

  var topActionDetail: String {
    guard let topActionRow else { return "No automation step queued for this round." }
    return [
      "\(topActionRow.contenderTitle): \(topActionRow.nextStepDetail)",
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
    let topAction = topActionRow.map { row in
      let title = StringUtils.boundedText(row.contenderTitle, limit: 80)
      let summary = StringUtils.boundedText(row.nextStepSummary, limit: 140)
      return "top_action \(title): \(summary)"
    } ?? "top_action none"
    let scope = [
      "tournament \(tournamentID ?? "unknown_tournament")",
      "targets \(targetCount)/\(contenderCount)",
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

  private struct ScopeKey: Hashable {
    var tournamentID: String?
    var roundID: String?
  }

  private static func item(
    for key: ScopeKey,
    targets: [TournamentAutomationProofTarget],
    config: ProductTournamentConfig,
    nextStepsByExperimentID: [String: TournamentAutomationStep],
    latestDebtMovementByExperimentID: [String: TournamentAutomationProofTargetDebtMovement]
  ) -> TournamentAutomationProofTargetScoreboardItem {
    let tournament = key.tournamentID.flatMap { tournamentID in
      config.tournaments.first { $0.id == tournamentID }
    }
    let round = key.roundID.flatMap { roundID in
      config.tournamentRounds.first { $0.id == roundID }
    }
    let contenderCount = max(
      1,
      activeContenderCount(round: round, tournament: tournament, config: config)
    )
    let rows = targets
      .map { target in
        row(
          for: target,
          config: config,
          nextStep: nextStepsByExperimentID[target.experimentID],
          latestDebtMovement: latestDebtMovementByExperimentID[target.experimentID]
        )
      }
      .sorted {
        if $0.urgencyScore == $1.urgencyScore {
          return $0.contenderTitle < $1.contenderTitle
        }
        return $0.urgencyScore > $1.urgencyScore
      }
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
    config: ProductTournamentConfig,
    nextStep: TournamentAutomationStep?,
    latestDebtMovement: TournamentAutomationProofTargetDebtMovement?
  ) -> TournamentAutomationProofTargetScoreboardRow {
    let contender = target.contenderID.flatMap { contenderID in
      config.tournamentContenders.first { $0.id == contenderID }
    }
    return TournamentAutomationProofTargetScoreboardRow(
      experimentID: target.experimentID,
      contenderID: target.contenderID,
      contenderTitle: contender?.title ?? target.contenderID ?? target.experimentID,
      targetLabel: target.label,
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
    (
      audit.executedStepIDs + audit.experimentIDs + audit.messages + audit.evidenceRunIDs
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
        ].compactMap { $0 }
    )
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
        lowercased.contains("round \(roundID.lowercased())") || lowercased.contains(
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

  private static func scopeKey(
    for target: TournamentAutomationProofTarget,
    config: ProductTournamentConfig
  ) -> ScopeKey {
    let contender = target.contenderID.flatMap { contenderID in
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
