import Foundation
import Testing

@testable import Compass

struct MarketCompilerValidationTests {
  @Test func acceptsMinimalValidSyntheticMarket() throws {
    let fixture = marketCompilerFixture()
    let output = MarketCompilerOutput(
      summary: "Compiled market.",
      status: .compiled,
      marketEdits: fixture.compiled.markets,
      contenderSeeds: [fixture.seed]
    )

    let next = try output.applying(to: fixture.base)
    try #require(next.markets.count == 1)
    try #require(next.marketCompilationStatus == .compiled)
  }

  @Test func applyingCompilerOutputIgnoresDistributionExperimentEdits() throws {
    var fixture = marketCompilerFixture()
    fixture.base.distributionExperiments = []
    let legacyDistribution = try #require(fixture.compiled.distributionExperiments.first)
    let output = MarketCompilerOutput(
      summary: "Compiled proof seed.",
      status: .compiled,
      marketEdits: fixture.compiled.markets,
      distributionExperimentEdits: [legacyDistribution]
    )

    let next = try output.applying(to: fixture.base)

    try #require(next.markets.count == 1)
    try #require(next.distributionExperiments.isEmpty)
  }

  @Test func rejectsCommitteeActorIDsThatDoNotExist() throws {
    var fixture = marketCompilerFixture()
    fixture.compiled.markets[0].buyingCommittees[0].actorIDs.append("missing-actor")
    let output = MarketCompilerOutput(
      summary: "Bad committee.",
      status: .compiled,
      marketEdits: fixture.compiled.markets
    )

    #expect(throws: DiscoverPromptValidationError.self) {
      _ = try output.applying(to: fixture.base)
    }
  }

  @Test func rejectsChannelsWithoutMatchingMarketIDs() throws {
    var fixture = marketCompilerFixture()
    fixture.compiled.markets[0].channels[0].marketID = "other-market"
    let output = MarketCompilerOutput(
      summary: "Bad channel.",
      status: .compiled,
      marketEdits: fixture.compiled.markets
    )

    #expect(throws: DiscoverPromptValidationError.self) {
      _ = try output.applying(to: fixture.base)
    }
  }

  @Test func rejectsContenderSeedsWithoutMarketIDs() throws {
    let fixture = marketCompilerFixture()
    var seed = fixture.seed
    seed.marketID = "missing-market"
    let output = MarketCompilerOutput(
      summary: "Bad seed.",
      status: .compiled,
      marketEdits: fixture.compiled.markets,
      contenderSeeds: [seed]
    )

    #expect(throws: DiscoverPromptValidationError.self) {
      _ = try output.applying(to: fixture.base)
    }
  }

  @Test func rejectsBudgetBuyerThatIsNotBuyerOrSponsor() throws {
    var fixture = marketCompilerFixture()
    let operatorID = try #require(
      fixture.compiled.markets[0].actors.first { $0.role == .operator }?.id)
    fixture.compiled.markets[0].budgetModels[0].buyerActorID = operatorID
    let output = MarketCompilerOutput(
      summary: "Bad budget.",
      status: .compiled,
      marketEdits: fixture.compiled.markets
    )

    #expect(throws: DiscoverPromptValidationError.self) {
      _ = try output.applying(to: fixture.base)
    }
  }
}

private func marketCompilerFixture() -> (
  base: ProductTournamentConfig, compiled: ProductTournamentConfig, seed: MarketContenderSeed
) {
  var compiled = ProductTournamentConfig.seedDefaults(
    projectTitle: "Market Compiler",
    rawPain: "Operations leads lose weekly handoff context.",
    now: Date(timeIntervalSince1970: 1_700_000_000)
  )
  var base = compiled
  base.markets = []
  let market = compiled.markets[0]
  let seed = MarketContenderSeed(
    id: "handoff-proof-seed",
    marketID: market.id,
    targetActorIDs: [market.actors[0].id],
    promise: "Preserve handoff proof for the operator.",
    wedge: "Start with one recurring handoff moment.",
    likelyBuyerActorID: market.actors.first { $0.role == .economicBuyer }?.id,
    likelyChannelID: market.channels.first?.id,
    incumbentToBeatID: market.incumbents.first?.id,
    requiredMarketProof: ["Buying committee accepts the pilot."]
  )
  compiled.contenderPlans = []
  compiled.tournamentExperiments = []
  compiled.tournaments = []
  compiled.tournamentContenders = []
  compiled.tournamentRounds = []
  compiled.scenarioCohorts = []
  compiled.decisions = []
  base.contenderPlans = []
  base.tournamentExperiments = []
  base.tournaments = []
  base.tournamentContenders = []
  base.tournamentRounds = []
  base.scenarioCohorts = []
  base.decisions = []
  return (base, compiled, seed)
}
