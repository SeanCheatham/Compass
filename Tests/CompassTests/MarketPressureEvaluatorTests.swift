import Foundation
import Testing

@testable import Compass

struct MarketPressureEvaluatorTests {
  @Test func modelFreeBuyingCommitteeProducesDeterministicScores() throws {
    let config = pressureFixture()
    let market = try #require(config.markets.first)
    let contender = try #require(config.tournamentContenders.first)
    let first = MarketPressureEvaluator.evaluate(
      kind: .buyingCommittee,
      market: market,
      contender: contender,
      tournamentID: contender.tournamentID,
      roundID: config.tournamentRounds.first?.id,
      now: Date(timeIntervalSince1970: 100)
    )
    let second = MarketPressureEvaluator.evaluate(
      kind: .buyingCommittee,
      market: market,
      contender: contender,
      tournamentID: contender.tournamentID,
      roundID: config.tournamentRounds.first?.id,
      now: Date(timeIntervalSince1970: 100)
    )

    try #require(first == second)
    try #require(first.pressureKind == .buyingCommittee)
    try #require(first.scores.buyerClarity >= 2)
    try #require(!first.requiredNextProof.isEmpty)
  }

  @Test func incumbentDefenseIncreasesIncumbentDebtWhenCurrentAlternativeWins() throws {
    let config = pressureFixture()
    var market = try #require(config.markets.first)
    market.marketProofDebt.incumbentDefeatDeficit = 3
    var contender = try #require(config.tournamentContenders.first)
    contender.productPlan = "A generic assistant that does not compare the current workflow."

    let record = MarketPressureEvaluator.evaluate(
      kind: .incumbentDefense,
      market: market,
      contender: contender,
      tournamentID: contender.tournamentID,
      roundID: nil,
      now: Date(timeIntervalSince1970: 100)
    )

    try #require(record.verdict == .rejected || record.verdict == .needsReframe)
    try #require(record.proofDebtDelta.incumbentDefeatDelta > 0)
  }

  @Test func churnCritiqueIncreasesRetentionDebtWhenRepeatedUseIsWeak() throws {
    let config = pressureFixture()
    let market = try #require(config.markets.first)
    var contender = try #require(config.tournamentContenders.first)
    contender.productPlan = "One-time novelty for a single update."

    let record = MarketPressureEvaluator.evaluate(
      kind: .churnChallenge,
      market: market,
      contender: contender,
      tournamentID: contender.tournamentID,
      roundID: nil,
      now: Date(timeIntervalSince1970: 100)
    )

    try #require(record.proofDebtDelta.retentionDelta > 0)
    try #require(record.objections.contains { $0.contains("repeat usage") })
  }
}

func pressureFixture() -> ProductTournamentConfig {
  ProductTournamentConfig.seedDefaults(
    projectTitle: "Pressure Desk",
    rawPain: "Operations teams lose handoff context every week.",
    now: Date(timeIntervalSince1970: 1_700_000_000)
  )
}
