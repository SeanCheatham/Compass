import Foundation

enum ProductTournamentLaneStatus: String, Codable, CaseIterable, Equatable, Sendable {
  case idle
  case needsPlan
  case needsWorktree
  case building
  case awaitingLLM
  case runningEvidence
  case verifying
  case readyForDecision
  case awaitingPeers
  case blocked
  case finished

  var label: String {
    switch self {
    case .idle: return "Idle"
    case .needsPlan: return "Needs plan"
    case .needsWorktree: return "Needs worktree"
    case .building: return "Building"
    case .awaitingLLM: return "Awaiting LLM"
    case .runningEvidence: return "Running evidence"
    case .verifying: return "Verifying"
    case .readyForDecision: return "Ready for decision"
    case .awaitingPeers: return "Awaiting peers"
    case .blocked: return "Blocked"
    case .finished: return "Finished"
    }
  }
}

struct ProductTournamentLaneState: Codable, Equatable, Identifiable, Sendable {
  var id: String { experimentID }

  var experimentID: String
  var experimentTitle: String
  var contenderID: String?
  var contenderTitle: String?
  var branchName: String
  var worktreeID: String
  var currentCommit: String?
  var baseCommit: String?
  var status: ProductTournamentLaneStatus
  var activeStepID: String?
  var blockedReason: String?
  var latestEvidenceIDs: [String]
  var proofDebtSummary: String
  var updatedAt: Double

  init(
    experimentID: String,
    experimentTitle: String,
    contenderID: String?,
    contenderTitle: String?,
    branchName: String,
    worktreeID: String,
    currentCommit: String?,
    baseCommit: String?,
    status: ProductTournamentLaneStatus,
    activeStepID: String?,
    blockedReason: String?,
    latestEvidenceIDs: [String],
    proofDebtSummary: String,
    updatedAt: Double
  ) {
    self.experimentID = ProductTournamentModelText.identifier(
      experimentID,
      fallback: "experiment"
    )
    self.experimentTitle = ProductTournamentModelText.cleanedText(
      experimentTitle,
      fallback: "Tournament experiment",
      limit: 180
    )
    self.contenderID = ProductTournamentModelText.optionalIdentifier(
      contenderID,
      fallback: "contender"
    )
    self.contenderTitle = ProductTournamentModelText.optionalCleanedText(
      contenderTitle,
      limit: 180
    )
    self.branchName = ProductTournamentModelText.cleanedText(
      branchName,
      fallback: "codex/product-experiment",
      limit: 240
    )
    self.worktreeID = ProductTournamentModelText.identifier(worktreeID, fallback: "worktree")
    self.currentCommit = ProductTournamentModelText.optionalCleanedText(currentCommit, limit: 80)
    self.baseCommit = ProductTournamentModelText.optionalCleanedText(baseCommit, limit: 80)
    self.status = status
    self.activeStepID = ProductTournamentModelText.optionalCleanedText(activeStepID, limit: 260)
    self.blockedReason = ProductTournamentModelText.optionalCleanedText(blockedReason, limit: 700)
    self.latestEvidenceIDs = ProductTournamentModelText.cleanedList(latestEvidenceIDs, limit: 140)
    self.proofDebtSummary = ProductTournamentModelText.cleanedText(
      proofDebtSummary,
      fallback: "Proof debt unavailable.",
      limit: 600
    )
    self.updatedAt = updatedAt
  }
}

enum ProductTournamentLaneStateBuilder {
  static func lanes(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    isPersonaModelAvailable: Bool = FoundationModelsAvailability.isAvailable,
    now: Date = Date()
  ) -> [ProductTournamentLaneState] {
    let steps = TournamentAutomationPlanner.steps(
      config: config,
      evidenceIndex: evidenceIndex,
      isPersonaModelAvailable: isPersonaModelAvailable
    )
    return lanes(
      config: config,
      evidenceIndex: evidenceIndex,
      steps: steps,
      now: now
    )
  }

