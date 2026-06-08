import Foundation
import Testing

@testable import Compass

struct MarketCalibrationAggregateTests {
  @Test func computesOverconfidenceRate() throws {
    let aggregate = MarketCalibrationAggregate(runs: [
      makeRun(id: "miss-a", predicted: .breakout, actual: .failed, confidence: 5),
      makeRun(id: "miss-b", predicted: .durableNiche, actual: .featureAbsorbed, confidence: 4),
      makeRun(id: "hit-a", predicted: .durableNiche, actual: .durableNiche, confidence: 4),
    ])

    try #require(aggregate.runCount == 3)
    try #require(aggregate.correctCount == 1)
    try #require(aggregate.accuracyPercent == 33)
    try #require(aggregate.overconfidenceCount == 2)
    try #require(aggregate.overconfidenceRatePercent == 67)
  }

  @Test func identifiesRepeatedMissedMarketForce() throws {
    let aggregate = MarketCalibrationAggregate(runs: [
      makeRun(id: "miss-a", missedRisks: ["channel fit", "budget"]),
      makeRun(id: "miss-b", missedRisks: ["channel fit"]),
      makeRun(id: "miss-c", missedRisks: ["retention"]),
    ])

    try #require(aggregate.mostCommonMissedMarketForce == "channel fit")
    try #require(aggregate.warning?.contains("channel fit") == true)
  }

  @Test func emitsPlanningDigestWarning() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Calibration Harness",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 10)
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: [],
      marketBacktestRuns: [
        makeRun(id: "miss-a", missedRisks: ["channel fit"], createdAt: 200),
        makeRun(id: "miss-b", missedRisks: ["channel fit"], createdAt: 100),
      ],
      now: Date(timeIntervalSince1970: 300)
    )

    let digest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(digest.contains("Synthetic market calibration"))
    try #require(digest.contains("overconfidence 2/2"))
    try #require(digest.contains("channel fit"))
    try #require(digest.contains("Synthetic market has historically overestimated"))
  }

  private func makeRun(
    id: String,
    predicted: KnownProductOutcome = .breakout,
    actual: KnownProductOutcome = .failed,
    confidence: Int = 5,
    missedRisks: [String] = ["channel fit"],
    createdAt: Double = 100
  ) -> MarketBacktestRun {
    MarketBacktestRun(
      id: id,
      caseID: "\(id)-case",
      predictedOutcome: predicted,
      actualOutcome: actual,
      confidence: confidence,
      strongestReasons: ["channel fit"],
      missedRisks: missedRisks,
      overconfidenceFlags: confidence >= 4 && predicted != actual ? ["overconfident"] : [],
      compilerInputSummary: "Initial pain only.",
      createdAt: createdAt
    )
  }
}
