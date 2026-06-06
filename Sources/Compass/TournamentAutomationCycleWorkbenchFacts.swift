import Foundation

struct TournamentAutomationActedPressureGroupOutcome: Equatable, Sendable {
  enum State: String, Sendable {
    case cleared
    case moved
    case still
    case reduced
    case worsened
    case stalled
    case unknown
  }

  var auditID: String
  var anchor: String?
  var sourceGroup: String?
  var currentGroup: String?
  var contender: String?
  var state: State
  var summary: String

  var isStalledProofRun: Bool {
    state == .stalled && currentGroup == "Proof runs"
  }

  var isStillProofRun: Bool {
    state == .still && currentGroup == "Proof runs"
  }

  static func stalledProofRun(
    auditID: String,
    actedSummary: String
  ) -> TournamentAutomationActedPressureGroupOutcome? {
    proofRun(auditID: auditID, actedSummary: actedSummary, state: .stalled)
  }

  static func stillProofRun(
    auditID: String,
    actedSummary: String
  ) -> TournamentAutomationActedPressureGroupOutcome? {
    proofRun(auditID: auditID, actedSummary: actedSummary, state: .still)
  }

  private static func proofRun(
    auditID: String,
    actedSummary: String,
    state: State
  ) -> TournamentAutomationActedPressureGroupOutcome? {
    let fields = parsedFields(in: actedSummary)
    guard fields.group == "Proof runs" else { return nil }
    let status = fields.status ?? "More proof"
    let next = fields.next.map { "next \($0)" } ?? "next proof target unchanged"
    let prefix =
      state == .stalled
      ? "stalled in Proof runs"
      : "still Proof runs"
    return TournamentAutomationActedPressureGroupOutcome(
      auditID: auditID,
      anchor: fields.anchor,
      sourceGroup: fields.group,
      currentGroup: fields.group,
      contender: fields.contender,
      state: state,
      summary: "\(prefix); \(status); \(next)"
    )
  }

  private static func parsedFields(
    in summary: String
  ) -> (group: String?, anchor: String?, contender: String?, status: String?, next: String?) {
    var group: String?
    var anchor: String?
    var contender: String?
    var status: String?
    var next: String?
    let fields = summary
      .split(separator: ";", omittingEmptySubsequences: true)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    for field in fields {
      if field.hasPrefix("pressure_group ") {
        group = String(field.dropFirst("pressure_group ".count))
      } else if field.hasPrefix("anchor ") {
        anchor = String(field.dropFirst("anchor ".count))
      } else if field.hasPrefix("contender ") {
        contender = String(field.dropFirst("contender ".count))
      } else if field.hasPrefix("status ") {
        status = String(field.dropFirst("status ".count))
      } else if field.hasPrefix("next ") {
        next = String(field.dropFirst("next ".count))
      }
    }
    return (group, anchor, contender, status, next)
  }
}

struct TournamentAutomationCycleWorkbenchFacts: Equatable, Sendable {
  var latestCycleSummary: String
  var latestCycleHelp: String
  var latestPreparationSummary: String?
  var latestPreparationHelp: String?
  var latestEvidenceSummary: String
  var latestEvidenceHelp: String?
  var latestActedPressureGroupSummary: String?
  var latestActedPressureGroupHelp: String?
  var latestActedPressureGroupOutcomeSummary: String?
  var latestActedPressureGroupOutcomeHelp: String?
  var latestActedPressureGroupLearningSummary: String?
  var latestActedPressureGroupLearningHelp: String?
  var latestActedRevisionValidationSummary: String?
  var latestActedRevisionValidationHelp: String?
  var postPreparationEvidenceSummary: String?
  var postPreparationEvidenceHelp: String?
  var latestRoundTwoProofGapValidationSummary: String?
  var latestRoundTwoProofGapValidationHelp: String?
  var latestRoundThreeImplementationRevisionValidationSummary: String?
  var latestRoundThreeImplementationRevisionValidationHelp: String?

