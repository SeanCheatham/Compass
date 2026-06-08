import Foundation
import Testing

@testable import Compass

struct ProductTournamentPortfolioSchedulerTests {
  @Test func selectsHighPriorityWorkAndDefersByCycleCap() throws {
    let config = makePortfolioSchedulerConfig()
    let first = config.tournamentExperiments[0]
    let second = config.tournamentExperiments[1]
    let lowPriorityEvidence = makeSchedulerCohortStep(experiment: first, priority: 40)
    let highPriorityWorktree = makeSchedulerStep(
      experiment: second,
      kind: .prepareWorktree,
      title: "Prepare worktree",
      priority: 100
    )

    let schedule = TournamentPortfolioScheduler.schedule(
      steps: [lowPriorityEvidence, highPriorityWorktree],
      config: config,
      evidenceIndex: .empty,
      maxSteps: 1
    )

    try #require(schedule.selectedWork.map(\.stepID) == [highPriorityWorktree.id])
    try #require(schedule.deferredWork.map(\.stepID).contains(lowPriorityEvidence.id))
    try #require(schedule.deferredSummary.contains("capped at 1 step"))
  }

  @Test func mapsStepKindsToSchedulerResources() throws {
    let config = makePortfolioSchedulerConfig()
    let experiment = config.tournamentExperiments[0]
    let worktree = makeSchedulerStep(
      experiment: experiment,
      kind: .prepareWorktree,
      title: "Prepare worktree",
      priority: 100
    )
    let cohort = makeSchedulerCohortStep(experiment: experiment, priority: 90)

    let schedule = TournamentPortfolioScheduler.schedule(
      steps: [worktree, cohort],
      config: config,
      evidenceIndex: .empty,
      maxSteps: 2
    )

    let worktreeWork = try #require(schedule.selectedWork.first { $0.stepID == worktree.id })
    let cohortWork = try #require(schedule.selectedWork.first { $0.stepID == cohort.id })
    try #require(worktreeWork.resourceKind == .stateWriter)
    try #require(worktreeWork.additionalResourceKinds == [.build])
    try #require(worktreeWork.conflictKeys.contains("worktree:\(experiment.worktreeID)"))
    try #require(cohortWork.resourceKind == .scenarioSimulation)
    try #require(cohortWork.additionalResourceKinds.isEmpty)
  }

  @Test func defersSecondMutableStepForSameLane() throws {
    let config = makePortfolioSchedulerConfig()
    let experiment = config.tournamentExperiments[0]
    let promote = makeSchedulerStep(
      experiment: experiment,
      kind: .applyDecision,
      title: "Promote",
      priority: 100,
      targetDecision: .promote
    )
    let kill = makeSchedulerStep(
      experiment: experiment,
      kind: .applyDecision,
      title: "Kill",
      priority: 90,
      targetDecision: .kill
    )

    let schedule = TournamentPortfolioScheduler.schedule(
      steps: [promote, kill],
      config: config,
      evidenceIndex: .empty,
      maxSteps: 3
    )

    try #require(schedule.selectedWork.map(\.stepID) == [promote.id])
    let deferred = try #require(schedule.deferredWork.first { $0.stepID == kill.id })
    try #require(deferred.blockedReason?.contains("another mutable step") == true)
  }

  @Test func plannerCyclePlanUsesPortfolioScheduleSelection() throws {
    let config = makePortfolioSchedulerConfig()
    let schedule = TournamentAutomationPlanner.portfolioSchedule(
      config: config,
      evidenceIndex: .empty,
      maxSteps: 1,
      isPersonaModelAvailable: false
    )
    let cyclePlan = TournamentAutomationPlanner.cyclePlan(
      config: config,
      evidenceIndex: .empty,
      maxSteps: 1,
      isPersonaModelAvailable: false
    )

    try #require(cyclePlan.executableSteps == schedule.selectedWork.map(\.step))
    try #require(cyclePlan.capped)
  }

  @Test func planningDigestIncludesPortfolioSchedulePreview() throws {
    let config = makePortfolioSchedulerConfig()
    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: .empty
    )

    try #require(digest.contains("Tournament portfolio schedule:"))
    try #require(digest.contains("selected"))
    try #require(digest.contains("active_resources"))
  }
}

private func makePortfolioSchedulerConfig() -> ProductTournamentConfig {
  ProductTournamentConfig.seedDefaults(
    projectTitle: "LedgerLift",
    rawPain: "Finance operators lose weekly reporting context between Slack and spreadsheets.",
    now: Date(timeIntervalSince1970: 10)
  )
}

private func makeSchedulerStep(
  experiment: ProductTournamentExperiment,
  kind: ProductTournamentNextActionKind,
  title: String,
  priority: Int,
  targetDecision: ProductTournamentExperimentDecision? = nil
) -> TournamentAutomationStep {
  TournamentAutomationStep(
    experiment: experiment,
    action: ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: kind,
      title: title,
      detail: "Scheduler test step.",
      priority: priority,
      targetDecision: targetDecision
    ),
    cohortReadiness: nil,
    isPersonaModelAvailable: true
  )
}

private func makeSchedulerCohortStep(
  experiment: ProductTournamentExperiment,
  priority: Int
) -> TournamentAutomationStep {
  TournamentAutomationStep(
    experiment: experiment,
    action: ProductTournamentNextAction(
      experimentID: experiment.id,
      kind: .runCohort,
      title: "Run cohort",
      detail: "Run model-free cohort.",
      priority: priority,
      cohortID: "cohort-a",
      requiredSimulationMode: .modelFree
    ),
    cohortReadiness: ProductTournamentCohortRunReadiness(
      cohortID: "cohort-a",
      cohortTitle: "Cohort A",
      cohortEnabled: true,
      enabledScenarioCount: 2,
      missingTargetCommitCount: 0
    ),
    isPersonaModelAvailable: true
  )
}
