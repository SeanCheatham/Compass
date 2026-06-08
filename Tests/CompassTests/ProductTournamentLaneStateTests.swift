import Foundation
import Testing

@testable import Compass

struct ProductTournamentLaneStateTests {
  @Test func derivesNeedsPlanLanesFromNoEvidence() throws {
    let config = makeLaneConfig()
    let lanes = ProductTournamentLaneStateBuilder.lanes(
      config: config,
      evidenceIndex: .empty,
      isPersonaModelAvailable: false,
      now: Date(timeIntervalSince1970: 100)
    )

    try #require(lanes.count == config.tournamentExperiments.count)
    try #require(lanes.allSatisfy { $0.status == .needsPlan })
    try #require(lanes.allSatisfy { $0.activeStepID?.contains("run_plan_proof") == true })
    try #require(lanes[0].proofDebtSummary.contains("Round 1 plan proof"))
  }

  @Test func derivesNeedsWorktreeLaneFromPrepareStep() throws {
    var config = makeLaneConfig()
    let experiment = config.tournamentExperiments[0]
    config.tournamentExperiments[0].currentSha = nil
    let step = makeStep(
      experiment: experiment,
      kind: .prepareWorktree,
      title: "Prepare product worktree"
    )

    let lane = try #require(
      ProductTournamentLaneStateBuilder.lanes(
        config: config,
        evidenceIndex: .empty,
        steps: [step]
      ).first { $0.experimentID == experiment.id })

    try #require(lane.status == .needsWorktree)
    try #require(lane.currentCommit == nil)
    try #require(lane.branchName == experiment.branchName)
  }

  @Test func derivesRunningEvidenceLaneFromRunnableCohort() throws {
    var config = makeLaneConfig()
    config.tournamentExperiments[0].currentSha = "head-sha"
    let experiment = config.tournamentExperiments[0]
    let step = makeCohortStep(experiment: experiment, canRun: true)

    let lane = try #require(
      ProductTournamentLaneStateBuilder.lanes(
        config: config,
        evidenceIndex: .empty,
        steps: [step]
      ).first { $0.experimentID == experiment.id })

    try #require(lane.status == .runningEvidence)
    try #require(lane.activeStepID == step.id)
    try #require(lane.blockedReason == nil)
  }

  @Test func derivesBlockedLaneFromRefineContenderAction() throws {
    let config = makeLaneConfig()
    let experiment = config.tournamentExperiments[0]
    let step = makeStep(
      experiment: experiment,
      kind: .refineContender,
      title: "Refine contender",
      detail: "Needs a sharper target segment before more evidence."
    )

    let lane = try #require(
      ProductTournamentLaneStateBuilder.lanes(
        config: config,
        evidenceIndex: .empty,
        steps: [step]
      ).first { $0.experimentID == experiment.id })

    try #require(lane.status == .blocked)
    try #require(lane.blockedReason?.contains("sharper target segment") == true)
  }

  @Test func derivesReadyForDecisionLaneFromDecisionAction() throws {
    let config = makeLaneConfig()
    let experiment = config.tournamentExperiments[0]
    let step = makeStep(
      experiment: experiment,
      kind: .applyDecision,
      title: "Apply tournament decision",
      targetDecision: .promote
    )

    let lane = try #require(
      ProductTournamentLaneStateBuilder.lanes(
        config: config,
        evidenceIndex: .empty,
        steps: [step]
      ).first { $0.experimentID == experiment.id })

    try #require(lane.status == .readyForDecision)
    try #require(lane.activeStepID?.contains("target_decision:promote") == true)
  }

  @Test func planningDigestSummarizesTournamentLanes() throws {
    let config = makeLaneConfig()
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: .empty
    )

    try #require(digest.contains("Tournament lanes:"))
    try #require(digest.contains("status"))
    try #require(digest.contains("active_step"))
  }
}

private func makeLaneConfig() -> ProductTournamentConfig {
  ProductTournamentConfig.seedDefaults(
    projectTitle: "LedgerLift",
    rawPain: "Finance operators lose weekly reporting context between Slack and spreadsheets.",
    now: Date(timeIntervalSince1970: 10)
  )
}

private func makeStep(
  experiment: ProductTournamentExperiment,
  kind: ProductTournamentNextActionKind,
  title: String,
  detail: String = "Test automation step.",
  targetDecision: ProductTournamentExperimentDecision? = nil
) -> TournamentAutomationStep {
  TournamentAutomationStep(
    experiment: experiment,
    action: ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: kind,
      title: title,
      detail: detail,
      priority: 100,
      targetDecision: targetDecision
    ),
    cohortReadiness: nil,
    isPersonaModelAvailable: true
  )
}

private func makeCohortStep(
  experiment: ProductTournamentExperiment,
  canRun: Bool
) -> TournamentAutomationStep {
  TournamentAutomationStep(
    experiment: experiment,
    action: ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: .runCohort,
      title: "Run evidence cohort",
      detail: "Run the enabled cohort.",
      priority: 90,
      cohortID: "cohort-a",
      requiredSimulationMode: .modelFree
    ),
    cohortReadiness: ProductTournamentCohortRunReadiness(
      cohortID: "cohort-a",
      cohortTitle: "Cohort A",
      cohortEnabled: true,
      enabledScenarioCount: canRun ? 2 : 0,
      missingTargetCommitCount: 0
    ),
    isPersonaModelAvailable: true
  )
}