  static func latest(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    currentStep: TournamentAutomationStep? = nil,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> TournamentAutomationCycleWorkbenchFacts? {
    let audits = sortedAudits(in: config)
    guard let latestAudit = audits.first else { return nil }

    let preparationAudit = audits.first { $0.prepareWorktreeStepCount > 0 }
    let evidenceAudit = audits.first { audit in
      audit.evidenceRunStepCount > 0
        || !audit.evidenceRunIDs.isEmpty
        || audit.completedEvidenceRunCount > 0
        || audit.failedEvidenceRunCount > 0
        || audit.skippedScenarioCount > 0
    }
    let actedPressureGroupAudit = audits.first { !$0.actedProofPressureGroupSummaries.isEmpty }
    let actedPressureGroupLearning = actedPressureGroupAudit.flatMap {
      makeActedPressureGroupLearningSignal(
        for: $0,
        audits: audits,
        config: config,
        evidenceIndex: evidenceIndex
      )
    }
    let actedRevisionValidation = audits.compactMap(makeActedRevisionValidationContext).first
    let proofScoreboardItems =
      actedPressureGroupAudit == nil
      ? []
      : TournamentAutomationProofTargetScoreboard.items(
        config: config,
        evidenceIndex: evidenceIndex,
        limit: Int.max,
        isPersonaModelAvailable: isPersonaModelAvailable
      )

    let latestPreparationSummary: String?
    let latestPreparationHelp: String?
    if let preparationAudit {
      latestPreparationSummary = makePreparationSummary(
        for: preparationAudit,
        config: config,
        evidenceIndex: evidenceIndex
      )
      let currentEvidenceRuns = currentEvidenceRunCount(
        for: preparationAudit,
        config: config,
        evidenceIndex: evidenceIndex
      )
      latestPreparationHelp =
        "audit \(preparationAudit.id); prepared \(preparationAudit.prepareWorktreeStepCount) worktree step(s); current evidence runs \(currentEvidenceRuns); \(preparationAudit.stopDetail)"
    } else {
      latestPreparationSummary = nil
      latestPreparationHelp = nil
    }
    let postPreparationEvidence = makePostPreparationEvidenceCue(
      for: currentStep,
      preparationAudit: preparationAudit,
      config: config,
      evidenceIndex: evidenceIndex
    )
    let roundTwoValidation = ProductTournamentRoundTwoProofGapValidationAdvisor
      .results(config: config, evidenceIndex: evidenceIndex, limit: 1)
      .first
    let roundThreeValidation = ProductTournamentRoundThreeImplementationRevisionValidationAdvisor
      .results(config: config, evidenceIndex: evidenceIndex, limit: 1)
      .first

    return TournamentAutomationCycleWorkbenchFacts(
      latestCycleSummary: latestAudit.summary,
      latestCycleHelp: helpSummary(for: latestAudit),
      latestPreparationSummary: latestPreparationSummary,
      latestPreparationHelp: latestPreparationHelp,
      latestEvidenceSummary: evidenceAudit.map(makeEvidenceSummary(for:)) ?? "none recorded",
      latestEvidenceHelp: evidenceAudit.map(helpSummary(for:)),
      latestActedPressureGroupSummary: actedPressureGroupAudit.flatMap(
        makeActedPressureGroupSummary(for:)
      ),
      latestActedPressureGroupHelp: actedPressureGroupAudit.map(
        makeActedPressureGroupHelp(for:)
      ),
      latestActedPressureGroupOutcomeSummary: actedPressureGroupAudit.flatMap {
        makeActedPressureGroupOutcomeSummary(
          for: $0,
          scoreboardItems: proofScoreboardItems
        )
      },
      latestActedPressureGroupOutcomeHelp: actedPressureGroupAudit.map {
        makeActedPressureGroupOutcomeHelp(
          for: $0,
          scoreboardItems: proofScoreboardItems
        )
      },
      latestActedPressureGroupLearningSummary: actedPressureGroupLearning?.summary,
      latestActedPressureGroupLearningHelp: actedPressureGroupLearning?.help,
      latestActedRevisionValidationSummary: actedRevisionValidation?.summary,
      latestActedRevisionValidationHelp: actedRevisionValidation?.help,
      postPreparationEvidenceSummary: postPreparationEvidence?.summary,
      postPreparationEvidenceHelp: postPreparationEvidence?.help,
      latestRoundTwoProofGapValidationSummary: roundTwoValidation.map(
        makeRoundTwoProofGapValidationSummary(for:)
      ),
      latestRoundTwoProofGapValidationHelp: roundTwoValidation.map(\.contextLine),
      latestRoundThreeImplementationRevisionValidationSummary: roundThreeValidation.map(
        makeRoundThreeImplementationRevisionValidationSummary(for:)
      ),
      latestRoundThreeImplementationRevisionValidationHelp: roundThreeValidation.map(\.contextLine)
    )
  }

  static func actedPressureGroupOutcomeSummary(
    for audit: TournamentAutomationCycleAudit,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> String? {
    guard !audit.actedProofPressureGroupSummaries.isEmpty else { return nil }
    let proofScoreboardItems = TournamentAutomationProofTargetScoreboard.items(
      config: config,
      evidenceIndex: evidenceIndex,
      limit: Int.max,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
    return makeActedPressureGroupOutcomeSummary(
      for: audit,
      scoreboardItems: proofScoreboardItems
    )
  }

  static func actedPressureGroupOutcomes(
    for audit: TournamentAutomationCycleAudit,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> [TournamentAutomationActedPressureGroupOutcome] {
    guard !audit.actedProofPressureGroupSummaries.isEmpty else { return [] }
    let proofScoreboardItems = TournamentAutomationProofTargetScoreboard.items(
      config: config,
      evidenceIndex: evidenceIndex,
      limit: Int.max,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
    return makeActedPressureGroupOutcomes(
      for: audit,
      scoreboardItems: proofScoreboardItems
    )
  }

  static func actedPressureGroupLearningSummary(
    for audit: TournamentAutomationCycleAudit,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> String? {
    let audits = sortedAudits(in: config)
    return makeActedPressureGroupLearningSignal(
      for: audit,
      audits: audits,
      config: config,
      evidenceIndex: evidenceIndex
    )?.summary
  }

  private static func sortedAudits(
    in config: ProductTournamentConfig
  ) -> [TournamentAutomationCycleAudit] {
    config.tournamentAutomationCycleAudits.sorted { lhs, rhs in
      if lhs.endedAt == rhs.endedAt { return lhs.id < rhs.id }
      return lhs.endedAt > rhs.endedAt
    }
  }

  private static func makePreparationSummary(
    for audit: TournamentAutomationCycleAudit,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> String {
    let experimentIDs = audit.experimentIDs.isEmpty ? ["unknown-experiment"] : audit.experimentIDs
    let experiments = bounded(experimentIDs.prefix(3).joined(separator: ", "), limit: 180)
    let moreExperiments =
      experimentIDs.count > 3
      ? ", +\(experimentIDs.count - 3) more"
      : ""
    let evidenceRunCount = currentEvidenceRunCount(
      for: audit,
      config: config,
      evidenceIndex: evidenceIndex
    )
    return
      "\(audit.prepareWorktreeStepCount) prepare step(s), experiments \(experiments)\(moreExperiments), current evidence runs \(evidenceRunCount)"
  }

  private static func currentEvidenceRunCount(
    for audit: TournamentAutomationCycleAudit,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> Int {
    audit.experimentIDs.reduce(0) { count, experimentID in
      guard
        let experiment = config.tournamentExperiments.first(where: { $0.id == experimentID })
      else { return count }
      return count + evidenceIndex.summaries(for: experiment).count
    }
  }

  private static func makeEvidenceSummary(for audit: TournamentAutomationCycleAudit) -> String {
    let runIDs =
      audit.evidenceRunIDs.isEmpty
      ? ""
      : "; runs \(bounded(audit.evidenceRunIDs.prefix(3).joined(separator: ", "), limit: 160))"
    let moreRuns =
      audit.evidenceRunIDs.count > 3
      ? ", +\(audit.evidenceRunIDs.count - 3) more"
      : ""
    return
      "\(audit.evidenceRunStepCount) evidence step(s), \(audit.completedEvidenceRunCount) completed, \(audit.failedEvidenceRunCount) needing review, \(audit.skippedScenarioCount) skipped\(runIDs)\(moreRuns)"
  }

  private static func makeActedPressureGroupSummary(
    for audit: TournamentAutomationCycleAudit
  ) -> String? {
    let summaries = audit.actedProofPressureGroupSummaries.prefix(2)
      .map(ActedPressureGroupContext.init(summary:))
      .map(\.displaySummary)
    guard !summaries.isEmpty else { return nil }
    return bounded(summaries.joined(separator: " | "), limit: 260)
  }

  private static func makeActedPressureGroupHelp(
    for audit: TournamentAutomationCycleAudit
  ) -> String {
    let contexts = audit.actedProofPressureGroupSummaries.prefix(3)
      .map(ActedPressureGroupContext.init(summary:))
      .map(\.helpSummary)
      .joined(separator: " | ")
    return bounded(
      "audit \(audit.id); \(contexts); stop \(audit.stopReason.rawValue); \(audit.stopDetail)",
      limit: 500
    )
  }

  private static func makeActedPressureGroupOutcomeSummary(
    for audit: TournamentAutomationCycleAudit,
    scoreboardItems: [TournamentAutomationProofTargetScoreboardItem]
  ) -> String? {
    let outcomes = makeActedPressureGroupOutcomes(for: audit, scoreboardItems: scoreboardItems)
      .prefix(2)
      .map(\.summary)
    guard !outcomes.isEmpty else { return nil }
    return bounded(outcomes.joined(separator: " | "), limit: 260)
  }

  private static func makeActedPressureGroupOutcomeHelp(
    for audit: TournamentAutomationCycleAudit,
    scoreboardItems: [TournamentAutomationProofTargetScoreboardItem]
  ) -> String {
    let outcomes = audit.actedProofPressureGroupSummaries.prefix(3)
      .map(ActedPressureGroupContext.init(summary:))
      .map { $0.outcomeHelpSummary(after: audit, in: scoreboardItems) }
      .joined(separator: " | ")
    return bounded(
      "audit \(audit.id); \(outcomes); stop \(audit.stopReason.rawValue); \(audit.stopDetail)",
      limit: 500
    )
  }

  private static func makeActedPressureGroupLearningSignal(
    for audit: TournamentAutomationCycleAudit,
    audits: [TournamentAutomationCycleAudit],
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> (summary: String, help: String)? {
    guard !audit.actedProofPressureGroupSummaries.isEmpty,
      !hasCompletedEvidence(after: audit, config: config, evidenceIndex: evidenceIndex)
    else { return nil }
    if (audit.endingProofDebtCount ?? 0) > 0,
      audit.proofDebtDelta == 0,
      let outcome = audit.actedProofPressureGroupSummaries
        .compactMap({
          TournamentAutomationActedPressureGroupOutcome.stalledProofRun(
            auditID: audit.id,
            actedSummary: $0
          )
        })
        .first(where: \.isStalledProofRun)
    {
      return (
        summary: "stalled Proof runs; next Retarget stalled proof group",
        help: bounded(
          "audit \(audit.id); \(anchorHelp(for: outcome)); outcome \(outcome.summary); proof debt unchanged; next Retarget stalled proof group",
          limit: 500
        )
      )
    }
    let recentAudits = audits.prefix(8)
    for outcome in audit.actedProofPressureGroupSummaries
      .compactMap({
        TournamentAutomationActedPressureGroupOutcome.stillProofRun(
          auditID: audit.id,
          actedSummary: $0
        )
      })
      where outcome.isStillProofRun
    {
      let matchingAudits = recentAudits.filter { recentAudit in
        guard recentAudit.stopReason != .executionFailed,
          recentAudit.endedAt <= audit.endedAt,
          recentAudit.completedEvidenceRunCount > 0 || recentAudit.evidenceRunStepCount > 0,
          recentAudit.proofDebtDelta.map({ $0 >= 0 }) ?? true
        else { return false }
        return recentAudit.actedProofPressureGroupSummaries.contains { summary in
          guard
            let recentOutcome = TournamentAutomationActedPressureGroupOutcome.stillProofRun(
              auditID: recentAudit.id,
              actedSummary: summary
            )
          else { return false }
          return outcomesShareAnchor(outcome, recentOutcome)
        }
      }
      guard matchingAudits.count >= 2 else { continue }
      let auditIDs = matchingAudits.prefix(3).map(\.id).joined(separator: ", ")
      let moreAudits =
        matchingAudits.count > 3
        ? ", +\(matchingAudits.count - 3) more"
        : ""
      return (
        summary:
          "repeated still-present Proof runs; \(matchingAudits.count) recent attempts; next Retarget repeated proof group",
        help: bounded(
          "audits \(auditIDs)\(moreAudits); \(anchorHelp(for: outcome)); outcome \(outcome.summary); next Retarget repeated proof group",
          limit: 500
        )
      )
    }
    return nil
  }

  private static func makeActedRevisionValidationContext(
    for audit: TournamentAutomationCycleAudit
  ) -> (summary: String, help: String)? {
    guard
      let revision = audit.revisionBriefSummaries
        .compactMap(ActedRevisionValidationContext.init(summary:))
        .first
    else { return nil }
    return (
      summary: revision.displaySummary,
      help: bounded(
        "audit \(audit.id); \(revision.helpSummary); stop \(audit.stopReason.rawValue); \(audit.stopDetail)",
        limit: 500
      )
    )
  }

  private static func outcomesShareAnchor(
    _ lhs: TournamentAutomationActedPressureGroupOutcome,
    _ rhs: TournamentAutomationActedPressureGroupOutcome
  ) -> Bool {
    guard let lhsAnchor = lhs.anchor, let rhsAnchor = rhs.anchor else { return false }
    return lhsAnchor == rhsAnchor
  }

  private static func anchorHelp(
    for outcome: TournamentAutomationActedPressureGroupOutcome
  ) -> String {
    outcome.anchor.map { "anchor \($0)" } ?? "anchor unavailable"
  }

  private static func hasCompletedEvidence(
    after audit: TournamentAutomationCycleAudit,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> Bool {
    config.tournamentExperiments
      .filter { audit.experimentIDs.contains($0.id) }
      .contains { experiment in
        evidenceIndex.summaries(for: experiment).contains {
          $0.isCompleted && $0.endedAt > audit.endedAt
        }
      }
  }

  private static func makeActedPressureGroupOutcomes(
    for audit: TournamentAutomationCycleAudit,
    scoreboardItems: [TournamentAutomationProofTargetScoreboardItem]
  ) -> [TournamentAutomationActedPressureGroupOutcome] {
    audit.actedProofPressureGroupSummaries
      .map(ActedPressureGroupContext.init(summary:))
      .map { $0.outcome(after: audit, in: scoreboardItems) }
  }

  private static func makePostPreparationEvidenceCue(
    for step: TournamentAutomationStep?,
    preparationAudit: TournamentAutomationCycleAudit?,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> (summary: String, help: String)? {
    guard
      let step,
      let preparationAudit,
      step.canExecute,
      step.kind == .runCohort,
      preparationAudit.experimentIDs.contains(step.experimentID),
      currentEvidenceRunCount(
        for: preparationAudit,
        config: config,
        evidenceIndex: evidenceIndex
      ) == 0,
      let cohortID = step.cohortID
    else { return nil }

    let enabledScenarioText =
      step.cohortReadiness.map { "\($0.enabledScenarioCount) enabled scenario(s)" }
        ?? "enabled scenarios"
    let mode = (step.action.requiredSimulationMode ?? .modelFree)
      .tournamentAutomationLabel
      .lowercased()
    let target = step.action.targetPersonaName.map { "; target \(bounded($0, limit: 120))" } ?? ""
    let summary =
      "first \(mode) simulated-user cohort `\(bounded(cohortID, limit: 120))`; \(enabledScenarioText)\(target)"
    let help = bounded(
      "Latest preparation audit \(preparationAudit.id) has 0 current evidence runs for \(step.experimentID); current queue is \(step.queueTitle). \(step.detail)",
      limit: 500
    )
    return (summary, help)
  }

  private static func helpSummary(for audit: TournamentAutomationCycleAudit) -> String {
    bounded(
      "audit \(audit.id); stop \(audit.stopReason.rawValue); \(audit.stopDetail)",
      limit: 500
    )
  }

  private static func makeRoundTwoProofGapValidationSummary(
    for result: ProductTournamentRoundTwoProofGapValidationResult
  ) -> String {
    let scenario = result.revisionScenarioID.map { "; scenario \($0)" } ?? ""
    return bounded(
      "\(result.outcome.title), contender \(result.contenderID), \(result.completedValidationRunCount)/\(result.validationRunCount) validation run(s), audit \(result.revisionAuditID)\(scenario)",
      limit: 260
    )
  }

  private static func makeRoundThreeImplementationRevisionValidationSummary(
    for result: ProductTournamentRoundThreeImplementationRevisionValidationResult
  ) -> String {
    let scenario = result.revisionScenarioID.map { "; scenario \($0)" } ?? ""
    return bounded(
      "\(result.outcome.title), contender \(result.contenderID), \(result.completedValidationRunCount)/\(result.validationRunCount) validation run(s), audit \(result.revisionAuditID)\(scenario)",
      limit: 260
    )
  }

  private static func bounded(_ value: String, limit: Int) -> String {
    StringUtils.boundedText(value, limit: limit)
  }

  private struct ActedPressureGroupContext {
    var group: String?
    var anchor: String?
    var contender: String?
    var status: String?
    var next: String?
    var rawSummary: String

    init(summary: String) {
      self.rawSummary = summary
      let fields = summary
        .split(separator: ";", omittingEmptySubsequences: true)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      for field in fields {
        if field.hasPrefix("pressure_group ") {
          group = String(field.dropFirst("pressure_group ".count))
        } else if field.hasPrefix("anchor ") {
          anchor = String(field.dropFirst("anchor ".count))
        } else if field.hasPrefix("contender ") {
          contender = String(field.dropFirst("contender ".count))
        } else if field.hasPrefix("status ") {
          status = String(field.dropFirst("status ".count))
        } else if field.hasPrefix("next ") {
          next = String(field.dropFirst("next ".count))
        }
      }
    }

    var displaySummary: String {
      let parts = [
        group,
        contender,
        status,
        next.map { "next \($0)" },
      ].compactMap { $0 }
      guard !parts.isEmpty else { return rawSummary }
      return parts.joined(separator: "; ")
    }

    var helpSummary: String {
      let anchorPart = anchor.map { "; anchor \($0)" } ?? ""
      return "\(displaySummary)\(anchorPart)"
    }

    func outcomeSummary(
      after audit: TournamentAutomationCycleAudit,
      in scoreboardItems: [TournamentAutomationProofTargetScoreboardItem]
    ) -> String {
      outcome(after: audit, in: scoreboardItems).summary
    }

    func outcome(
      after audit: TournamentAutomationCycleAudit,
      in scoreboardItems: [TournamentAutomationProofTargetScoreboardItem]
    ) -> TournamentAutomationActedPressureGroupOutcome {
      guard let anchor else {
        return TournamentAutomationActedPressureGroupOutcome(
          auditID: audit.id,
          anchor: nil,
          sourceGroup: group,
          currentGroup: nil,
          contender: contender,
          state: .unknown,
          summary: "outcome unknown; no anchor"
        )
      }
      guard let match = currentMatch(for: anchor, in: scoreboardItems) else {
        return TournamentAutomationActedPressureGroupOutcome(
          auditID: audit.id,
          anchor: anchor,
          sourceGroup: group,
          currentGroup: nil,
          contender: contender,
          state: .cleared,
          summary: "cleared from proof scoreboard"
        )
      }
      let transition = outcomeTransition(
        audit: audit,
        currentGroup: match.group,
        row: match.row
      )
      let summary = [
        transition.summary,
        match.row.nextStatusLabel,
        "next \(match.row.nextStepSummary)",
      ].joined(separator: "; ")
      return TournamentAutomationActedPressureGroupOutcome(
        auditID: audit.id,
        anchor: anchor,
        sourceGroup: group,
        currentGroup: match.group.bucket,
        contender: contender ?? match.row.contenderTitle,
        state: transition.state,
        summary: summary
      )
    }

    func outcomeHelpSummary(
      after audit: TournamentAutomationCycleAudit,
      in scoreboardItems: [TournamentAutomationProofTargetScoreboardItem]
    ) -> String {
      let anchorPart = anchor.map { "; anchor \($0)" } ?? ""
      return "\(displaySummary); outcome \(outcomeSummary(after: audit, in: scoreboardItems))\(anchorPart)"
    }

    private func outcomeTransition(
      audit: TournamentAutomationCycleAudit,
      currentGroup: TournamentAutomationProofTargetScoreboardReadinessGroup,
      row: TournamentAutomationProofTargetScoreboardRow
    ) -> (state: TournamentAutomationActedPressureGroupOutcome.State, summary: String) {
      guard let group, group == currentGroup.bucket else {
        let source = group ?? "acted group"
        return (.moved, "moved \(source) -> \(currentGroup.bucket)")
      }
      guard let movement = row.latestDebtMovement, movement.auditID == audit.id else {
        return (.still, "still \(currentGroup.bucket)")
      }
      if movement.proofDebtDelta < 0 {
        return (.reduced, "reduced but still \(currentGroup.bucket)")
      }
      if movement.proofDebtDelta > 0 {
        return (.worsened, "worsened in \(currentGroup.bucket)")
      }
      return (.stalled, "stalled in \(currentGroup.bucket)")
    }

    private func currentMatch(
      for anchor: String,
      in scoreboardItems: [TournamentAutomationProofTargetScoreboardItem]
    ) -> (
      row: TournamentAutomationProofTargetScoreboardRow,
      group: TournamentAutomationProofTargetScoreboardReadinessGroup
    )? {
      for item in scoreboardItems {
        guard let group = item.readinessGroup(containingRowSelectionID: anchor) else { continue }
        if let row = group.rows.first(where: { $0.selectionID == anchor }) {
          return (row, group)
        }
      }
      return nil
    }
  }

  private struct ActedRevisionValidationContext {
    var experimentID: String?
    var title: String?
    var validation: String?
    var scenarioID: String?
    var rawSummary: String

    init?(summary: String) {
      guard summary.contains("source acted_proof_group") else { return nil }
      rawSummary = summary
      let fields = summary
        .split(separator: ";", omittingEmptySubsequences: true)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      guard let first = fields.first else { return nil }
      if let separator = first.range(of: ": ") {
        experimentID = String(first[..<separator.lowerBound])
        title = String(first[separator.upperBound...])
      } else {
        title = first
      }
      for field in fields.dropFirst() {
        if field.hasPrefix("validation ") {
          validation = String(field.dropFirst("validation ".count))
        } else if field.hasPrefix("scenario ") {
          scenarioID = String(field.dropFirst("scenario ".count))
        }
      }
      guard validation != nil else { return nil }
    }

    var displaySummary: String {
      let parts = [
        validation,
        experimentID.map { "experiment \($0)" },
        scenarioID.map { "scenario \($0)" },
      ].compactMap { $0 }
      guard !parts.isEmpty else { return rawSummary }
      return bounded(parts.joined(separator: "; "), limit: 260)
    }

    var helpSummary: String {
      let parts = [
        title,
        validation.map { "validation \($0)" },
        experimentID.map { "experiment \($0)" },
        scenarioID.map { "scenario \($0)" },
      ].compactMap { $0 }
      guard !parts.isEmpty else { return rawSummary }
      return bounded(parts.joined(separator: "; "), limit: 420)
    }
  }
}
