import Foundation
import Testing

@testable import Compass

struct MarketDecisionCockpitTests {
  @Test func missingMarketCreatesCompileMove() throws {
    let cockpit = MarketDecisionCockpit.build(
      config: ProductTournamentConfig.empty,
      evidenceIndex: .empty
    )

    try #require(cockpit.activeMarket == nil)
    try #require(cockpit.nextMarketMove?.kind == .compileMarket)
    try #require(cockpit.nextMarketMove?.actionTitle == "Compile synthetic market")
  }

  @Test func missingBuyerOutranksProductProof() throws {
    var config = seededConfig()
    config.markets[0].actors.removeAll {
      $0.role == .economicBuyer || $0.role == .managerSponsor
    }
    let planEvaluation = ProductTournamentPlanEvaluationRecord(
      id: "weak-plan",
      tournamentID: config.tournaments[0].id,
      roundID: config.tournamentRounds[1].id,
      contenderID: config.tournamentContenders[0].id,
      contenderPlanID: config.tournamentContenders[0].contenderPlanID,
      experimentID: config.tournamentExperiments[0].id,
      painID: config.painHypotheses[0].id,
      personaID: config.userSegments[0].id,
      personaName: "Operator",
      mode: .modelFree,
      startedAt: 100,
      endedAt: 110,
      scores: ProductTournamentEvidenceScores(
        painRecognition: 2,
        workflowImprovement: 2,
        alternativeAdvantage: 1,
        switchingReadiness: 1,
        continuedUsePull: 2,
        willingnessToPay: 1
      ),
      willingnessToPayScore: 1,
      estimatedMonthlyPriceCents: nil,
      objections: ["No buyer."],
      missingCapabilities: ["buyer proof"],
      currentAlternativeComparison: "Manual workflow wins.",
      verdict: .weak,
      summary: "Weak product proof."
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: [],
      planEvaluationRecords: [planEvaluation],
      now: Date(timeIntervalSince1970: 120)
    )

    let cockpit = MarketDecisionCockpit.build(config: config, evidenceIndex: index)

    try #require(cockpit.nextMarketMove?.kind == .resolveBuyer)
    try #require(cockpit.nextMarketMove?.actionTitle == "Resolve missing buyer actor")
  }

  @Test func failedIncumbentDefenseCreatesMarketMove() throws {
    let config = seededConfig()
    let pressure = marketPressure(
      config: config,
      kind: .incumbentDefense,
      verdict: .blocked,
      objection: "The incumbent already owns the workflow."
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: [],
      marketPressureRecords: [pressure],
      now: Date(timeIntervalSince1970: 120)
    )

    let cockpit = MarketDecisionCockpit.build(config: config, evidenceIndex: index)

    try #require(cockpit.nextMarketMove?.kind == .runIncumbentDefense)
    try #require(cockpit.nextMarketMove?.actionTitle == "Defend incumbent")
    try #require(cockpit.pressureRows.first?.strongestObjection.contains("incumbent") == true)
  }

  @Test func failedChannelProofCreatesChannelMove() throws {
    let config = seededConfig()
    let distribution = DistributionPressureRecord(
      id: "ignored-channel",
      experimentID: config.distributionExperiments[0].id,
      marketID: config.markets[0].id,
      contenderID: config.tournamentContenders[0].id,
      channelID: config.markets[0].channels[0].id,
      simulatedAudience: "Operators",
      verdict: .ignored,
      scores: DistributionScores(
        attention: 1,
        intentMatch: 1,
        credibility: 2,
        differentiation: 1,
        buyerReachability: 1,
        channelEconomics: 1
      ),
      objections: ["Cold outbound is ignored."],
      rewriteRecommendations: ["Try a warmer channel."],
      createdAt: 100
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: [],
      distributionPressureRecords: [distribution],
      now: Date(timeIntervalSince1970: 120)
    )
    let cockpit = MarketDecisionCockpit.build(config: config, evidenceIndex: index)

    try #require(cockpit.nextMarketMove?.kind == .runDistribution)
    try #require(cockpit.nextMarketMove?.actionTitle == "Try a different channel")
  }

  @Test func churnBlocksWinner() throws {
    var config = seededConfig()
    config.tournamentContenders[0].status = .winner
    let churnScenario = try #require(
      config.lifecycleScenarios.first {
        $0.cohortID == config.syntheticCohorts[0].id && $0.stageID.contains("renewal")
      })
    let churn = LifecycleRunRecord(
      id: "renewal-churn",
      cohortID: churnScenario.cohortID,
      scenarioID: churnScenario.id,
      marketID: config.markets[0].id,
      contenderID: config.tournamentContenders[0].id,
      actorID: config.markets[0].actors[0].id,
      stageID: churnScenario.stageID,
      outcome: .churned,
      scores: LifecycleScores(
        activation: 4,
        repeatedUse: 1,
        habitFit: 1,
        collaborationPull: 1,
        paymentReadiness: 1,
        renewalReadiness: 1,
        churnRisk: 5
      ),
      churnReason: "The team went back to the incumbent.",
      createdAt: 100
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: [],
      lifecycleRunRecords: [churn],
      now: Date(timeIntervalSince1970: 120)
    )

    let cockpit = MarketDecisionCockpit.build(config: config, evidenceIndex: index)

    try #require(cockpit.nextMarketMove?.kind == .resolveChurn)
    try #require(cockpit.nextMarketMove?.actionTitle == "Resolve churn reason")
    try #require(cockpit.nextMarketMove?.blockedReason == nil)
  }

  private func seededConfig() -> ProductTournamentConfig {
    ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 10)
    )
  }

  private func marketPressure(
    config: ProductTournamentConfig,
    kind: MarketPressureKind,
    verdict: MarketPressureVerdict,
    objection: String
  ) -> MarketPressureEvaluationRecord {
    MarketPressureEvaluationRecord(
      id: "pressure-\(kind.rawValue)",
      tournamentID: config.tournaments[0].id,
      roundID: config.tournamentRounds[0].id,
      marketID: config.markets[0].id,
      contenderID: config.tournamentContenders[0].id,
      pressureKind: kind,
      verdict: verdict,
      scores: MarketPressureScores(
        attention: 2,
        urgency: 2,
        incumbentAdvantage: 5,
        buyerClarity: 2,
        budgetFit: 2,
        trustReadiness: 2,
        channelFit: 2,
        retentionRisk: 4
      ),
      objections: [objection],
      proofDebtDelta: MarketProofDebtDelta(incumbentDefeatDelta: 1),
      transcriptSummary: "Market pressure blocked.",
      createdAt: 100
    )
  }
}
