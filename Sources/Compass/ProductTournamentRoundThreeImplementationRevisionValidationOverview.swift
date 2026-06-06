import Foundation

struct ProductTournamentRoundThreeImplementationRevisionValidationOverviewItem:
  Equatable, Sendable, Identifiable
{
  var id: String { result.id }

  var result: ProductTournamentRoundThreeImplementationRevisionValidationResult
  var contenderTitle: String
  var experimentTitle: String
  var branchName: String
  var worktreeID: String
  var nextStep: TournamentAutomationStep?

  var tournamentID: String { result.tournamentID }
  var roundID: String { result.roundID }
  var contenderID: String { result.contenderID }
  var experimentID: String { result.experimentID }
  var revisionAuditID: String { result.revisionAuditID }
  var revisionScenarioID: String? { result.revisionScenarioID }
  var outcome: ProductTournamentRoundThreeImplementationRevisionValidationOutcome {
    result.outcome
  }

  var displaySubtitle: String {
    "\(outcome.title) - \(result.completedValidationRunCount)/\(result.validationRunCount) validation - readiness \(result.scoreLabel)/100"
  }

  var displayDetail: String {
    result.displayDetail
  }

  var validationSummary: String {
    result.displaySummary
  }

  var nextStepSummary: String {
    guard let nextStep else {
      return "No automation step queued"
    }
    let prefix = nextStep.canExecute ? "Ready" : "Blocked"
    return "\(prefix): \(nextStep.queueTitle)"
  }

  var nextStepDetail: String {
    guard let nextStep else { return result.nextValidationTarget }
    if nextStep.kind == .prepareWorktree {
      let actionDetail = nextStep.action.detail.trimmingCharacters(in: .whitespacesAndNewlines)
      if !actionDetail.isEmpty {
        return "\(nextStep.experimentTitle): \(nextStep.action.title). \(actionDetail)"
      }
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

  var persistedGapSummary: String {
    result.persistedProofGaps.isEmpty
      ? "none"
      : result.persistedProofGaps.prefix(3).joined(separator: "; ")
  }

  var resolvedGapSummary: String {
    result.resolvedProofGaps.isEmpty
      ? "none"
      : result.resolvedProofGaps.prefix(3).joined(separator: "; ")
  }

  var displaySystemImage: String {
    switch outcome {
    case .pendingValidation:
      return "clock"
    case .partialValidation:
      return "hourglass"
    case .resolved:
      return "checkmark.seal"
    case .persisted:
      return "exclamationmark.triangle"
    case .eliminated:
      return "xmark.octagon"
    }
  }

  var workbenchAccessibilityID: String {
    "round-3-implementation-validation-\(id)"
  }

  var helpSummary: String {
    [
      contenderTitle,
      "Tournament \(tournamentID)",
      "Round \(roundID)",
      "Experiment \(experimentID)",
      "Branch \(branchName)",
      "Worktree \(worktreeID)",
      "Audit \(revisionAuditID)",
      revisionScenarioID.map { "Scenario \($0)" } ?? "Scenario unknown",
      validationSummary,
      "Next step: \(nextStepSummary)",
      nextStepDetail,
      "Resolved gaps: \(resolvedGapSummary)",
      "Persisted gaps: \(persistedGapSummary)",
      "Next validation: \(result.nextValidationTarget)",
    ]
    .joined(separator: "\n")
  }
}

enum ProductTournamentRoundThreeImplementationRevisionValidationOverview {
  static func items(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    limit: Int = 5,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable
  ) -> [ProductTournamentRoundThreeImplementationRevisionValidationOverviewItem] {
    guard limit > 0 else { return [] }
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

    return ProductTournamentRoundThreeImplementationRevisionValidationAdvisor.results(
      config: config,
      evidenceIndex: evidenceIndex,
      limit: max(limit * 3, 12)
    )
    .compactMap { result in
      guard
        let contender = config.tournamentContenders.first(where: {
          $0.id == result.contenderID && $0.tournamentID == result.tournamentID
        }),
        let experiment = config.tournamentExperiments.first(where: {
          $0.id == result.experimentID
        })
      else { return nil }

      return ProductTournamentRoundThreeImplementationRevisionValidationOverviewItem(
        result: result,
        contenderTitle: contender.title,
        experimentTitle: experiment.title,
        branchName: experiment.branchName,
        worktreeID: experiment.worktreeID,
        nextStep: nextStepsByExperimentID[result.experimentID]
      )
    }
    .sorted { lhs, rhs in
      if outcomeRank(lhs.outcome) == outcomeRank(rhs.outcome) {
        if lhs.result.revisionEndedAt == rhs.result.revisionEndedAt {
          return lhs.contenderID < rhs.contenderID
        }
        return lhs.result.revisionEndedAt > rhs.result.revisionEndedAt
      }
      return outcomeRank(lhs.outcome) < outcomeRank(rhs.outcome)
    }
    .prefix(limit)
    .map { $0 }
  }

  private static func outcomeRank(
    _ outcome: ProductTournamentRoundThreeImplementationRevisionValidationOutcome
  ) -> Int {
    switch outcome {
    case .pendingValidation:
      return 0
    case .partialValidation:
      return 1
    case .persisted:
      return 2
    case .eliminated:
      return 3
    case .resolved:
      return 4
    }
  }
}
