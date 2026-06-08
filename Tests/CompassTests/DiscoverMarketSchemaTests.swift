import Foundation
import Testing

@testable import Compass

struct DiscoverMarketSchemaTests {
  @Test func discoverSchemaAcceptsMarketEdits() throws {
    let config = seededMarketConfig()
    let decoded = try Prompts.decodeDiscoverResponse(discoverJSON(for: config))

    let applied = try decoded.validatedProductTournamentConfig(applyingTo: .empty)
    try #require(applied.markets.count == 1)
    try #require(applied.markets[0].actors.contains { $0.role == .economicBuyer })
    try #require(applied.markets[0].buyingCommittees[0].actorIDs.count >= 2)
  }

  @Test func discoverOutputRejectsMissingCommitteeActorReference() throws {
    var config = seededMarketConfig()
    config.markets[0].buyingCommittees[0].actorIDs.append("missing-actor")

    #expect(throws: DiscoverPromptValidationError.self) {
      _ = try Prompts.decodeDiscoverResponse(discoverJSON(for: config))
    }
  }

  @Test func discoverOutputRejectsBudgetBuyerWithNonBuyerRole() throws {
    var config = seededMarketConfig()
    let operatorID = try #require(config.markets[0].actors.first { $0.role == .operator }?.id)
    config.markets[0].budgetModels[0].buyerActorID = operatorID

    #expect(throws: DiscoverPromptValidationError.self) {
      _ = try Prompts.decodeDiscoverResponse(discoverJSON(for: config))
    }
  }

  @Test func channelsReferenceValidMarkets() throws {
    var config = seededMarketConfig()
    config.markets[0].channels[0].marketID = "missing-market"

    #expect(throws: DiscoverPromptValidationError.self) {
      _ = try Prompts.decodeDiscoverResponse(discoverJSON(for: config))
    }
  }

  private func seededMarketConfig() -> ProductTournamentConfig {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Market Validator",
      rawPain: "Team leads cannot tell which blocked handoffs are budget-worthy.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    config.contenderPlans = []
    config.tournamentExperiments = []
    config.tournaments = []
    config.tournamentContenders = []
    config.tournamentRounds = []
    config.scenarioCohorts = []
    config.decisions = []
    return config
  }

  private func discoverJSON(for config: ProductTournamentConfig) throws -> String {
    let output = DiscoverPromptOutput(
      summary: "Compiled synthetic market.",
      stateEdits: DiscoveryStateEdits(
        rawPain: config.rawPain,
        painHypotheses: config.painHypotheses,
        userSegments: config.userSegments,
        currentWorkflows: config.currentWorkflows,
        alternatives: config.alternatives,
        markets: config.markets,
        contenderPlans: config.contenderPlans,
        tournamentExperiments: config.tournamentExperiments,
        tournaments: config.tournaments,
        tournamentContenders: config.tournamentContenders,
        tournamentRounds: config.tournamentRounds,
        scenarioCohorts: config.scenarioCohorts,
        decisions: config.decisions
      ),
      candidateTournamentExperiments: [],
      openQuestions: [],
      lessonEdits: [],
      assumptions: []
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(output), as: UTF8.self)
  }
}
