import Foundation
import Testing

@testable import Compass

struct ProductTournamentRoundOrderTests {
  @Test func newTournamentsStartAtMarketCompilation() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Round Order",
      rawPain: "Leads lose handoff context.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let tournament = try #require(config.tournaments.first)
    let readModel = ProductTournamentReadModel(config: config)

    try #require(config.marketCompilationStatus == .compiled)
    try #require(config.tournamentRounds.map(\.kind).first == .marketCompilation)
    try #require(tournament.currentRoundID == config.tournamentRounds[0].id)
    try #require(readModel.activeRound(in: tournament)?.kind == .marketCompilation)
  }

  @Test func productPlanRoundIsBlockedUntilMarketIsCompiled() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Round Gate",
      rawPain: "Leads lose handoff context.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    config.markets = []
    let evidenceIndex = ProductTournamentEvidenceIndex.empty

    try #require(config.marketCompilationStatus == .missing)
    try #require(
      TournamentAutomationProofTargetAdvisor.targets(
        config: config,
        evidenceIndex: evidenceIndex
      ).isEmpty)
  }
}
