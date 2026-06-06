struct TournamentAutomationCycleWorkbenchFacts: Equatable, Sendable {
  var latestCycleSummary: String
  var latestCycleHelp: String
  var latestPreparationSummary: String?
  var latestPreparationHelp: String?
  var latestEvidenceSummary: String
  var latestEvidenceHelp: String?
  var postPreparationEvidenceSummary: String?
  var postPreparationEvidenceHelp: String?

  static func latest(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    currentStep: TournamentAutomationStep? = nil
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

    return TournamentAutomationCycleWorkbenchFacts(
      latestCycleSummary: latestAudit.summary,
      latestCycleHelp: helpSummary(for: latestAudit),
      latestPreparationSummary: latestPreparationSummary,
      latestPreparationHelp: latestPreparationHelp,
      latestEvidenceSummary: evidenceAudit.map(makeEvidenceSummary(for:)) ?? "none recorded",
      latestEvidenceHelp: evidenceAudit.map(helpSummary(for:)),
      postPreparationEvidenceSummary: postPreparationEvidence?.summary,
      postPreparationEvidenceHelp: postPreparationEvidence?.help
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

  private static func bounded(_ value: String, limit: Int) -> String {
    StringUtils.boundedText(value, limit: limit)
  }
}
