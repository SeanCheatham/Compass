import Foundation
import Testing

@testable import Compass

struct MarketPressureTransitionGateTests {
  @Test func roundOneBlocksWithoutPressureEvidence() throws {
    let index = ProductTournamentEvidenceIndex.empty

    try #require(
      MarketPressureTransitionGate.roundOneBlocker(
        contenderID: "contender-one",
        evidenceIndex: index
      )?.contains("buying committee") == true)
  }

  @Test func roundTwoBlocksOnRejectedIncumbentDefense() throws {
    let record = gatePressureRecord(kind: .incumbentDefense, verdict: .rejected)
    let index = ProductTournamentEvidenceIndex.build(
      records: [],
      marketPressureRecords: [record],
      now: Date(timeIntervalSince1970: 200)
    )

    try #require(
      MarketPressureTransitionGate.roundTwoBlocker(
        contenderID: "contender-one",
        evidenceIndex: index
      )?.contains("rejected") == true)
  }

  @Test func winnerBlocksOnUnresolvedChurnCritique() throws {
    let record = gatePressureRecord(
      kind: .churnChallenge,
      verdict: .blocked,
      proofDebtDelta: MarketProofDebtDelta(retentionDelta: 1)
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: [],
      marketPressureRecords: [record],
      now: Date(timeIntervalSince1970: 200)
    )

    try #require(
      MarketPressureTransitionGate.winnerBlocker(
        contenderID: "contender-one",
        evidenceIndex: index
      )?.contains("churn") == true)
  }
}

private func gatePressureRecord(
  kind: MarketPressureKind,
  verdict: MarketPressureVerdict,
  proofDebtDelta: MarketProofDebtDelta = .none
) -> MarketPressureEvaluationRecord {
  MarketPressureEvaluationRecord(
    id: "gate-\(kind.rawValue)",
    tournamentID: "tournament-one",
    roundID: "round-one",
    marketID: "market-one",
    contenderID: "contender-one",
    pressureKind: kind,
    verdict: verdict,
    scores: MarketPressureScores(
      attention: 3,
      urgency: 3,
      incumbentAdvantage: 5,
      buyerClarity: 2,
      budgetFit: 2,
      trustReadiness: 3,
      channelFit: 2,
      retentionRisk: 5
    ),
    objections: ["Blocked by market pressure."],
    proofDebtDelta: proofDebtDelta,
    requiredNextProof: ["Resolve market blocker."],
    transcriptSummary: "Gate pressure.",
    createdAt: 100
  )
}
