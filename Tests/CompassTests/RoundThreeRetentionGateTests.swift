import Foundation
import Testing

@testable import Compass

struct RoundThreeRetentionGateTests {
  @Test func winnerBlocksWithoutSecondUseProof() throws {
    let contenderID = "contender-one"
    let record = lifecycleRecord(
      contenderID: contenderID,
      outcome: .activated,
      repeatedUse: 1,
      paymentReadiness: 1,
      churnRisk: 2,
      churnReason: nil,
      createdAt: 100
    )
    let index = ProductTournamentEvidenceIndex.build(records: [], lifecycleRunRecords: [record])

    let blocker = RoundThreeRetentionGate.winnerBlocker(
      contenderID: contenderID,
      evidenceIndex: index
    )

    try #require(blocker?.contains("second-use proof") == true)
  }

  @Test func winnerBlocksWithUnresolvedChurn() throws {
    let contenderID = "contender-one"
    let record = lifecycleRecord(
      contenderID: contenderID,
      outcome: .churned,
      repeatedUse: 1,
      paymentReadiness: 1,
      churnRisk: 5,
      churnReason: "The job did not recur.",
      createdAt: 100
    )
    let index = ProductTournamentEvidenceIndex.build(records: [], lifecycleRunRecords: [record])

    let blocker = RoundThreeRetentionGate.winnerBlocker(
      contenderID: contenderID,
      evidenceIndex: index
    )

    try #require(blocker?.contains("Resolve churn reason") == true)
  }

  @Test func renewalProofCanClearPaymentRetentionGate() throws {
    let contenderID = "contender-one"
    let records = [
      lifecycleRecord(
        contenderID: contenderID,
        outcome: .activated,
        repeatedUse: 1,
        paymentReadiness: 1,
        churnRisk: 2,
        churnReason: nil,
        createdAt: 100
      ),
      lifecycleRecord(
        contenderID: contenderID,
        outcome: .renewed,
        repeatedUse: 5,
        paymentReadiness: 5,
        churnRisk: 1,
        churnReason: nil,
        createdAt: 200
      ),
    ]
    let index = ProductTournamentEvidenceIndex.build(records: [], lifecycleRunRecords: records)

    try #require(
      RoundThreeRetentionGate.winnerBlocker(contenderID: contenderID, evidenceIndex: index) == nil
    )
  }
}

private func lifecycleRecord(
  contenderID: String,
  outcome: LifecycleOutcome,
  repeatedUse: Int,
  paymentReadiness: Int,
  churnRisk: Int,
  churnReason: String?,
  createdAt: Double
) -> LifecycleRunRecord {
  LifecycleRunRecord(
    id: "lifecycle-\(outcome.rawValue)-\(Int(createdAt))",
    cohortID: "cohort-one",
    scenarioID: "scenario-one",
    marketID: "market-one",
    contenderID: contenderID,
    actorID: "actor-one",
    stageID: "stage-one",
    outcome: outcome,
    scores: LifecycleScores(
      activation: 4,
      repeatedUse: repeatedUse,
      habitFit: repeatedUse,
      collaborationPull: 2,
      paymentReadiness: paymentReadiness,
      renewalReadiness: paymentReadiness,
      churnRisk: churnRisk
    ),
    churnReason: churnReason,
    retainedReason: outcome == .retained || outcome == .renewed ? "The market came back." : nil,
    objections: churnReason.map { [$0] } ?? [],
    createdAt: createdAt
  )
}
