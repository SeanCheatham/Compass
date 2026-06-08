import Foundation
import Testing

@testable import Compass

struct TournamentAsyncEvidenceExecutorTests {
  @Test func runsIndependentEvidenceWorkConcurrently() async throws {
    let config = makeAsyncEvidenceConfig()
    let schedule = makeAsyncEvidenceSchedule(config: config)
    let recorder = AsyncEvidenceCompletionRecorder()
    let executor = TournamentAsyncEvidenceExecutor(
      limits: TournamentEvidenceConcurrencyLimits(
        totalEvidenceTasks: 2,
        personaModelLLMTasks: 1,
        modelFreeSimulationTasks: 2
      )
    )
    let firstStepID = schedule.selectedWork[0].stepID
    let secondStepID = schedule.selectedWork[1].stepID

    let outcome = await executor.run(
      schedule: schedule,
      now: Date(timeIntervalSince1970: 200)
    ) { work in
      if work.stepID == firstStepID {
        try await Task.sleep(nanoseconds: 100_000_000)
      } else {
        try await Task.sleep(nanoseconds: 10_000_000)
      }
      await recorder.record(work.stepID)
      return TournamentAutomationStepResult(
        message: "Completed \(work.laneID)",
        executedStepID: work.stepID,
        evidenceRunIDs: ["run-\(work.laneID)"],
        completedEvidenceRunCount: 1
      )
    }

    let completionOrder = await recorder.values()
    try #require(completionOrder == [secondStepID, firstStepID])
    try #require(outcome.completedResults.count == 2)
    try #require(outcome.failedWork.isEmpty)
    try #require(outcome.shouldRefreshEvidenceIndex)
    try #require(outcome.audits.filter { $0.status == .started }.count == 2)
    try #require(outcome.audits.filter { $0.status == .completed }.count == 2)
  }

  @Test func skipsSuccessfulEvidenceWorkOnRetry() async throws {
    let config = makeAsyncEvidenceConfig()
    let schedule = makeAsyncEvidenceSchedule(config: config)
    let executor = TournamentAsyncEvidenceExecutor()

    let first = await executor.run(schedule: schedule) { work in
      TournamentAutomationStepResult(
        message: "Completed \(work.laneID)",
        executedStepID: work.stepID,
        evidenceRunIDs: ["run-\(work.laneID)"],
        completedEvidenceRunCount: 1
      )
    }
    let second = await executor.run(schedule: schedule) { work in
      TournamentAutomationStepResult(
        message: "Should not run \(work.laneID)",
        executedStepID: work.stepID,
        evidenceRunIDs: ["duplicate-\(work.laneID)"],
        completedEvidenceRunCount: 1
      )
    }

    try #require(first.completedResults.count == 2)
    try #require(second.completedResults.isEmpty)
    try #require(second.skippedWork.count == 2)
    try #require(!second.shouldRefreshEvidenceIndex)
  }

  @Test func failedEvidenceWorkDoesNotCancelSuccessfulPeer() async throws {
    let config = makeAsyncEvidenceConfig()
    let schedule = makeAsyncEvidenceSchedule(config: config)
    let executor = TournamentAsyncEvidenceExecutor()
    let failingStepID = schedule.selectedWork[0].stepID

    let outcome = await executor.run(schedule: schedule) { work in
      if work.stepID == failingStepID {
        throw AsyncEvidenceTestError.intentionalFailure
      }
      return TournamentAutomationStepResult(
        message: "Completed \(work.laneID)",
        executedStepID: work.stepID,
        evidenceRunIDs: ["run-\(work.laneID)"],
        completedEvidenceRunCount: 1
      )
    }

    try #require(outcome.completedResults.count == 1)
    try #require(outcome.failedWork.map(\.stepID) == [failingStepID])
    try #require(outcome.audits.contains { $0.status == .failed })
    try #require(outcome.audits.contains { $0.status == .completed })
  }
}

private actor AsyncEvidenceCompletionRecorder {
  private var recorded: [String] = []

  func record(_ value: String) {
    recorded.append(value)
  }

  func values() -> [String] {
    recorded
  }
}

private enum AsyncEvidenceTestError: Error {
  case intentionalFailure
}

private func makeAsyncEvidenceConfig() -> ProductTournamentConfig {
  var config = ProductTournamentConfig.seedDefaults(
    projectTitle: "LedgerLift",
    rawPain: "Finance operators lose weekly reporting context between Slack and spreadsheets.",
    now: Date(timeIntervalSince1970: 10)
  )
  for index in config.tournamentExperiments.indices {
    config.tournamentExperiments[index].currentSha = "head-\(index)"
  }
  return config
}

private func makeAsyncEvidenceSchedule(
  config: ProductTournamentConfig
) -> TournamentPortfolioSchedule {
  let steps = config.tournamentExperiments.enumerated().map { index, experiment in
    TournamentAutomationStep(
      experiment: experiment,
      action: ProductTournamentNextAction(
        experimentID: experiment.id,
        kind: .runCohort,
        title: "Run cohort \(index)",
        detail: "Run model-free cohort.",
        priority: 100 - index,
        cohortID: "cohort-\(index)",
        requiredSimulationMode: .modelFree
      ),
      cohortReadiness: ProductTournamentCohortRunReadiness(
        cohortID: "cohort-\(index)",
        cohortTitle: "Cohort \(index)",
        cohortEnabled: true,
        enabledScenarioCount: 1,
        missingTargetCommitCount: 0
      ),
      isPersonaModelAvailable: true
    )
  }
  return TournamentPortfolioScheduler.schedule(
    steps: steps,
    config: config,
    evidenceIndex: .empty,
    maxSteps: 2
  )
}