  static func lanes(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    steps: [TournamentAutomationStep],
    now: Date = Date()
  ) -> [ProductTournamentLaneState] {
    let stepsByExperiment = Dictionary(uniqueKeysWithValues: steps.map { ($0.experimentID, $0) })
    let orderedExperimentIDs = orderedLaneExperimentIDs(
      experiments: config.tournamentExperiments,
      steps: steps
    )
    let experimentsByID = Dictionary(uniqueKeysWithValues: config.tournamentExperiments.map {
      ($0.id, $0)
    })

    return orderedExperimentIDs.compactMap { experimentID in
      guard let experiment = experimentsByID[experimentID] else { return nil }
      let step = stepsByExperiment[experiment.id]
      let contender = config.tournamentContenders.first { $0.experimentID == experiment.id }
      let contenderPlan = config.contenderPlans.first {
        $0.id == contender?.contenderPlanID || $0.id == experiment.contenderPlanID
      }
      let proofDebt = TournamentAutomationProofDebtSnapshotter.snapshot(
        forExperimentID: experiment.id,
        config: config,
        evidenceIndex: evidenceIndex,
        preferredStep: step
      )

      return ProductTournamentLaneState(
        experimentID: experiment.id,
        experimentTitle: experiment.title,
        contenderID: contender?.id,
        contenderTitle: contenderPlan?.title,
        branchName: experiment.branchName,
        worktreeID: experiment.worktreeID,
        currentCommit: experiment.currentSha,
        baseCommit: experiment.baseSha,
        status: status(for: experiment, step: step),
        activeStepID: step?.id,
        blockedReason: blockedReason(for: step),
        latestEvidenceIDs: latestEvidenceIDs(
          experiment: experiment,
          contenderID: contender?.id,
          evidenceIndex: evidenceIndex
        ),
        proofDebtSummary: proofDebt?.summary ?? "No active proof debt snapshot.",
        updatedAt: max(experiment.updatedAt, evidenceIndex.updatedAt, now.timeIntervalSince1970)
      )
    }
  }

  private static func orderedLaneExperimentIDs(
    experiments: [ProductTournamentExperiment],
    steps: [TournamentAutomationStep]
  ) -> [String] {
    var ordered: [String] = []
    for step in steps where !ordered.contains(step.experimentID) {
      ordered.append(step.experimentID)
    }
    for experiment in experiments.sorted(by: experimentSort) where !ordered.contains(experiment.id) {
      ordered.append(experiment.id)
    }
    return ordered
  }

  private static func experimentSort(
    lhs: ProductTournamentExperiment,
    rhs: ProductTournamentExperiment
  ) -> Bool {
    if lhs.updatedAt == rhs.updatedAt { return lhs.id < rhs.id }
    return lhs.updatedAt > rhs.updatedAt
  }

  private static func status(
    for experiment: ProductTournamentExperiment,
    step: TournamentAutomationStep?
  ) -> ProductTournamentLaneStatus {
    switch experiment.decision {
    case .archived, .promoted:
      return .finished
    case .notRun, .keepGoing, .narrow, .pivot, .kill, .promote:
      break
    }

    guard let step else { return .idle }
    guard step.canExecute else { return .blocked }

    switch step.kind {
    case .prepareWorktree:
      return .needsWorktree
    case .runPlanProof:
      return step.action.requiredSimulationMode == .personaModel ? .awaitingLLM : .needsPlan
    case .runCohort:
      return step.action.requiredSimulationMode == .personaModel ? .awaitingLLM : .runningEvidence
    case .applyDecision, .applyRoundTransition:
      return .readyForDecision
    case .applyRevision:
      return .building
    case .blocked:
      return .blocked
    }
  }

  private static func blockedReason(for step: TournamentAutomationStep?) -> String? {
    guard let step else { return nil }
    if let blockedReason = step.blockedReason { return blockedReason }
    return step.canExecute ? nil : step.detail
  }

  private static func latestEvidenceIDs(
    experiment: ProductTournamentExperiment,
    contenderID: String?,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [String] {
    var ids: [String] = []
    if let runID = evidenceIndex.aggregate.latestRunByExperiment[experiment.id] {
      ids.append(runID)
    }
    if let contenderID,
      let evaluationID = evidenceIndex.aggregate.latestPlanEvaluationByContender[contenderID]
    {
      ids.append(evaluationID)
    }
    return ids
  }
}
