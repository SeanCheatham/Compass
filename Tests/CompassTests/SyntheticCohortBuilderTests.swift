import Foundation
import Testing

@testable import Compass

struct SyntheticCohortBuilderTests {
  @Test func createsDefaultLifecycleStages() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 100)
    )
    let contenderID = try #require(config.tournamentContenders.first?.id)

    let result = try SyntheticCohortBuilder.build(contenderID: contenderID, in: config)

    try #require(result.scenarios.count >= 7)
    try #require(result.cohort.lifecycleScenarioIDs == result.scenarios.map(\.id))
    try #require(result.scenarios.contains { $0.task.lowercased().contains("come back") })
    try #require(result.scenarios.contains { $0.task.lowercased().contains("renew") })
  }

  @Test func secondUseStageIncludesCurrentAlternative() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 100)
    )
    let result = try SyntheticCohortBuilder.build(
      contenderID: try #require(config.tournamentContenders.first?.id),
      in: config
    )

    let secondUse = try #require(result.scenarios.first { $0.stageID.contains("second-use") })

    try #require(secondUse.task.contains("Manual workflow plus shared document"))
    try #require(secondUse.task.lowercased().contains("market comes back"))
  }

  @Test func budgetStageTargetsBuyerActor() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 100)
    )
    let buyerID = try #require(
      config.markets.first?.actors.first { $0.role == .economicBuyer }?.id
    )
    let result = try SyntheticCohortBuilder.build(
      contenderID: try #require(config.tournamentContenders.first?.id),
      in: config
    )

    let budget = try #require(result.scenarios.first { $0.stageID.contains("budget") })

    try #require(budget.task.contains(buyerID))
    try #require(budget.task.lowercased().contains("payment"))
  }
}
