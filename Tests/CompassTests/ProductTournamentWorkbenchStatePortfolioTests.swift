import Foundation
import Testing

@testable import Compass

struct ProductTournamentWorkbenchStatePortfolioTests {
  @Test func workbenchStateBuildsLaneScheduleBarrierAndRolloutSnapshot() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "LedgerLift",
      rawPain: "Finance operators lose weekly reporting context between Slack and spreadsheets.",
      now: Date(timeIntervalSince1970: 10)
    )
    let flags = CompassRuntimeFeatureFlags(environment: [
      "COMPASS_TOURNAMENT_SCHEDULER_PREVIEW": "1",
      "COMPASS_TOURNAMENT_PARALLEL_EVIDENCE": "1",
    ])

    let state = ProductTournamentWorkbenchState.build(
      config: config,
      evidenceIndex: ProductTournamentEvidenceIndex(updatedAt: 20),
      isPersonaModelAvailable: false,
      rolloutFlags: flags
    )

    try #require(state.laneStates.count == config.tournamentExperiments.count)
    try #require(!state.portfolioSchedule.selectedWork.isEmpty)
    try #require(!state.judgingBarriers.isEmpty)
    try #require(state.rolloutFlags.tournamentSchedulerPreview)
    try #require(state.rolloutFlags.tournamentParallelEvidence)
    try #require(!state.rolloutFlags.tournamentParallelDevelop)
  }
}
