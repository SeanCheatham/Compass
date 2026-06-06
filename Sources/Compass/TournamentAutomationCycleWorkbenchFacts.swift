import Foundation

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
    let outcomes = audit.actedProofPressureGroupSummaries.prefix(2)
      .map(ActedPressureGroupContext.init(summary:))
      .map { $0.outcomeSummary(after: audit, in: scoreboardItems) }
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
      guard let anchor else { return "outcome unknown; no anchor" }
      guard let match = currentMatch(for: anchor, in: scoreboardItems) else {
        return "cleared from proof scoreboard"
      }
      let transition = outcomeTransition(
        audit: audit,
        currentGroup: match.group,
        row: match.row
      )
      return [
        transition,
        match.row.nextStatusLabel,
        "next \(match.row.nextStepSummary)",
      ].joined(separator: "; ")
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
    ) -> String {
      guard let group, group == currentGroup.bucket else {
        let source = group ?? "acted group"
        return "moved \(source) -> \(currentGroup.bucket)"
      }
      guard let movement = row.latestDebtMovement, movement.auditID == audit.id else {
        return "still \(currentGroup.bucket)"
      }
      if movement.proofDebtDelta < 0 {
        return "reduced but still \(currentGroup.bucket)"
      }
      if movement.proofDebtDelta > 0 {
        return "worsened in \(currentGroup.bucket)"
      }
      return "stalled in \(currentGroup.bucket)"
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
}
